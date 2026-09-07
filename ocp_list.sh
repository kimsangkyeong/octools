#!/bin/bash
####################################################################################################
##
## File name   : ocp_list.sh
## Description : OCP release / Operator 카탈로그 조회 및 Operator 업그레이드 영향도 분석 도구.
##               - OCP 버전(예: 4.21, 4.22) 기준으로 release 목록과 Operator 카탈로그(index)를
##                 opm render(공식) 로 조회하여 JSON 으로 저장하고, default 채널/버전만 추려서
##                 표 형식 txt 로 정리한다.
##               - 클러스터에 설치된 Operator 를 조회/선택(또는 수동 입력)하고, 여러 OCP 버전을
##                 기준으로 채널/minVersion/maxVersion/현재버전/판정(Verdict)을 표로 비교하여
##                 업그레이드 영향도를 사전 분석한다. (check-operator-version.txt)
## Information : - 저장 루트: $HOME/workdir/ocpcatalogs (로컬 변수 WORKDIR 로 정의, 변경 가능)
##               - 버전별 하위 폴더: ocp<버전> (예: ocp4.21) 아래에 결과 파일 저장.
##                   release  : release.json / release.txt
##                   operator : <index>.json / <index>.txt
##                   영향도   : check-operator-version.txt (최하위 버전부터 상위 버전 컬럼)
##               - 데이터 소스: opm render(공식) 우선, 클러스터 현재 정보는 oc 로 조회.
##               - 메뉴가 많으면 화면 2분할 + 페이지네이션. 선택/직접입력(콤마 복수) 지원.
##               - signal 처리 로그는 $HOME/tmp 아래에 저장.
##
##==================================================================================================
##  version   date             author          reason
##--------------------------------------------------------------------------------------------------
##  1.0       2026.08.16       k.s.k & kiro     First Created
##  1.1       2026.08.16       k.s.k & kiro     영향도 분석 진입 시 클러스터 사용여부 확인 및
##                                              oc 로그인 사전 점검/가이드(재확인 루프) 추가
##  1.2       2026.08.16       k.s.k & kiro     JSON 을 jq 로 pretty-print 저장,
##                                              TXT 산출물에 조회 명령어/판정 로직 기준
##                                              Information 섹션 추가
##  1.3       2026.08.16       k.s.k & kiro     olm.maxOpenShiftVersion / olm.openshift.versions
##                                              기반 OCP 호환성 판정(업그레이드차단/호환범위밖) 추가,
##                                              속성 없으면 none 으로 치환 후 채널/semver 폴백
##  1.4       2026.09.07       k.s.k & kiro     operator catalog txt 에 DESCRIPTION 컬럼 추가,
##                                              영향도 비교 표를 2단 헤더(OCP버전 / CHANNEL·MINVERSION·
##                                              MAXVERSION·VERDICT)로 개선하여 가독성 향상
##
####################################################################################################

# ======<<<< Signal common processing logic (Start) >>>>=============================================
logdatefmt="%Y%m%d-%H:%M:%S"                 # 로깅용 날짜/시간 포맷
logdir="${HOME}/tmp"                          # signal 로그 저장 폴더
[ -d "${logdir}" ] || mkdir -p "${logdir}" 2>/dev/null
logfnm="${logdir}/$(basename "$0").log"       # signal 로그 파일 전체 경로

trap ' echo "$(date +${logdatefmt}) $0 signal(SIGINT ) captured" | tee -a "${logfnm}"; exit 1;' SIGINT
trap ' echo "$(date +${logdatefmt}) $0 signal(SIGQUIT) captured" | tee -a "${logfnm}"; exit 1;' SIGQUIT
trap ' echo "$(date +${logdatefmt}) $0 signal(SIGTERM) captured" | tee -a "${logfnm}"; exit 1;' SIGTERM
# ======<<<< Signal common processing logic (End) >>>>===============================================

# ======<<<< Important Global Variable Registration Area (Start) >>>>================================
# 색상 코드 (강조/비정상 표시)
C_RED='\033[0;91m'      ; C_GREEN='\033[0;92m' ; C_YELLOW='\033[0;93m'
C_BLUE='\033[0;94m'     ; C_CYAN='\033[0;96m'  ; C_WHITE='\033[0;97m'
C_BOLD='\033[1m'        ; C_RESET='\033[0m'

# 결과 저장 루트 디렉토리 (요구사항4: 로컬 변수로 정의, 기본값 $HOME/workdir/ocpcatalogs)
WORKDIR="${HOME}/workdir/ocpcatalogs"

# Operator 카탈로그 index 레지스트리 베이스 (요구사항5: opm 공식 방식)
# 실제 태그는 버전에 맞춰 v<major.minor> 로 조립한다. (예: v4.22)
REG_BASE="registry.redhat.io/redhat"

# 대표 Operator 카탈로그 index 목록 (요구사항6: 직접 입력이 어려우므로 선택 제공)
# 형식: "index이미지명" (레지스트리/태그는 코드에서 조립)
CATALOG_INDEXES=(
  "redhat-operator-index"
  "certified-operator-index"
  "community-operator-index"
  "redhat-marketplace-index"
)

# OCP release 조회용 그래프/이미지 (release 목록 확인용)
# release 정보는 oc adm release / opm 조합으로 조회하며, 환경에 따라 조정 가능하다.
RELEASE_REG_BASE="quay.io/openshift-release-dev/ocp-release"

# 메뉴 레이아웃
ITEMS_PER_COL=10                              # 한 열 최대 항목 수
MENU_COLS=2                                   # 화면 열 개수 (이분할)
ITEMS_PER_PAGE=$(( ITEMS_PER_COL * MENU_COLS ))

# oc 로그인 확인 캐시 (0=미확인, 1=확인)
OC_LOGIN_CHECKED=0
# 클러스터 사용 모드 (1=클러스터 연동 사용, 0=오프라인/수동) : 영향도 분석 진입 시 결정
USE_CLUSTER=0

# 렌더링 공용 배열/변수 (메뉴 함수에서 사용)
RENDER_ITEMS=()
RENDER_TOTAL_PAGES=1
# ======<<<< Important Global Variable Registration Area (End) >>>>==================================

# ======<<<< Function Registration Area (Start) >>>>================================================

######################################################################################################
##  Function Name : get_term_width
##  Description : 현재 터미널 열 너비를 반환한다. (조회 불가 시 100)
##  information : input none / output 터미널 너비(숫자)
######################################################################################################
get_term_width()
{
  local w
  w=$(tput cols 2>/dev/null)
  if [ -z "${w}" ] || [ "${w}" -lt 40 ]; then
    w=100
  fi
  echo "${w}"
}

######################################################################################################
##  Function Name : print_line
##  Description : 터미널 너비만큼 구분선을 출력한다.
##  information : input $1=구분문자(기본 '=') / output 구분선
######################################################################################################
print_line()
{
  local ch="${1:-=}"
  local width
  width=$(get_term_width)
  printf "%${width}s\n" "" | tr ' ' "${ch}"
}

######################################################################################################
##  Function Name : print_title
##  Description : 화면 상단 타이틀 배너를 출력한다. (화면 clear 포함)
##  information : input $1=타이틀 문자열 / output 배너
######################################################################################################
print_title()
{
  local title="$1"
  clear
  print_line "="
  printf "${C_BOLD}  %s${C_RESET}\n" "${title}"
  print_line "="
  echo ""
}

######################################################################################################
##  Function Name : print_info / print_warn / print_error
##  Description : 정보/경고/오류 메시지를 색상으로 출력한다.
##  information : input $1=메시지 / output 색상 메시지 (warn/error 는 stderr)
######################################################################################################
print_info()  { printf "${C_BOLD}  %s${C_RESET}\n" "$1"; }
print_warn()  { printf "${C_BOLD}  [WARN] %s${C_RESET}\n" "$1" >&2; }
print_error() { printf "${C_BOLD}  [ERROR] %s${C_RESET}\n" "$1" >&2; }
print_ok()    { printf "${C_BOLD}  %s${C_RESET}\n" "$1"; }

######################################################################################################
##  Function Name : pause_enter
##  Description : 사용자가 결과를 확인하도록 Enter 입력을 대기한다. (EOF 시 정상 반환)
##  information : input none / output none
######################################################################################################
pause_enter()
{
  echo ""
  printf "  ${C_BOLD}[Enter] 계속...${C_RESET}"
  read -r _dummy || return 0
}

######################################################################################################
##  Function Name : ask_input
##  Description : 사용자로부터 값을 입력받는다. (기본값 지원)
##  information : input $1=프롬프트, $2=결과변수명, $3=(선택)기본값
##                output 입력값을 $2 변수에 저장. 빈 입력 시 기본값 사용.
######################################################################################################
ask_input()
{
  local prompt="$1"
  local __resultvar="$2"
  local defval="$3"
  local input

  if [ -n "${defval}" ]; then
    printf "  ${C_BOLD}%s [기본: %s]: ${C_RESET}" "${prompt}" "${defval}"
  else
    printf "  ${C_BOLD}%s: ${C_RESET}" "${prompt}"
  fi
  read -r input || input=""
  [ -z "${input}" ] && input="${defval}"
  eval "${__resultvar}=\"\${input}\""
}

######################################################################################################
##  Function Name : confirm_run
##  Description : y/N 확인을 받는다.
##  information : input $1=확인 메시지 / output 0=진행, 1=취소
######################################################################################################
confirm_run()
{
  local msg="${1:-계속하시겠습니까?}"
  local ans
  printf "${C_BOLD}  %s (y/N): ${C_RESET}" "${msg}"
  read -r ans || ans=""
  case "${ans}" in
    y|Y|yes|YES) return 0 ;;
    *) echo "  취소되었습니다."; return 1 ;;
  esac
}

######################################################################################################
##  Function Name : show_exec_cmd
##  Description : 실제 실행되는 명령어(실행문)를 학습용으로 표시한다.
##  information : input $1=명령어 문자열 / output "[실행문: ...]"
######################################################################################################
show_exec_cmd()
{
  echo ""
  printf "${C_BOLD}[실행문: %s]${C_RESET}\n" "$1"
  print_line "-"
}

######################################################################################################
##  Function Name : check_cmd_exist
##  Description : 필요한 실행 파일 설치 여부를 확인한다.
##  information : input $1=명령어명 / output 0=존재, 1=없음(메시지)
######################################################################################################
check_cmd_exist()
{
  local c="$1"
  if ! command -v "${c}" >/dev/null 2>&1; then
    print_error "[${c}] 명령을 찾을 수 없습니다. 설치 또는 PATH를 확인하세요."
    return 1
  fi
  return 0
}

######################################################################################################
##  Function Name : check_dependencies
##  Description : 시작 시 필수/권장 도구 설치 여부를 점검하여 안내한다.
##  information : input none / output 경고 메시지 (차단하지 않음)
##                필수: jq  / 권장: opm, oc
######################################################################################################
check_dependencies()
{
  local miss_req="" miss_opt=""
  command -v jq  >/dev/null 2>&1 || miss_req="${miss_req} jq"
  command -v opm >/dev/null 2>&1 || miss_opt="${miss_opt} opm"
  command -v oc  >/dev/null 2>&1 || miss_opt="${miss_opt} oc"

  if [ -n "${miss_req}" ]; then
    print_warn "필수 도구 미설치:${miss_req} (JSON 파싱에 jq가 필요합니다)"
  fi
  if [ -n "${miss_opt}" ]; then
    print_warn "권장 도구 미설치:${miss_opt} (카탈로그 조회/클러스터 조회에 필요)"
  fi
  if [ -n "${miss_req}${miss_opt}" ]; then
    echo ""
    sleep 1
  fi
}

######################################################################################################
##  Function Name : check_oc_login
##  Description : oc 로그인 여부를 사전 점검하고, 미로그인 시 로그인 방법을 가이드한다.
##                (요구사항9: oc 가 필요한 기능은 사전에 로그인 여부를 점검하고 안내하여,
##                 미로그인 상태에서 나오는 원시 에러 메시지가 노출되지 않도록 품질을 높인다.)
##                미로그인 시 안내 후, 다른 터미널에서 로그인한 뒤 [r]재확인, [s]건너뛰기 를 지원.
##  information : input none / output 0=로그인됨(사용가능), 1=미로그인/건너뛰기
######################################################################################################
check_oc_login()
{
  check_cmd_exist "oc" || return 1
  # 세션당 1회 확인되면 캐시 사용 (성능)
  if [ "${OC_LOGIN_CHECKED}" = "1" ]; then
    return 0
  fi
  if oc whoami >/dev/null 2>&1; then
    OC_LOGIN_CHECKED=1
    return 0
  fi

  # 미로그인 -> 가이드 + 재확인 루프
  local ans
  while true; do
    echo ""
    print_error "oc 로그인이 되어 있지 않습니다. 이 기능은 클러스터 접속이 필요합니다."
    printf "${C_BOLD}  아래 방법으로 먼저 로그인하세요 (별도 터미널 가능):${C_RESET}\n"
    echo "    oc login https://<api-server>:6443 -u <user> -p <pass>"
    echo "    또는  oc login --token=<token> --server=https://<api-server>:6443"
    echo ""
    printf "  ${C_BOLD}[r] 로그인 후 재확인   [s] 건너뛰기(클러스터 미사용)   [b] 취소: ${C_RESET}"
    read -r ans || return 1
    case "${ans}" in
      r|R)
        if oc whoami >/dev/null 2>&1; then
          OC_LOGIN_CHECKED=1
          print_ok "로그인 확인됨: $(oc whoami 2>/dev/null) @ $(oc whoami --show-server 2>/dev/null)"
          return 0
        else
          print_warn "아직 로그인되어 있지 않습니다. 다시 시도하세요."
        fi
        ;;
      s|S) return 1 ;;   # 건너뛰기 (호출부에서 수동입력 등으로 대체)
      b|B) return 1 ;;
      *) ;;
    esac
  done
}

######################################################################################################
##  Function Name : ensure_version_dir
##  Description : 버전별 결과 저장 디렉토리($WORKDIR/ocp<버전>)를 생성하고 경로를 반환한다.
##  information : input $1=버전(예: 4.22), $2=결과변수명 / output 0=성공(경로 저장), 1=실패
######################################################################################################
ensure_version_dir()
{
  local ver="$1"
  local __resultvar="$2"
  local dir="${WORKDIR}/ocp${ver}"
  if ! mkdir -p "${dir}" 2>/dev/null; then
    print_error "디렉토리 생성 실패: ${dir}"
    return 1
  fi
  eval "${__resultvar}=\"\${dir}\""
  return 0
}

######################################################################################################
##  Function Name : normalize_version
##  Description : 입력 버전 문자열을 major.minor 형태로 정규화한다. (예: v4.22 -> 4.22)
##  information : input $1=버전문자열, $2=결과변수명 / output 정규화 버전 저장
######################################################################################################
normalize_version()
{
  local raw="$1"
  local __resultvar="$2"
  local v
  # 앞의 v 제거, 앞뒤 공백 제거, major.minor 만 추출
  v=$(echo "${raw}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//; s/^v//')
  v=$(echo "${v}" | grep -oE '^[0-9]+\.[0-9]+' | head -1)
  eval "${__resultvar}=\"\${v}\""
}

######################################################################################################
##  Function Name : render_paged_menu
##  Description : RENDER_ITEMS[] 항목을 화면 2분할 + 페이지 단위로 출력한다.
##                (요구사항: 목록이 많으면 이분할/페이지로 누락 없이 탐색)
##  information : input $1=제목, $2=페이지(0-base), $3=(선택)하단 안내 추가문구
##                output 화면 출력, RENDER_TOTAL_PAGES 에 총 페이지 수 저장.
######################################################################################################
render_paged_menu()
{
  local title="$1"
  local page="$2"
  local extra_help="$3"
  local total=${#RENDER_ITEMS[@]}
  local total_pages=$(( (total + ITEMS_PER_PAGE - 1) / ITEMS_PER_PAGE ))
  [ ${total_pages} -lt 1 ] && total_pages=1
  RENDER_TOTAL_PAGES=${total_pages}

  [ ${page} -lt 0 ] && page=0
  [ ${page} -ge ${total_pages} ] && page=$(( total_pages - 1 ))

  local start=$(( page * ITEMS_PER_PAGE ))
  local width col_width
  width=$(get_term_width)
  col_width=$(( width / 2 - 2 ))

  print_title "${title}"

  local row
  for (( row=0; row<ITEMS_PER_COL; row++ )); do
    local lidx=$(( start + row ))
    local ridx=$(( start + ITEMS_PER_COL + row ))
    local ltext="" rtext=""
    if [ ${lidx} -lt ${total} ]; then
      ltext=$(printf "  [%3d] %s" "$(( lidx + 1 ))" "${RENDER_ITEMS[${lidx}]}")
    fi
    if [ ${ridx} -lt ${total} ]; then
      rtext=$(printf "  [%3d] %s" "$(( ridx + 1 ))" "${RENDER_ITEMS[${ridx}]}")
    fi
    if [ -z "${ltext}" ] && [ -z "${rtext}" ]; then
      continue
    fi
    printf "${C_BOLD}%-${col_width}s${C_RESET}| ${C_BOLD}%s${C_RESET}\n" "${ltext}" "${rtext}"
  done

  echo ""
  print_line "-"
  printf "${C_BOLD}  페이지 %d/%d  |  [n]다음 [p]이전 [b]뒤로 [q]종료${C_RESET}\n" "$(( page + 1 ))" "${total_pages}"
  [ -n "${extra_help}" ] && printf "${C_BOLD}  %s${C_RESET}\n" "${extra_help}"
  print_line "-"
}

######################################################################################################
##  Function Name : select_from_list
##  Description : 페이지형 메뉴에서 단일 항목 선택(번호/네비게이션)을 처리한다.
##  information : input $1=제목, $2=결과변수명(0-base 인덱스) / output 0=선택, 1=뒤로, 2=종료
##                표시 항목은 전역 RENDER_ITEMS[] 에 미리 채운다.
######################################################################################################
select_from_list()
{
  local title="$1"
  local __resultvar="$2"
  local page=0
  local total=${#RENDER_ITEMS[@]}
  local input

  while true; do
    render_paged_menu "${title}" "${page}"
    echo ""
    printf "  ${C_BOLD}선택(번호): ${C_RESET}"
    if ! read -r input; then return 2; fi
    case "${input}" in
      q|Q) return 2 ;;
      b|B) return 1 ;;
      n|N) [ $(( page + 1 )) -lt ${RENDER_TOTAL_PAGES} ] && page=$(( page + 1 )) ;;
      p|P) [ ${page} -gt 0 ] && page=$(( page - 1 )) ;;
      ''|*[!0-9]*) ;;
      *)
        if [ "${input}" -ge 1 ] && [ "${input}" -le ${total} ]; then
          eval "${__resultvar}=$(( input - 1 ))"
          return 0
        fi
        ;;
    esac
  done
}

######################################################################################################
##  Function Name : select_multi_from_list
##  Description : 페이지형 메뉴에서 복수 선택을 처리한다.
##                번호(콤마/공백 구분 복수), 'a'(전체선택), 'm'(수동 입력 콤마 복수)을 지원한다.
##                (요구사항8: 일부/전체 선택 + 목록 외 수동입력 콤마 복수 허용)
##  information : input $1=제목, $2=결과변수명(선택된 라벨을 개행으로 저장)
##                output 0=선택완료, 1=뒤로, 2=종료
######################################################################################################
select_multi_from_list()
{
  local title="$1"
  local __resultvar="$2"
  local page=0
  local total=${#RENDER_ITEMS[@]}
  local input
  local help="[a]전체선택  [m]수동입력(콤마복수)  |  번호는 콤마/공백으로 복수 선택 가능"

  while true; do
    render_paged_menu "${title}" "${page}" "${help}"
    echo ""
    printf "  ${C_BOLD}선택: ${C_RESET}"
    if ! read -r input; then return 2; fi

    case "${input}" in
      q|Q) return 2 ;;
      b|B) return 1 ;;
      n|N) [ $(( page + 1 )) -lt ${RENDER_TOTAL_PAGES} ] && page=$(( page + 1 )); continue ;;
      p|P) [ ${page} -gt 0 ] && page=$(( page - 1 )); continue ;;
      a|A)
        # 전체 선택
        local out="" it
        for it in "${RENDER_ITEMS[@]}"; do
          out="${out}${it}"$'\n'
        done
        eval "${__resultvar}=\"\${out}\""
        return 0
        ;;
      m|M)
        # 수동 입력 (콤마 복수)
        local manual
        ask_input "package 이름 수동 입력 (콤마로 복수, 예: a-operator,b-operator)" manual ""
        [ -z "${manual}" ] && continue
        local out="" tok
        IFS=',' read -r -a __toks <<< "${manual}"
        for tok in "${__toks[@]}"; do
          tok=$(echo "${tok}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
          [ -n "${tok}" ] && out="${out}${tok}"$'\n'
        done
        eval "${__resultvar}=\"\${out}\""
        return 0
        ;;
      '') continue ;;
      *)
        # 번호(콤마/공백 복수) 파싱
        local out="" num
        local cleaned
        cleaned=$(echo "${input}" | tr ',' ' ')
        local valid=1
        for num in ${cleaned}; do
          case "${num}" in
            ''|*[!0-9]*) valid=0; break ;;
          esac
          if [ "${num}" -lt 1 ] || [ "${num}" -gt ${total} ]; then valid=0; break; fi
          out="${out}${RENDER_ITEMS[$(( num - 1 ))]}"$'\n'
        done
        if [ ${valid} -eq 1 ] && [ -n "${out}" ]; then
          eval "${__resultvar}=\"\${out}\""
          return 0
        fi
        ;;
    esac
  done
}

# --------------------------------------------------------------------------------------------------
# [기능A-1] OCP release 카탈로그 조회
#   - OpenShift Update Service(Cincinnati) graph API 를 사용하여 채널별 버전 목록을 조회한다.
#     endpoint: https://api.openshift.com/api/upgrades_info/v1/graph?channel=<channel>&arch=<arch>
#   - 응답 구조: { "nodes":[{"version","payload","metadata"}...], "edges":[[from,to]...] }
#   - 결과: $WORKDIR/ocp<버전>/release.json (원본), release.txt (default 채널/버전 표)
# --------------------------------------------------------------------------------------------------

######################################################################################################
##  Function Name : func_release_catalog
##  Description : 입력한 OCP 버전(예: 4.22)의 release 목록을 조회하여 JSON/TXT 로 저장한다.
##                default 지원 채널(stable)을 기준으로 버전 목록을 표로 정리한다.
##  information : input none(대화형) / output release.json, release.txt
######################################################################################################
func_release_catalog()
{
  check_cmd_exist "curl" || { pause_enter; return 1; }
  check_cmd_exist "jq"   || { pause_enter; return 1; }

  local raw ver arch
  ask_input "조회할 OCP 버전 (예: 4.22)" raw ""
  normalize_version "${raw}" ver
  if [ -z "${ver}" ]; then
    print_error "버전 형식이 올바르지 않습니다. (예: 4.22)"
    pause_enter; return 1
  fi
  ask_input "아키텍처(arch)" arch "amd64"

  local vdir
  ensure_version_dir "${ver}" vdir || { pause_enter; return 1; }

  local json_file="${vdir}/release.json"
  local txt_file="${vdir}/release.txt"

  # 조회 대상 채널: default 는 stable. 함께 fast/eus/candidate 도 수집하여 참고 제공.
  local channels="stable fast eus candidate"
  local api="https://api.openshift.com/api/upgrades_info/v1/graph"

  print_info "release 정보를 조회합니다. (채널: ${channels})"
  show_exec_cmd "curl -sH 'Accept: application/json' '${api}?channel=stable-${ver}&arch=${arch}'"

  # 채널별 JSON 을 하나의 객체로 병합 저장
  local tmp_all ch chan_full resp
  tmp_all="{}"
  for ch in ${channels}; do
    chan_full="${ch}-${ver}"
    resp=$(curl -s -H 'Accept: application/json' "${api}?channel=${chan_full}&arch=${arch}" 2>/dev/null)
    # 유효한 JSON 인지 확인 후 병합
    if echo "${resp}" | jq -e . >/dev/null 2>&1; then
      tmp_all=$(echo "${tmp_all}" | jq --arg ch "${ch}" --argjson data "${resp}" '. + {($ch): $data}')
    else
      tmp_all=$(echo "${tmp_all}" | jq --arg ch "${ch}" '. + {($ch): {"nodes":[],"edges":[]}}')
    fi
  done

  # 메타(조회 정보) 포함하여 저장
  echo "${tmp_all}" | jq --arg ver "${ver}" --arg arch "${arch}" --arg ts "$(date '+%Y-%m-%d %H:%M:%S')" \
    '{queried_version:$ver, arch:$arch, queried_at:$ts, channels:.}' > "${json_file}" 2>/dev/null

  if [ ! -s "${json_file}" ]; then
    print_error "release.json 저장 실패 또는 응답이 비어있습니다. 네트워크/프록시를 확인하세요."
    pause_enter; return 1
  fi

  # ---- release.txt 표 작성 (default 채널 = stable 기준 버전 목록) --------------------------------
  {
    echo "# OCP Release Catalog"
    echo "# queried_version : ${ver}"
    echo "# arch            : ${arch}"
    echo "# queried_at       : $(date '+%Y-%m-%d %H:%M:%S')"
    echo "# os_user          : $(whoami)"
    echo "# default_channel  : stable-${ver}"
    echo "#"
    echo "# [Information] 기초 데이터 조회 방법"
    echo "#   - 데이터 소스 : OpenShift Update Service (Cincinnati) graph API"
    echo "#   - 조회 명령   : curl -sH 'Accept: application/json' \\"
    echo "#                     '${api}?channel=<channel>-${ver}&arch=${arch}'"
    echo "#   - 조회 채널   : ${channels}  (default 표기는 stable 기준)"
    echo "#   - 원본 JSON   : $(basename "${json_file}")  (jq 로 pretty-print 저장)"
    echo "#"
    printf "%-16s | %-10s | %s\n" "VERSION" "CHANNEL" "PAYLOAD_DIGEST(short)"
    printf -- "-----------------+------------+---------------------------------------------\n"
    # stable 채널 버전을 정렬하여 출력 (없으면 fast 로 대체 안내)
    local vers
    vers=$(jq -r '.channels.stable.nodes[]?.version' "${json_file}" 2>/dev/null | sort -V)
    if [ -z "${vers}" ]; then
      echo "(stable 채널에 데이터가 없습니다. fast/eus/candidate 채널을 참고하세요.)"
    else
      local v pay
      while IFS= read -r v; do
        [ -z "${v}" ] && continue
        pay=$(jq -r --arg v "${v}" '.channels.stable.nodes[]? | select(.version==$v) | .payload' "${json_file}" 2>/dev/null | head -1)
        # digest 짧게 표시
        pay=$(echo "${pay}" | sed 's/.*@sha256:／/sha256:/; s/.*@//' | cut -c1-20)
        printf "%-16s | %-10s | %s\n" "${v}" "stable" "${pay}"
      done <<< "${vers}"
    fi
    echo ""
    echo "# --- 채널별 버전 개수 요약 ---"
    local c cnt
    for c in stable fast eus candidate; do
      cnt=$(jq -r --arg c "${c}" '.channels[$c].nodes | length' "${json_file}" 2>/dev/null)
      printf "  %-10s : %s versions\n" "${c}" "${cnt:-0}"
    done
  } > "${txt_file}"

  clear
  print_title "OCP Release 조회 결과 - ${ver}"
  cat "${txt_file}"
  echo ""
  print_ok "저장 완료:"
  echo "    JSON : ${json_file}"
  echo "    TXT  : ${txt_file}"
  pause_enter
}

# --------------------------------------------------------------------------------------------------
# [기능A-2] Operator 카탈로그(index) 조회
#   - opm render <catalog_index_image> 로 카탈로그 전체를 JSON 스트림으로 받아 저장한다.
#     (요구사항5: opm 공식 방식)
#   - 스키마: olm.package(name, defaultChannel), olm.channel(package, name, entries[]),
#             olm.bundle(name, ...). 채널 head(최신) = 다른 entry 의 replaces/skips 대상이 아닌 entry.
#   - 결과: $WORKDIR/ocp<버전>/<index>.json (원본 스트림), <index>.txt (default 채널/최신버전 표)
# --------------------------------------------------------------------------------------------------

######################################################################################################
##  Function Name : jq_channel_head_filter
##  Description : olm.channel 의 entries 에서 채널 head(최신 버전)를 구하는 jq 표현식을 반환한다.
##                head = 자신의 name 이 다른 entry 의 replaces 또는 skips 에 등장하지 않는 entry.
##                여러 개면 semver 상 마지막을 택한다.
##  information : input none / output jq 필터 문자열 (echo)
######################################################################################################
jq_channel_head_filter()
{
  # 입력: 하나의 olm.channel 객체 (.entries[] 보유)
  # 출력: head entry 의 name (문자열)
  cat <<'JQF'
    (.entries // []) as $e
    | ($e | map(.replaces) | map(select(. != null))) as $rep
    | ($e | map(.skips // []) | add // []) as $skp
    | ($rep + $skp) as $covered
    | [ $e[].name | select( ([.] - $covered) == [.] and ( . as $n | ($covered | index($n)) | not ) ) ]
    | (if length>0 then (sort_by(.) | last) else ($e | last | .name) end)
JQF
}

######################################################################################################
##  Function Name : func_operator_catalog
##  Description : OCP 버전과 카탈로그 index 를 선택/입력받아 opm render 로 JSON 을 저장하고,
##                패키지별 defaultChannel 과 채널 head(최신 버전)를 표(txt)로 정리한다.
##  information : input none(대화형) / output <index>.json, <index>.txt
######################################################################################################
func_operator_catalog()
{
  check_cmd_exist "opm" || { pause_enter; return 1; }
  check_cmd_exist "jq"  || { pause_enter; return 1; }

  local raw ver
  ask_input "조회할 OCP 버전 (예: 4.22)" raw ""
  normalize_version "${raw}" ver
  if [ -z "${ver}" ]; then
    print_error "버전 형식이 올바르지 않습니다. (예: 4.22)"
    pause_enter; return 1
  fi

  # ---- index 선택 (목록) 또는 직접 입력 (요구사항6) --------------------------------------------
  local index_name=""
  echo ""
  printf "  ${C_BOLD}Operator 카탈로그 index 지정: [1] 목록에서 선택  [2] 직접 입력${C_RESET}\n"
  printf "  ${C_BOLD}선택: ${C_RESET}"
  local ich
  read -r ich || ich="1"
  if [ "${ich}" = "2" ]; then
    ask_input "index 이미지명 (예: redhat-operator-index)" index_name ""
  else
    RENDER_ITEMS=()
    local ci
    for ci in "${CATALOG_INDEXES[@]}"; do
      RENDER_ITEMS+=( "${ci}" )
    done
    local idx
    select_from_list "Operator 카탈로그 index 선택" idx
    [ $? -ne 0 ] && return 1
    index_name="${RENDER_ITEMS[${idx}]}"
  fi
  [ -z "${index_name}" ] && { print_error "index 가 지정되지 않았습니다."; pause_enter; return 1; }

  # 카탈로그 이미지 전체 경로 조립 (레지스트리/버전태그)
  local image="${REG_BASE}/${index_name}:v${ver}"

  local vdir
  ensure_version_dir "${ver}" vdir || { pause_enter; return 1; }
  local json_file="${vdir}/${index_name}.json"
  local txt_file="${vdir}/${index_name}.txt"

  print_info "opm render 로 카탈로그를 조회합니다. (다소 시간이 걸릴 수 있습니다)"
  show_exec_cmd "opm render ${image} | jq . > ${json_file}"

  # opm render 는 JSON 문서 스트림(객체 연속)을 출력한다.
  # jq . 로 각 객체를 보기 좋게(pretty-print) 저장한다. (스트림 구조는 유지되어 후속 파싱 호환)
  local raw_tmp="${vdir}/.${index_name}.raw"
  if ! opm render "${image}" > "${raw_tmp}" 2>"${vdir}/.opm_err"; then
    print_error "opm render 실패: $(cat "${vdir}/.opm_err" 2>/dev/null | head -3)"
    rm -f "${vdir}/.opm_err" "${raw_tmp}"
    pause_enter; return 1
  fi
  rm -f "${vdir}/.opm_err"

  if [ ! -s "${raw_tmp}" ]; then
    print_error "조회 결과가 비어 있습니다. index/버전/레지스트리 로그인을 확인하세요."
    rm -f "${raw_tmp}"
    pause_enter; return 1
  fi

  # jq 로 pretty-print 하여 저장 (실패 시 원본 그대로 저장)
  if jq . "${raw_tmp}" > "${json_file}" 2>/dev/null && [ -s "${json_file}" ]; then
    rm -f "${raw_tmp}"
  else
    mv -f "${raw_tmp}" "${json_file}"
  fi

  # ---- <index>.txt 표 작성 (패키지별 defaultChannel / 채널 head) --------------------------------
  local head_filter
  head_filter=$(jq_channel_head_filter)

  {
    echo "# OCP Operator Catalog"
    echo "# index           : ${index_name}"
    echo "# image           : ${image}"
    echo "# ocp_version      : ${ver}"
    echo "# queried_at       : $(date '+%Y-%m-%d %H:%M:%S')"
    echo "# os_user          : $(whoami)"
    echo "#"
    echo "# [Information] 기초 데이터 조회 방법"
    echo "#   - 데이터 소스   : Operator 카탈로그 index 이미지 (File-Based Catalog)"
    echo "#   - 조회 명령     : opm render ${image} | jq . > $(basename "${json_file}")"
    echo "#   - 원본 JSON     : $(basename "${json_file}")  (jq 로 pretty-print 저장)"
    echo "#   - DEFAULT_CHANNEL      : olm.package.defaultChannel"
    echo "#   - DEFAULT_CHANNEL_HEAD : 해당 채널 entries 중 다른 entry 의 replaces/skips 대상이"
    echo "#                            아닌 최신(semver 최대) 번들 = 채널 head(설치 시 기본 버전)"
    echo "#   - DESCRIPTION          : olm.package.description (패키지 용도, 축약 표시)"
    echo "#"
    printf "%-45s | %-22s | %-30s | %s\n" "PACKAGE" "DEFAULT_CHANNEL" "DEFAULT_CHANNEL_HEAD(latest)" "DESCRIPTION"
    printf -- "----------------------------------------------+------------------------+--------------------------------+--------------------------------------------------\n"

    # 패키지 목록과 defaultChannel, description 추출 (olm.package)
    # 각 패키지의 defaultChannel head 는 해당 채널 entries 에서 계산
    jq -rs --arg hf "dummy" '
      ( [ .[] | select(.schema=="olm.package") ] ) as $pkgs
      | ( [ .[] | select(.schema=="olm.channel") ] ) as $chs
      | $pkgs[]
      | . as $p
      | ($chs[] | select(.package==$p.name and .name==$p.defaultChannel)) as $dch
      | (($p.description // "") | gsub("[\r\n]+";" ") | .[0:200]) as $desc
      | [$p.name, $p.defaultChannel, ($dch.entries // []), $desc] | @json
    ' "${json_file}" 2>/dev/null | while IFS= read -r rowjson; do
        local pkg dch head desc
        pkg=$(echo "${rowjson}" | jq -r '.[0]')
        dch=$(echo "${rowjson}" | jq -r '.[1]')
        # entries 로부터 head 계산
        head=$(echo "${rowjson}" | jq -r ".[2] | {entries: .} | ${head_filter}" 2>/dev/null)
        [ -z "${head}" ] && head="-"
        desc=$(echo "${rowjson}" | jq -r '.[3]')
        [ -z "${desc}" ] && desc="-"
        printf "%-45s | %-22s | %-30s | %s\n" "${pkg}" "${dch}" "${head}" "${desc}"
      done | sort

    echo ""
    local pcnt ccnt
    pcnt=$(jq -rs '[.[] | select(.schema=="olm.package")] | length' "${json_file}" 2>/dev/null)
    ccnt=$(jq -rs '[.[] | select(.schema=="olm.channel")] | length' "${json_file}" 2>/dev/null)
    echo "# --- 요약: packages=${pcnt:-0}, channels=${ccnt:-0} ---"
  } > "${txt_file}"

  clear
  print_title "Operator 카탈로그 조회 결과 - ${index_name} (OCP ${ver})"
  # 표가 길 수 있으므로 앞부분만 미리보기
  head -n 40 "${txt_file}"
  echo ""
  print_info "(표가 길 경우 파일에서 전체 확인)"
  print_ok "저장 완료:"
  echo "    JSON : ${json_file}"
  echo "    TXT  : ${txt_file}"
  pause_enter
}

# --------------------------------------------------------------------------------------------------
# [기능B-1] 설치된 Operator 조회 및 선택
#   - oc get subscription -A 로 클러스터에 설치된 Operator(Subscription)를 조회한다.
#     각 Subscription: spec.name(package), spec.channel, status.currentCSV(설치된 버전)
#   - 목록을 2분할/페이지 메뉴로 표시하고, 일부/전체 선택 또는 수동 입력(콤마 복수)을 지원한다.
#   - 클러스터 미연결/미로그인 시 수동 입력으로 대체한다.
#   - 선택 결과(package 이름)는 전역 SELECTED_PKGS 에 개행 구분으로 저장한다.
#   - 설치 정보(package -> "channel|currentCSV")는 전역 연관배열 INSTALLED_INFO 에 저장한다.
# --------------------------------------------------------------------------------------------------

declare -A INSTALLED_INFO       # [package]="channel|currentCSV"
SELECTED_PKGS=""                 # 개행 구분 선택 package 목록

######################################################################################################
##  Function Name : get_cluster_version
##  Description : 클러스터의 현재 OCP 버전을 조회한다. (oc get clusterversion)
##  information : input $1=결과변수명 / output 0=성공(버전 저장), 1=실패
######################################################################################################
get_cluster_version()
{
  local __resultvar="$1"
  local v
  v=$(oc get clusterversion version -o jsonpath='{.status.desired.version}' 2>/dev/null)
  if [ -z "${v}" ]; then
    return 1
  fi
  eval "${__resultvar}=\"\${v}\""
  return 0
}

######################################################################################################
##  Function Name : load_installed_operators
##  Description : 설치된 Operator(Subscription) 목록을 조회하여 RENDER_ITEMS 와 INSTALLED_INFO 를
##                채운다.
##  information : input none / output 0=성공(목록 있음), 1=조회 실패/미로그인, 2=설치된 것 없음
######################################################################################################
load_installed_operators()
{
  RENDER_ITEMS=()
  INSTALLED_INFO=()

  check_oc_login || return 1

  local subs_json
  subs_json=$(oc get subscription -A -o json 2>/dev/null)
  if [ -z "${subs_json}" ]; then
    return 1
  fi

  # package|channel|currentCSV 형태로 추출
  local line pkg ch csv
  while IFS='|' read -r pkg ch csv; do
    [ -z "${pkg}" ] && continue
    INSTALLED_INFO["${pkg}"]="${ch}|${csv}"
    RENDER_ITEMS+=( "$(printf '%s  (ch:%s, csv:%s)' "${pkg}" "${ch:-?}" "${csv:-?}")" )
  done < <(echo "${subs_json}" | jq -r '.items[]? | "\(.spec.name)|\(.spec.channel // "")|\(.status.currentCSV // "")"' 2>/dev/null | sort)

  if [ ${#RENDER_ITEMS[@]} -eq 0 ]; then
    return 2
  fi
  return 0
}

######################################################################################################
##  Function Name : extract_pkg_from_label
##  Description : 메뉴 라벨("pkg  (ch:.., csv:..)")에서 package 이름만 추출한다.
##  information : input $1=라벨 / output package 이름 (echo)
######################################################################################################
extract_pkg_from_label()
{
  echo "$1" | sed 's/  (ch:.*$//' | sed 's/[[:space:]]*$//'
}

######################################################################################################
##  Function Name : func_select_operators
##  Description : 설치된 Operator 목록에서 선택하거나 수동 입력으로 대상 package 를 확정한다.
##                (요구사항8: 일부/전체 선택 + 목록 외 수동 입력 콤마 복수)
##  information : input none / output 0=선택완료(SELECTED_PKGS 채움), 1=취소
######################################################################################################
func_select_operators()
{
  SELECTED_PKGS=""
  local rc raw_sel

  # 오프라인 모드(클러스터 미사용)면 클러스터 조회를 건너뛰고 바로 수동 입력으로 진행한다.
  if [ "${USE_CLUSTER}" != "1" ]; then
    rc=1
  else
    load_installed_operators
    rc=$?
  fi

  if [ ${rc} -eq 0 ]; then
    # 설치 목록에서 복수 선택 (라벨 -> package 추출)
    local sel_labels
    select_multi_from_list "설치된 Operator 선택 (분석 대상)" sel_labels
    [ $? -ne 0 ] && return 1
    local lb pkg
    while IFS= read -r lb; do
      [ -z "${lb}" ] && continue
      pkg=$(extract_pkg_from_label "${lb}")
      [ -n "${pkg}" ] && SELECTED_PKGS="${SELECTED_PKGS}${pkg}"$'\n'
    done <<< "${sel_labels}"
  else
    # 오프라인/미연결 또는 설치된 것 없음 -> 수동 입력
    if [ "${USE_CLUSTER}" != "1" ]; then
      print_info "오프라인 모드: package 이름을 직접 입력하세요."
    elif [ ${rc} -eq 1 ]; then
      print_warn "클러스터 조회 불가(미로그인/미연결). 수동 입력으로 진행합니다."
    else
      print_warn "설치된 Operator가 없습니다. 수동 입력으로 진행합니다."
    fi
    ask_input "operator package 이름 (콤마로 복수, 예: a-operator,b-operator)" raw_sel ""
    [ -z "${raw_sel}" ] && return 1
    local tok
    IFS=',' read -r -a __toks <<< "${raw_sel}"
    for tok in "${__toks[@]}"; do
      tok=$(echo "${tok}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
      [ -n "${tok}" ] && SELECTED_PKGS="${SELECTED_PKGS}${tok}"$'\n'
    done
  fi

  [ -z "${SELECTED_PKGS}" ] && return 1
  return 0
}

# --------------------------------------------------------------------------------------------------
# [기능B-2] Operator 업그레이드 영향도 분석
#   - 대상 package 들과 비교할 OCP 버전들(콤마 복수)을 입력받아,
#     각 (package x OCP버전) 조합에서 다음 정보를 계산하여 표로 비교한다.
#       defaultChannel, minVersion(채널 최소), maxVersion(채널 head=최신), description
#     그리고 현재 설치 버전(currVersion) 대비 판정(Verdict)을 부여한다.
#   - 결과 파일: 최하위 버전부터 각 버전 폴더에 check-operator-version.txt 를 저장한다.
#       (ex. 4.20,4.21,4.22 -> ocp4.20/에는 4.20,4.21,4.22 컬럼 / ocp4.21/에는 4.21,4.22 컬럼 /
#            ocp4.22/에는 비교대상 없으므로 파일 미생성)
# --------------------------------------------------------------------------------------------------

# 분석용 카탈로그 index (영향도 분석 시 기본으로 사용할 index)
ANALYZE_INDEX="redhat-operator-index"

######################################################################################################
##  Function Name : ensure_catalog_json
##  Description : 특정 OCP 버전의 카탈로그 JSON 이 없으면 opm render 로 생성한다.
##  information : input $1=버전, $2=index명, $3=결과변수명(json경로) / output 0=성공,1=실패
######################################################################################################
ensure_catalog_json()
{
  local ver="$1" index_name="$2" __resultvar="$3"
  local vdir json_file image
  ensure_version_dir "${ver}" vdir || return 1
  json_file="${vdir}/${index_name}.json"

  if [ -s "${json_file}" ]; then
    # 이미 존재하면 재사용
    eval "${__resultvar}=\"\${json_file}\""
    return 0
  fi

  check_cmd_exist "opm" || return 1
  image="${REG_BASE}/${index_name}:v${ver}"
  print_info "카탈로그 조회(opm render): ${image}"
  show_exec_cmd "opm render ${image} | jq . > ${json_file}"
  local raw_tmp="${vdir}/.${index_name}.raw"
  if ! opm render "${image}" > "${raw_tmp}" 2>/dev/null || [ ! -s "${raw_tmp}" ]; then
    print_warn "opm render 실패 또는 데이터 없음: ${image}"
    rm -f "${raw_tmp}"
    return 1
  fi
  # jq 로 pretty-print 저장 (실패 시 원본 그대로)
  if jq . "${raw_tmp}" > "${json_file}" 2>/dev/null && [ -s "${json_file}" ]; then
    rm -f "${raw_tmp}"
  else
    mv -f "${raw_tmp}" "${json_file}"
  fi
  eval "${__resultvar}=\"\${json_file}\""
  return 0
}

######################################################################################################
##  Function Name : get_pkg_info_for_version
##  Description : 특정 카탈로그 JSON 에서 package 의 정보를 추출하여
##                "defaultChannel|minVer|maxVer|description|maxOCP|osVersions" 형식으로 반환한다.
##                package 가 없으면 "NONE|-|-|-|none|none" 을 반환한다.
##                - maxOCP     : olm.bundle.properties 의 olm.maxOpenShiftVersion 값 (없으면 none)
##                - osVersions : olm.bundle.properties 의 olm.openshift.versions 값 (없으면 none)
##                  두 속성은 head 번들 기준으로 취득하되, currVer(설치버전) 번들이 대상 카탈로그에
##                  존재하면 그 번들 값을 우선 사용한다. (요구사항: 값이 있으면 그 값으로 호환성 판단,
##                  없으면 none 으로 치환)
##  information : input $1=json경로, $2=package명, $3=결과변수명, $4=(선택)currVer(설치버전 csv)
##                output 0=존재, 1=없음
######################################################################################################
get_pkg_info_for_version()
{
  local json_file="$1" pkg="$2" __resultvar="$3" curr="$4"
  local head_filter result

  # jq 로 한 번에 계산:
  #  - defaultChannel: olm.package.defaultChannel
  #  - description   : olm.package.description (없으면 첫 줄 축약)
  #  - default 채널 entries 로 minVer(semver 최소), maxVer(head) 계산
  #  - head 번들 및 (있으면) curr 번들의 properties 에서
  #      olm.maxOpenShiftVersion / olm.openshift.versions 추출 (없으면 "none")
  result=$(jq -rs --arg pkg "${pkg}" --arg curr "${curr}" '
    def prop($bname; $ptype):
      ( [ .[] | select(.schema=="olm.bundle" and .name==$bname) ] | first ) as $b
      | ( ($b.properties // []) | map(select(.type==$ptype)) | first ) as $pp
      | if $pp == null then "none"
        else ( $pp.value
                | if type=="string" then .
                  elif type=="object" then (.version // .versions // (tostring))
                  else tostring end )
        end;
    . as $all
    | ( [ $all[] | select(.schema=="olm.package" and .name==$pkg) ] | first ) as $p
    | if $p == null then
        "NONE|-|-|-|none|none"
      else
        ( [ $all[] | select(.schema=="olm.channel" and .package==$pkg and .name==$p.defaultChannel) ] | first ) as $dch
        | ( ($dch.entries // []) | map(.name) ) as $names
        | ( $names | sort_by(.) | (if length>0 then first else "-" end) ) as $minv
        | ( $dch.entries // [] ) as $ents
        | ( $ents | map(.replaces) | map(select(.!=null)) ) as $rep
        | ( $ents | map(.skips // []) | add // [] ) as $skp
        | ( $rep + $skp ) as $covered
        | ( [ $ents[].name | select( . as $n | ($covered | index($n)) | not ) ] ) as $heads
        | ( if ($heads|length)>0 then ($heads | sort_by(.) | last) else ($names | sort_by(.) | (if length>0 then last else "-" end)) end ) as $maxv
        | ( ($p.description // "") | gsub("[\r\n]+";" ") | .[0:60] ) as $desc
        # curr 번들 이름 매칭: curr 가 채널 entries 에 존재하면 그 이름, 아니면 head($maxv)
        | ( if ($curr != "" and ($names | index($curr))) then $curr else $maxv end ) as $target_bundle
        | ( $all | prop($target_bundle; "olm.maxOpenShiftVersion") ) as $maxocp
        | ( $all | prop($target_bundle; "olm.openshift.versions") ) as $osvers
        | "\($p.defaultChannel)|\($minv)|\($maxv)|\($desc)|\($maxocp)|\($osvers)"
      end
  ' "${json_file}" 2>/dev/null)

  [ -z "${result}" ] && result="NONE|-|-|-|none|none"
  eval "${__resultvar}=\"\${result}\""
  case "${result}" in
    NONE\|*) return 1 ;;
    *) return 0 ;;
  esac
}

######################################################################################################
##  Function Name : ocp_in_range
##  Description : 대상 OCP 버전(major.minor)이 olm.openshift.versions 범위 문자열에 부합하는지 판정.
##                지원 형식(관용적):  "v4.14-v4.17" | "4.14-4.17" | ">=4.14" | "=4.15" | "4.15"
##  information : input $1=대상OCP(예:4.21), $2=범위문자열 / output 0=범위내/판단불가(허용), 1=범위밖
######################################################################################################
ocp_in_range()
{
  local ocp="$1" spec="$2"
  [ -z "${spec}" ] && return 0
  [ "${spec}" = "none" ] && return 0

  # 정규화: 'v' 제거, 공백 제거
  local s
  s=$(echo "${spec}" | tr -d ' ' | sed 's/v//g')

  local lo hi
  case "${s}" in
    *-*)
      # 범위: lo-hi (major.minor 기준 비교)
      lo=$(echo "${s}" | cut -d'-' -f1 | grep -oE '^[0-9]+\.[0-9]+')
      hi=$(echo "${s}" | cut -d'-' -f2 | grep -oE '^[0-9]+\.[0-9]+')
      [ -z "${lo}" ] && return 0
      # ocp < lo ?
      if [ "$(printf '%s\n%s\n' "${ocp}" "${lo}" | sort -V | head -1)" = "${ocp}" ] && [ "${ocp}" != "${lo}" ]; then
        return 1
      fi
      # hi 가 있으면 ocp > hi ?
      if [ -n "${hi}" ]; then
        if [ "$(printf '%s\n%s\n' "${ocp}" "${hi}" | sort -V | tail -1)" = "${ocp}" ] && [ "${ocp}" != "${hi}" ]; then
          return 1
        fi
      fi
      return 0
      ;;
    ">="*)
      lo=$(echo "${s}" | sed 's/>=//' | grep -oE '^[0-9]+\.[0-9]+')
      [ -z "${lo}" ] && return 0
      if [ "$(printf '%s\n%s\n' "${ocp}" "${lo}" | sort -V | head -1)" = "${ocp}" ] && [ "${ocp}" != "${lo}" ]; then
        return 1
      fi
      return 0
      ;;
    "<="*)
      hi=$(echo "${s}" | sed 's/<=//' | grep -oE '^[0-9]+\.[0-9]+')
      [ -z "${hi}" ] && return 0
      if [ "$(printf '%s\n%s\n' "${ocp}" "${hi}" | sort -V | tail -1)" = "${ocp}" ] && [ "${ocp}" != "${hi}" ]; then
        return 1
      fi
      return 0
      ;;
    "="*)
      lo=$(echo "${s}" | sed 's/=//' | grep -oE '^[0-9]+\.[0-9]+')
      [ -z "${lo}" ] && return 0
      [ "${ocp}" = "${lo}" ] && return 0 || return 1
      ;;
    *)
      # 단일 버전 표기 (예: 4.15) -> 정확히 일치할 때만 범위내로 간주하지 않고,
      # 관용적으로 "그 이상 지원 불명"이므로 판단불가로 처리하여 허용(오탐 방지).
      return 0
      ;;
  esac
}

######################################################################################################
##  Function Name : verdict_for
##  Description : 현재 설치 버전(curr) 과 대상 버전 카탈로그의 정보로 업그레이드 판정을 계산한다.
##  information : input $1=defaultChannel, $2=minVer, $3=maxVer, $4=currVer(설치버전 csv),
##                      $5=currChannel, $6=maxOCP(olm.maxOpenShiftVersion), $7=osVersions,
##                      $8=target_ocp(대상 OCP major.minor)
##                output 판정 문자열 (echo)
##                판정 우선순위:
##                  1) 미지원(대안필요)   : 대상 버전 카탈로그에 package 없음(defaultChannel=NONE)
##                  2) 업그레이드차단     : maxOCP(none 아님) 이고 target_ocp > maxOCP
##                                          (Operator 가 해당 OCP 초과 업그레이드를 차단)
##                  3) 호환범위밖         : osVersions(none 아님) 범위에 target_ocp 가 없음
##                  4) 채널변경필요       : 현재 채널이 대상 defaultChannel 과 다름
##                  5) 유지가능           : curr 가 [min,max] 범위 내
##                  6) 업그레이드필요     : curr < min
##                  7) 확인필요           : 정보 부족
##                ※ maxOCP/osVersions 가 "none"(속성 없음)이면 해당 규칙은 건너뛰고 채널/semver 로 판정.
######################################################################################################
verdict_for()
{
  local dch="$1" minv="$2" maxv="$3" curr="$4" cch="$5"
  local maxocp="$6" osvers="$7" target_ocp="$8"

  if [ "${dch}" = "NONE" ]; then
    echo "미지원(대안필요)"
    return
  fi

  # --- 우선 규칙: OCP 호환성 속성 기반 판정 (값이 있는 경우에만) ---------------------------------
  # 2) olm.maxOpenShiftVersion : 이 값을 초과하는 OCP 로는 업그레이드가 차단됨
  if [ -n "${maxocp}" ] && [ "${maxocp}" != "none" ] && [ -n "${target_ocp}" ]; then
    local maxocp_mm
    maxocp_mm=$(echo "${maxocp}" | sed 's/v//g' | grep -oE '^[0-9]+\.[0-9]+')
    if [ -n "${maxocp_mm}" ]; then
      if [ "$(printf '%s\n%s\n' "${target_ocp}" "${maxocp_mm}" | sort -V | tail -1)" = "${target_ocp}" ] && [ "${target_ocp}" != "${maxocp_mm}" ]; then
        echo "업그레이드차단(maxOCP:${maxocp_mm})"
        return
      fi
    fi
  fi

  # 3) olm.openshift.versions : 지원 OCP 범위 밖이면 호환범위밖
  if [ -n "${osvers}" ] && [ "${osvers}" != "none" ] && [ -n "${target_ocp}" ]; then
    if ! ocp_in_range "${target_ocp}" "${osvers}"; then
      echo "호환범위밖(support:${osvers})"
      return
    fi
  fi

  if [ -z "${curr}" ] || [ "${curr}" = "-" ]; then
    echo "확인필요(현재버전미상)"
    return
  fi

  # 현재 채널과 대상 defaultChannel 비교 (채널명이 있으면)
  if [ -n "${cch}" ] && [ "${cch}" != "-" ] && [ "${cch}" != "${dch}" ]; then
    echo "채널변경필요(${cch}->${dch})"
    return
  fi

  # semver 비교: curr 가 min..max 범위인지 (sort -V 활용)
  # curr 를 포함해 정렬했을 때 위치로 판단
  local lowest highest
  lowest=$(printf '%s\n%s\n' "${minv}" "${curr}" | sed 's/^[^0-9]*//' | sort -V | head -1)
  highest=$(printf '%s\n%s\n' "${maxv}" "${curr}" | sed 's/^[^0-9]*//' | sort -V | tail -1)

  # curr 의 순수 semver 추출 (csv 이름에 vX.Y.Z 형태 포함 가능)
  local curr_sem min_sem max_sem
  curr_sem=$(echo "${curr}" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  min_sem=$(echo "${minv}"  | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
  max_sem=$(echo "${maxv}"  | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)

  if [ -z "${curr_sem}" ] || [ -z "${min_sem}" ] || [ -z "${max_sem}" ]; then
    echo "확인필요(버전파싱)"
    return
  fi

  # curr < min ?
  if [ "$(printf '%s\n%s\n' "${curr_sem}" "${min_sem}" | sort -V | head -1)" = "${curr_sem}" ] && [ "${curr_sem}" != "${min_sem}" ]; then
    echo "업그레이드필요(min:${min_sem})"
    return
  fi
  # curr > max ?
  if [ "$(printf '%s\n%s\n' "${curr_sem}" "${max_sem}" | sort -V | tail -1)" = "${curr_sem}" ] && [ "${curr_sem}" != "${max_sem}" ]; then
    echo "확인필요(curr>max)"
    return
  fi
  echo "유지가능"
}

######################################################################################################
##  Function Name : func_analyze_upgrade
##  Description : 업그레이드 영향도 분석 메인. 대상 package 와 비교 OCP 버전들을 받아 표를 생성하고
##                최하위 버전부터 각 버전 폴더에 check-operator-version.txt 를 저장한다.
##  information : input none(대화형, 앞서 func_select_operators 로 SELECTED_PKGS 확정) / output 파일/화면
######################################################################################################
func_analyze_upgrade()
{
  check_cmd_exist "jq" || { pause_enter; return 1; }

  # 0) 클러스터 사용 여부 확인 + oc 로그인 사전 점검 (요구사항9)
  #    클러스터를 사용하면 설치 Operator/현재 버전을 자동 조회하므로 로그인을 먼저 점검한다.
  #    미로그인 시 로그인을 가이드하고, 로그인 후 재확인하거나 오프라인(수동)으로 전환한다.
  USE_CLUSTER=0
  print_title "Operator 업그레이드 영향도 분석"
  echo "  클러스터에 연결하면 설치된 Operator와 현재 버전을 자동으로 조회합니다."
  echo "  연결하지 않으면(오프라인) package/버전을 수동으로 입력합니다."
  echo ""
  printf "  ${C_BOLD}클러스터에 연결하여 진행할까요? [Y] 예(로그인 점검)  [n] 아니오(수동): ${C_RESET}"
  local use_ans
  read -r use_ans || use_ans="Y"
  case "${use_ans}" in
    n|N)
      USE_CLUSTER=0
      print_info "오프라인 모드로 진행합니다. (package/버전 수동 입력)"
      ;;
    *)
      # oc 로그인 사전 점검 + 가이드
      if check_oc_login; then
        USE_CLUSTER=1
        print_ok "클러스터 연결 확인. 설치된 Operator/현재 버전을 자동 조회합니다."
      else
        USE_CLUSTER=0
        print_warn "로그인되지 않아 오프라인 모드로 진행합니다. (package/버전 수동 입력)"
      fi
      ;;
  esac
  pause_enter

  # 1) 대상 package 선택/입력
  func_select_operators || { print_info "분석을 취소했습니다."; pause_enter; return 1; }

  # 2) 분석 index 확인/변경
  local idx_in
  ask_input "분석에 사용할 카탈로그 index" idx_in "${ANALYZE_INDEX}"
  [ -n "${idx_in}" ] && ANALYZE_INDEX="${idx_in}"

  # 3) 현재 클러스터 버전 안내 + 비교할 OCP 버전들 입력 (콤마 복수)
  #    클러스터 사용 모드일 때만 현재 버전을 조회한다. (요구사항9: 미로그인 원시 에러 방지)
  local cur_cluster=""
  if [ "${USE_CLUSTER}" = "1" ]; then
    if get_cluster_version cur_cluster; then
      print_info "현재 클러스터 버전: ${cur_cluster}"
    else
      print_warn "클러스터 버전 조회 불가. 비교 버전을 직접 입력하세요."
    fi
  else
    print_info "오프라인 모드: 비교할 OCP 버전을 직접 입력하세요."
  fi

  local raw_vers
  ask_input "비교할 OCP 버전들 (콤마 복수, 예: 4.20,4.21,4.22)" raw_vers "${cur_cluster%.*}"
  [ -z "${raw_vers}" ] && { print_error "비교 버전이 없습니다."; pause_enter; return 1; }

  # 버전 정규화 + 정렬(오름차순) + 중복 제거
  local vlist="" tok nv
  IFS=',' read -r -a __vtoks <<< "${raw_vers}"
  for tok in "${__vtoks[@]}"; do
    normalize_version "${tok}" nv
    [ -n "${nv}" ] && vlist="${vlist}${nv}"$'\n'
  done
  # 정렬/중복제거 후 배열화
  local -a VERS
  while IFS= read -r nv; do
    [ -n "${nv}" ] && VERS+=( "${nv}" )
  done < <(echo "${vlist}" | grep -v '^$' | sort -V -u)

  if [ ${#VERS[@]} -eq 0 ]; then
    print_error "유효한 비교 버전이 없습니다."
    pause_enter; return 1
  fi

  # 4) 대상 package 배열화
  local -a PKGS
  while IFS= read -r tok; do
    [ -n "${tok}" ] && PKGS+=( "${tok}" )
  done < <(echo "${SELECTED_PKGS}" | grep -v '^$')

  print_info "대상 package: ${#PKGS[@]}개 / 비교 버전: ${VERS[*]}"
  echo ""

  # 5) 각 비교 버전의 카탈로그 JSON 확보 (버전->json경로 매핑)
  declare -A VER_JSON
  local v jf
  for v in "${VERS[@]}"; do
    if ensure_catalog_json "${v}" "${ANALYZE_INDEX}" jf; then
      VER_JSON["${v}"]="${jf}"
    else
      VER_JSON["${v}"]=""
      print_warn "OCP ${v} 카탈로그 확보 실패 - 해당 컬럼은 N/A 로 표기됩니다."
    fi
  done

  # 6) 최하위 버전부터 각 버전을 기준으로 상위 버전 컬럼 표 생성/저장
  #    base_idx 를 0..(n-2) 로 돌며, 컬럼 = VERS[base_idx..n-1]
  local n=${#VERS[@]}
  local base_idx
  local generated=0
  for (( base_idx=0; base_idx<n-1; base_idx++ )); do
    local base_ver="${VERS[${base_idx}]}"
    local vdir
    ensure_version_dir "${base_ver}" vdir || continue
    local out_file="${vdir}/check-operator-version.txt"

    # 헤더 (요구사항8: 첫줄에 날짜/시간/os user)
    {
      echo "# Operator Upgrade Impact Analysis"
      echo "# generated_at : $(date '+%Y-%m-%d %H:%M:%S')   os_user: $(whoami)"
      echo "# base_version : ${base_ver}   (기준 버전 폴더)"
      echo "# compare_cols : $(printf '%s ' "${VERS[@]:${base_idx}}")"
      echo "# catalog_index: ${ANALYZE_INDEX}"
      [ -n "${cur_cluster}" ] && echo "# cluster_now  : ${cur_cluster}"
      echo "#"
      echo "# =============================================================================="
      echo "# [Information] 기초 데이터 조회 방법"
      echo "#   - 카탈로그 조회 : opm render ${REG_BASE}/${ANALYZE_INDEX}:v<버전> | jq . > <버전>/${ANALYZE_INDEX}.json"
      echo "#                     (비교하는 각 OCP 버전마다 위 명령으로 카탈로그 확보/재사용)"
      if [ "${USE_CLUSTER}" = "1" ]; then
        echo "#   - 설치 Operator : oc get subscription -A -o json"
        echo "#                     (package=.spec.name, 현재채널=.spec.channel, 설치버전=.status.currentCSV)"
        echo "#   - 클러스터 버전 : oc get clusterversion version -o jsonpath='{.status.desired.version}'"
      else
        echo "#   - 대상 package  : 오프라인 모드(수동 입력). 현재 채널/버전(CURRENT)은 미제공(-/-)"
      fi
      echo "#"
      echo "# [Information] 컬럼/값 산출 기준"
      echo "#   - defaultChannel : 각 버전 카탈로그의 olm.package.defaultChannel"
      echo "#   - min            : defaultChannel entries 중 semver 최소 버전"
      echo "#   - max(head)      : defaultChannel entries 중 다른 entry 의 replaces/skips 대상이"
      echo "#                      아닌 최신(semver 최대) 번들 = 채널 head(설치 기본 버전)"
      echo "#   - CURRENT        : 클러스터에 설치된 현재 채널/버전(csv)"
      echo "#"
      echo "# [Information] OCP 호환성 속성 (opm render 의 olm.bundle.properties 에서 추출)"
      echo "#   - maxOCP     : olm.maxOpenShiftVersion  (이 값 초과 OCP 로는 업그레이드 차단)"
      echo "#   - support    : olm.openshift.versions   (지원 OCP 버전 범위)"
      echo "#   ※ 속성이 없으면 'none' 으로 표기하며, 이 경우 채널/semver 기준으로 판정한다."
      echo "#   ※ 두 속성은 head 번들 기준이며, 설치버전(csv) 번들이 대상 카탈로그에 있으면 그 값을 우선한다."
      echo "#"
      echo "# [Information] 판정(Verdict) 로직 기준 (위에서부터 우선 적용)"
      echo "#   - 미지원(대안필요)     : 대상 버전 카탈로그에 package 없음(defaultChannel=NONE)"
      echo "#   - 업그레이드차단       : maxOCP(!=none) 이고 대상 OCP > maxOCP  (Operator 가 상위 OCP 차단)"
      echo "#   - 호환범위밖           : support(!=none) 범위에 대상 OCP 가 없음"
      echo "#   - 확인필요(현재버전미상): CURRENT(설치버전) 정보 없음(오프라인/미설치)"
      echo "#   - 채널변경필요         : 현재 채널 != 대상 버전 defaultChannel  (표기: 현재->대상)"
      echo "#   - 업그레이드필요       : 현재 설치버전(semver) < 대상 채널 min"
      echo "#   - 확인필요(curr>max)   : 현재 설치버전 > 대상 채널 head(max)"
      echo "#   - 유지가능             : 현재 설치버전이 대상 채널 [min, max] 범위 내"
      echo "#   ※ semver 비교는 X.Y.Z 를 추출하여 'sort -V' 기준으로 판별함(사전 참고용)."
      echo "# =============================================================================="
      echo "#"
      echo "# 판정(Verdict): 유지가능/업그레이드필요/채널변경필요/미지원(대안필요)/업그레이드차단/호환범위밖/확인필요"
      echo "#"
      echo "# 표 구성: 상단 헤더=OCP release 버전, 하단 서브헤더=CHANNEL/MINVER/MAXVER/VERDICT"
      echo "#          각 Operator 행은 해당 OCP 버전 블록의 서브 항목에 값만 표시합니다."
      echo "#"

      # ---- 2단 헤더 구성 -----------------------------------------------------------------------
      # 컬럼 폭 정의 (서브 항목)
      #   CHANNEL=20, MINVER=16, MAXVER=16, VERDICT=24  (한 OCP 버전 블록)
      #   PACKAGE=38, DESCRIPTION=40, CURRENT=26
      local w_ch=20 w_min=16 w_max=16 w_vd=24
      local w_pkg=38 w_desc=40 w_curr=26
      # 한 OCP 버전 블록의 전체 폭 = 4개 서브컬럼 + 3개 구분 공백
      local blk_w=$(( w_ch + w_min + w_max + w_vd + 3 ))
      local cj

      # (1단) 상위 헤더: OCP 버전을 블록 폭에 맞춰 표기
      printf "%-${w_pkg}s | %-${w_desc}s" "" ""
      for (( cj=base_idx; cj<n; cj++ )); do
        printf " | %-${blk_w}s" "OCP ${VERS[${cj}]}"
      done
      printf " | %-${w_curr}s\n" ""

      # (2단) 하위 서브 헤더
      printf "%-${w_pkg}s | %-${w_desc}s" "PACKAGE" "DESCRIPTION"
      for (( cj=base_idx; cj<n; cj++ )); do
        printf " | %-${w_ch}s %-${w_min}s %-${w_max}s %-${w_vd}s" "CHANNEL" "MINVERSION" "MAXVERSION" "VERDICT"
      done
      printf " | %-${w_curr}s\n" "CURRENT(ch/csv)"

      # 구분선
      _repeat_char() { local n="$1" c="${2:--}"; printf "%${n}s" "" | tr ' ' "${c}"; }
      _repeat_char ${w_pkg}; printf -- "-+-"; _repeat_char ${w_desc}
      for (( cj=base_idx; cj<n; cj++ )); do
        printf -- "-+-"; _repeat_char ${blk_w}
      done
      printf -- "-+-"; _repeat_char ${w_curr}; printf "\n"

      # ---- 각 package 행 -----------------------------------------------------------------------
      local pkg info dch minv maxv desc curr cch verdict
      for pkg in "${PKGS[@]}"; do
        # 현재 설치 정보 (INSTALLED_INFO: channel|csv)
        curr=""; cch=""
        if [ -n "${INSTALLED_INFO[${pkg}]:-}" ]; then
          cch=$(echo "${INSTALLED_INFO[${pkg}]}" | cut -d'|' -f1)
          curr=$(echo "${INSTALLED_INFO[${pkg}]}" | cut -d'|' -f2)
        fi

        # description 은 첫 유효 버전에서 취득
        desc="-"
        local first_desc_done=0
        # 각 OCP 버전 블록의 서브컬럼 문자열(개행 구분 4항목)을 배열에 저장
        local -a blocks=()
        for (( cj=base_idx; cj<n; cj++ )); do
          local cv="${VERS[${cj}]}"
          local jffile="${VER_JSON[${cv}]}"
          if [ -z "${jffile}" ]; then
            # 카탈로그 없음: 서브컬럼 전부 N/A 표기
            blocks+=( "$(printf '%s\t%s\t%s\t%s' "-" "-" "-" "N/A(카탈로그없음)")" )
            continue
          fi
          # curr(설치버전 csv)를 전달하여 해당 번들 우선으로 maxOCP/support 추출
          get_pkg_info_for_version "${jffile}" "${pkg}" info "${curr}"
          dch=$(echo "${info}"  | cut -d'|' -f1)
          minv=$(echo "${info}" | cut -d'|' -f2)
          maxv=$(echo "${info}" | cut -d'|' -f3)
          local d4 maxocp osvers
          d4=$(echo "${info}"     | cut -d'|' -f4)
          maxocp=$(echo "${info}" | cut -d'|' -f5)
          osvers=$(echo "${info}" | cut -d'|' -f6)
          if [ ${first_desc_done} -eq 0 ] && [ -n "${d4}" ] && [ "${d4}" != "-" ]; then
            desc="${d4}"; first_desc_done=1
          fi
          # 대상 OCP 버전(cv)을 전달하여 maxOCP/support 기반 판정 포함
          verdict=$(verdict_for "${dch}" "${minv}" "${maxv}" "${curr}" "${cch}" "${maxocp}" "${osvers}" "${cv}")
          if [ "${dch}" = "NONE" ]; then
            blocks+=( "$(printf '%s\t%s\t%s\t%s' "-" "-" "-" "미지원(대안필요)")" )
          else
            blocks+=( "$(printf '%s\t%s\t%s\t%s' "${dch}" "${minv}" "${maxv}" "${verdict}")" )
          fi
        done

        # 행 출력: PACKAGE | DESCRIPTION | (각 OCP 블록의 4 서브컬럼) | CURRENT
        printf "%-${w_pkg}s | %-${w_desc}s" "${pkg:0:${w_pkg}}" "${desc:0:${w_desc}}"
        local b bc bmin bmax bvd
        for b in "${blocks[@]}"; do
          bc=$(echo "${b}"  | cut -f1)
          bmin=$(echo "${b}" | cut -f2)
          bmax=$(echo "${b}" | cut -f3)
          bvd=$(echo "${b}"  | cut -f4)
          printf " | %-${w_ch}s %-${w_min}s %-${w_max}s %-${w_vd}s" "${bc}" "${bmin}" "${bmax}" "${bvd}"
        done
        printf " | %-${w_curr}s\n" "${cch:--}/${curr:--}"
      done

      echo ""
      echo "# ※ CHANNEL/MINVERSION/MAXVERSION: 대상 OCP 버전 카탈로그의 defaultChannel 과 그 채널의"
      echo "#    최소버전 ~ head(최신버전). VERDICT: 현재 설치버전 기준 판정."
      echo "# ※ CURRENT: 클러스터에 설치된 현재 채널/버전(csv). 미설치(수동입력)면 -/- 표기."
    } > "${out_file}"

    print_ok "저장: ${out_file}"
    generated=$(( generated + 1 ))
  done

  # 최상위 버전은 비교 대상이 없으므로 파일 미생성 (요구사항8)
  local top="${VERS[$(( n - 1 ))]}"
  print_info "최상위 버전 OCP ${top} 폴더는 비교 대상이 없어 파일을 생성하지 않습니다."

  # 화면 미리보기: 최하위 기준 파일 출력
  echo ""
  local preview="${WORKDIR}/ocp${VERS[0]}/check-operator-version.txt"
  if [ -f "${preview}" ]; then
    clear
    print_title "업그레이드 영향도 분석 결과 (기준: OCP ${VERS[0]})"
    cat "${preview}"
  fi
  echo ""
  print_ok "총 ${generated}개 기준 버전 파일 생성 완료. (경로: ${WORKDIR}/ocp<버전>/check-operator-version.txt)"
  pause_enter
}

# --------------------------------------------------------------------------------------------------
# 메인 메뉴 / 진입점
# --------------------------------------------------------------------------------------------------

######################################################################################################
##  Function Name : func_show_config
##  Description : 현재 설정(저장 경로, 레지스트리, 분석 index)을 표시하고 변경할 수 있게 한다.
##  information : input none / output none
######################################################################################################
func_show_config()
{
  print_title "설정 (Configuration)"
  echo "  현재 설정값:"
  echo "    WORKDIR       : ${WORKDIR}"
  echo "    REG_BASE      : ${REG_BASE}"
  echo "    ANALYZE_INDEX : ${ANALYZE_INDEX}"
  echo ""
  echo "  [1] WORKDIR 변경   [2] REG_BASE 변경   [3] ANALYZE_INDEX 변경   [b] 뒤로"
  echo ""
  printf "  ${C_BOLD}선택: ${C_RESET}"
  local ch
  read -r ch || return 0
  case "${ch}" in
    1) ask_input "새 WORKDIR" WORKDIR "${WORKDIR}" ;;
    2) ask_input "새 REG_BASE" REG_BASE "${REG_BASE}" ;;
    3) ask_input "새 ANALYZE_INDEX" ANALYZE_INDEX "${ANALYZE_INDEX}" ;;
    *) return 0 ;;
  esac
  print_ok "설정이 변경되었습니다."
  pause_enter
}

######################################################################################################
##  Function Name : do_exit
##  Description : 프로그램을 정상 종료한다.
##  information : input none / output none (exit)
######################################################################################################
do_exit()
{
  clear
  echo "ocp_list 를 종료합니다. 수고하셨습니다."
  echo "결과 저장 경로: ${WORKDIR}"
  exit 0
}

######################################################################################################
##  Function Name : main_menu
##  Description : 최상위 메뉴. 기능(카탈로그 조회 / 영향도 분석 / 설정)을 선택한다.
##  information : input none / output 없음 (메인 루프)
######################################################################################################
main_menu()
{
  local input
  while true; do
    clear
    print_line "="
    printf "${C_BOLD}  ocp_list - OCP Release/Operator 카탈로그 & 업그레이드 영향도 분석${C_RESET}\n"
    print_line "="
    echo ""
    echo "  [저장경로] ${WORKDIR}"
    echo ""
    printf "${C_BOLD}  [ 카탈로그 조회 ]${C_RESET}\n"
    echo "    1) OCP Release 목록 조회        (release.json / release.txt)"
    echo "    2) Operator 카탈로그(index) 조회 (<index>.json / <index>.txt)"
    echo ""
    printf "${C_BOLD}  [ 업그레이드 영향도 분석 ]${C_RESET}\n"
    echo "    3) Operator 업그레이드 영향도 분석 (check-operator-version.txt)"
    echo ""
    printf "${C_BOLD}  [ 기타 ]${C_RESET}\n"
    echo "    4) 설정 보기/변경"
    echo "    q) 종료"
    echo ""
    print_line "-"
    printf "  ${C_BOLD}메뉴 선택: ${C_RESET}"
    if ! read -r input; then do_exit; fi

    case "${input}" in
      1) func_release_catalog ;;
      2) func_operator_catalog ;;
      3) func_analyze_upgrade ;;
      4) func_show_config ;;
      q|Q) do_exit ;;
      *) ;;
    esac
  done
}
# ======<<<< Function Registration Area (End) >>>>=================================================

# ======<<<< Main Logic Coding Area (Start) >>>>===================================================
# 1) 저장 루트 디렉토리 준비
mkdir -p "${WORKDIR}" 2>/dev/null

# 2) 시작 배너 + 의존성 점검
print_title "ocp_list - OCP Release/Operator 카탈로그 & 업그레이드 영향도 분석"
echo "  이 도구는 OCP 버전별 release/Operator 카탈로그를 조회(opm 공식)하고,"
echo "  설치된 Operator의 여러 OCP 버전 기준 업그레이드 영향도를 표로 분석합니다."
echo ""
echo "  - 결과는 ${WORKDIR}/ocp<버전>/ 아래에 JSON/TXT 로 저장됩니다."
echo "  - 영향도 분석 결과: check-operator-version.txt (최하위 버전부터 상위 버전 컬럼)"
echo ""
check_dependencies
pause_enter

# 3) 메인 메뉴 진입
main_menu
# ======<<<< Main Logic Coding Area (End) >>>>=====================================================
