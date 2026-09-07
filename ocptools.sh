#!/bin/bash
####################################################################################################
##
## File name   : ocptools.sh
## Description : OCP / Podman / Network 운영 명령어 학습형 통합 CLI 도구.
##               메뉴에서 명령어 유형과 세부 명령어를 선택하거나 인자를 입력하면,
##               실제 실행되는 명령어 문자열(실행문)을 함께 출력한 뒤 실행/결과를 보여준다.
##               사용자가 명령어와 파라미터를 자연스럽게 익히도록 돕는 것을 목표로 한다.
## Information : - 명령어 유형(Category) -> 세부 명령어(Command) 2단계 메뉴 구조.
##               - 명령어 메타데이터는 연관배열(CMD_*)로 관리 (array depth 2, 확장 용이).
##               - 리소스 인자(node/pod 등)는 직접 입력 또는 oc 조회 결과 메뉴 선택 지원.
##               - oc login 여부를 먼저 확인하여 미로그인 에러를 사전 차단.
##               - 성능용 메타파일은 $PWD/.ocptools 에 저장하고 종료 시 삭제(흔적 제거).
##               - signal 처리 로그는 $HOME/tmp 아래에 저장.
##
##==================================================================================================
##  version   date             author          reason
##--------------------------------------------------------------------------------------------------
##  1.0       2026.08.16       k.s.k & kiro     First Created
##  1.1       2026.08.16       k.s.k & kiro     registry catalog 전체목록 조회 추가,
##                                              tcpdump 명령 추가,
##                                              curl --resolve 멀티IP/커스텀포트 보완 및
##                                              --connect-to(host:port:host:port) 메뉴 추가
##  1.2       2026.09.07       k.s.k & kiro     (1) private registry 주소 입력 시 기본 참고정보
##                                                  (DEFAULT_REGISTRY=ocprgst.bss.skt:5000)를 제시하고,
##                                                  엔터만 누르면 기본값으로 처리하도록 개선
##                                                  (podman login/catalog/tags/delete_tag 프롬프트).
##                                              (2) 화면 출력을 C_BOLD 로 통일(색상 정의는 유지, 가독성 문제 회피)
##  1.3       2026.09.07       k.s.k & kiro     기능 추가: 인증서 유효일자 조회(ocp_cert),
##                                              Pod 이미지 정보 조회, OCP 관리작업(oc adm/patch: ocp_adm),
##                                              노드 tcpdump/ss, 테스트 이미지(busybox/toolbox/nginx: test_img)
##  1.4       2026.09.07       k.s.k & kiro     기능 추가: istioctl(istio), 유틸리티(util) -
##                                              복수 crt merge->ConfigMap 생성/patch, 복수 JSON merge(jq),
##                                              openssl 사용법
##
####################################################################################################

# ======<<<< Signal common processing logic (Start) >>>>=============================================
# 로그 디렉토리($HOME/tmp)를 준비하고 signal 발생 시 로그를 남긴 뒤 정리 후 종료한다.
logdatefmt="%Y%m%d-%H:%M:%S"                 # 로깅용 날짜/시간 포맷
logdir="${HOME}/tmp"                          # signal 로그 저장 폴더
[ -d "${logdir}" ] || mkdir -p "${logdir}" 2>/dev/null
logfnm="${logdir}/$(basename "$0").log"       # signal 로그 파일 전체 경로

trap ' echo "$(date +${logdatefmt}) $0 signal(SIGINT ) captured" | tee -a "${logfnm}"; cleanup_meta; exit 1;' SIGINT
trap ' echo "$(date +${logdatefmt}) $0 signal(SIGQUIT) captured" | tee -a "${logfnm}"; cleanup_meta; exit 1;' SIGQUIT
trap ' echo "$(date +${logdatefmt}) $0 signal(SIGTERM) captured" | tee -a "${logfnm}"; cleanup_meta; exit 1;' SIGTERM
# 정상 종료(EXIT) 시에도 메타 폴더 정리
trap ' cleanup_meta;' EXIT
# ======<<<< Signal common processing logic (End) >>>>===============================================

# ======<<<< Important Global Variable Registration Area (Start) >>>>================================
# 색상 코드 (비정상/강조 표시에 사용)
C_RED='\033[0;91m'      ; C_GREEN='\033[0;92m' ; C_YELLOW='\033[0;93m'
C_BLUE='\033[0;94m'     ; C_CYAN='\033[0;96m'  ; C_WHITE='\033[0;97m'
C_BOLD='\033[1m'        ; C_RESET='\033[0m'

# 성능용 메타파일 저장 폴더 (프로그램 종료 시 삭제)
META_DIR="${PWD}/.ocptools"

# private registry 기본 참고정보 (레지스트리 주소 입력 시 기본값으로 제시)
# 입력 프롬프트에서 이 값을 참고정보로 보여주고, 엔터만 누르면 이 값을 사용한다.
DEFAULT_REGISTRY="ocprgst.bss.skt:5000"

# 메뉴 화면 레이아웃 설정
ITEMS_PER_COL=10        # 한 열에 표시할 최대 항목 수
MENU_COLS=2             # 화면 열 개수 (이분할)
ITEMS_PER_PAGE=$(( ITEMS_PER_COL * MENU_COLS ))   # 페이지당 항목 수

# oc 로그인 확인 캐시 플래그 (0=미확인, 1=확인완료)
OC_LOGIN_CHECKED=0

# ---- 명령어 유형(Category) 정의 ----------------------------------------------------------------
# CAT_IDS      : 유형 ID 목록 (표시 순서)
# CAT_LABEL    : 유형 ID -> 화면 표시명 (연관배열, depth 1)
# 세부 명령어는 각 유형별 CMDLIST_<catid> 배열로 관리한다.
CAT_IDS=( "ocp_get" "ocp_cert" "ocp_adm" "ocp_node" "ocp_file" "ocp_exec" "test_img" "istio" "util" "podman_reg" "net_diag" "sys_net" )

declare -A CAT_LABEL
CAT_LABEL=(
  [ocp_get]="OCP 리소스 조회 (oc get)"
  [ocp_cert]="OCP 인증서 조회 (만료일/상세)"
  [ocp_adm]="OCP 관리 작업 (oc adm/patch)"
  [ocp_node]="OCP 노드 접속 실행 (oc debug node)"
  [ocp_file]="OCP 파일 송수신 (oc cp / rsync)"
  [ocp_exec]="OCP Pod 실행/진입 (oc exec/rsh/logs)"
  [test_img]="테스트 이미지 (busybox/toolbox/nginx)"
  [istio]="Istio 서비스메시 (istioctl)"
  [util]="유틸리티 (crt merge/json merge/openssl)"
  [podman_reg]="Podman 레지스트리 (catalog/tags/tag/rmi)"
  [net_diag]="네트워크 진단 (curl/ncat/ping/ss)"
  [sys_net]="시스템/네트워크 (chrony/NIC)"
)

# ---- 명령어 메타데이터 (CMD_META : depth 2 연관배열) --------------------------------------------
# 키 형식: "<cmd_id>|<field>"
#   label    : 세부 명령어 화면 표시명
#   desc     : 설명 (학습용)
#   handler  : 실행 처리 함수명 (함수 포인터 역할, eval 호출)
#   confirm  : Y 이면 실행 전 y/N 확인 (되돌리기 어려운 명령 안전장치)
# 실제 실행문 조립과 인자 입력은 각 handler 함수에서 수행한다.
declare -A CMD_META
# 세부 명령어 ID 목록 (유형별)
declare -A CMDLIST      # [catid]="cmd_id1 cmd_id2 ..." (공백 구분 문자열, depth 1 유지)
# ======<<<< Important Global Variable Registration Area (End) >>>>==================================

# ======<<<< Function Registration Area (Start) >>>>================================================

######################################################################################################
##  Function Name : cleanup_meta
##  Description : 프로그램 종료 시 성능용 메타 폴더($PWD/.ocptools)를 삭제하여 흔적을 남기지 않는다.
##  information : input none / output none
######################################################################################################
cleanup_meta()
{
  if [ -n "${META_DIR}" ] && [ -d "${META_DIR}" ]; then
    rm -rf "${META_DIR}" 2>/dev/null
  fi
}

######################################################################################################
##  Function Name : init_meta
##  Description : 성능용 메타 폴더를 생성한다. (없을 때만)
##  information : input none / output none
######################################################################################################
init_meta()
{
  [ -d "${META_DIR}" ] || mkdir -p "${META_DIR}" 2>/dev/null
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
##  Function Name : get_term_width
##  Description : 현재 터미널 열 너비를 반환한다. (조회 불가 시 80)
##  information : input none / output 터미널 너비(숫자)
######################################################################################################
get_term_width()
{
  local w
  w=$(tput cols 2>/dev/null)
  if [ -z "${w}" ] || [ "${w}" -lt 40 ]; then
    w=80
  fi
  echo "${w}"
}

######################################################################################################
##  Function Name : pause_enter
##  Description : 사용자가 결과를 확인할 수 있도록 Enter 입력을 대기한다.
##  information : input none / output none
######################################################################################################
pause_enter()
{
  echo ""
  printf "  ${C_BOLD}[Enter] 계속...${C_RESET}"
  read -r _dummy || return 0
}

######################################################################################################
##  Function Name : print_title
##  Description : 화면 상단 타이틀 배너를 출력한다.
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
##  Function Name : show_exec_cmd
##  Description : 실제 실행되는 명령어 문자열(실행문)을 학습용으로 화면에 강조 출력한다.
##  information : input $1=명령어 문자열 / output "[실행문: ...]" 형태로 출력
##                요구사항3: 사용자가 실제 명령어를 눈으로 익힐 수 있도록 항상 표시한다.
######################################################################################################
show_exec_cmd()
{
  local cmd="$1"
  echo ""
  printf "${C_BOLD}[실행문: %s]${C_RESET}\n" "${cmd}"
  print_line "-"
}

######################################################################################################
##  Function Name : confirm_run
##  Description : 되돌리기 어려운 명령(삭제, NIC down 등) 실행 전 y/N 확인을 받는다.
##  information : input $1=확인 메시지 / output 0=진행, 1=취소
######################################################################################################
confirm_run()
{
  local msg="${1:-이 명령을 실행하시겠습니까?}"
  local ans
  printf "${C_BOLD}  %s (y/N): ${C_RESET}" "${msg}"
  read -r ans
  case "${ans}" in
    y|Y|yes|YES) return 0 ;;
    *) echo "  취소되었습니다."; return 1 ;;
  esac
}

######################################################################################################
##  Function Name : run_cmd
##  Description : 실행문을 표시한 뒤 명령어를 실제 실행한다.
##  information : input $1=명령어 문자열, $2=(선택)confirm(Y면 실행전 확인) / output 명령 실행 결과
######################################################################################################
run_cmd()
{
  local cmd="$1"
  local need_confirm="${2:-N}"

  show_exec_cmd "${cmd}"

  if [ "${need_confirm}" = "Y" ]; then
    confirm_run "위 실행문을 실행합니다. 계속할까요?" || return 1
  fi

  echo ""
  # eval 로 파이프/옵션 포함 명령을 그대로 실행 (학습형 도구 특성상 실행문 그대로 수행)
  eval "${cmd}"
  local rc=$?
  echo ""
  if [ ${rc} -ne 0 ]; then
    printf "${C_BOLD}  (종료코드: %s) 명령 실행 중 오류가 발생했거나 결과가 없습니다.${C_RESET}\n" "${rc}"
  fi
  return ${rc}
}

######################################################################################################
##  Function Name : ask_input
##  Description : 사용자로부터 인자 값을 입력받는다. (기본값 지원)
##  information : input $1=프롬프트 메시지, $2=결과변수명, $3=(선택)기본값
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
  read -r input
  [ -z "${input}" ] && input="${defval}"
  eval "${__resultvar}=\"\${input}\""
}

######################################################################################################
##  Function Name : check_cmd_exist
##  Description : 필요한 실행 파일(oc, podman 등)이 설치되어 있는지 확인한다.
##  information : input $1=명령어명 / output 0=존재, 1=없음(메시지 출력)
######################################################################################################
check_cmd_exist()
{
  local c="$1"
  if ! command -v "${c}" >/dev/null 2>&1; then
    printf "${C_BOLD}  [%s] 명령을 찾을 수 없습니다. 설치 또는 PATH를 확인하세요.${C_RESET}\n" "${c}"
    return 1
  fi
  return 0
}

######################################################################################################
##  Function Name : check_oc_login
##  Description : oc 로그인 여부를 확인하고, 미로그인 시 로그인 방법을 안내한다.
##                요구사항5: 미로그인 상태에서 발생하는 원시 에러 메시지 노출을 방지한다.
##  information : input none / output 0=로그인됨, 1=미로그인(안내 출력)
######################################################################################################
check_oc_login()
{
  check_cmd_exist "oc" || return 1

  # 세션당 1회만 실제 확인 (성능 고려), 이후 캐시 플래그 사용
  if [ "${OC_LOGIN_CHECKED}" = "1" ]; then
    return 0
  fi

  if oc whoami >/dev/null 2>&1; then
    OC_LOGIN_CHECKED=1
    return 0
  fi

  echo ""
  printf "${C_BOLD}  oc 로그인이 되어 있지 않습니다.${C_RESET}\n"
  printf "${C_BOLD}  아래 방법으로 먼저 로그인하세요:${C_RESET}\n"
  echo "    1) 사용자/비밀번호 : oc login https://<api-server>:6443 -u <user> -p <pass>"
  echo "    2) 토큰 사용        : oc login --token=<token> --server=https://<api-server>:6443"
  echo ""
  return 1
}

######################################################################################################
##  Function Name : render_paged_menu
##  Description : 항목 배열을 화면 이분할(2열) + 페이지 단위로 출력한다.
##                요구사항7: 항목이 많을 때 이분할/페이지로 누락 없이 보기 좋게 탐색.
##  information : input $1=제목, $2=페이지번호(0-base), 그리고 표시할 항목들을 전역배열
##                     RENDER_ITEMS[] 에 담아 호출한다 (라벨 문자열 배열).
##                output 화면 출력, 전역 RENDER_TOTAL_PAGES 에 총 페이지 수 저장.
######################################################################################################
render_paged_menu()
{
  local title="$1"
  local page="$2"
  local total=${#RENDER_ITEMS[@]}
  local total_pages=$(( (total + ITEMS_PER_PAGE - 1) / ITEMS_PER_PAGE ))
  [ ${total_pages} -lt 1 ] && total_pages=1
  RENDER_TOTAL_PAGES=${total_pages}

  # 페이지 범위 보정
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
      ltext=$(printf "  [%2d] %s" "$(( lidx + 1 ))" "${RENDER_ITEMS[${lidx}]}")
    fi
    if [ ${ridx} -lt ${total} ]; then
      rtext=$(printf "  [%2d] %s" "$(( ridx + 1 ))" "${RENDER_ITEMS[${ridx}]}")
    fi

    # 양쪽 모두 비어있으면 줄 생략
    if [ -z "${ltext}" ] && [ -z "${rtext}" ]; then
      continue
    fi
    printf "${C_BOLD}%-${col_width}s${C_RESET}| ${C_BOLD}%s${C_RESET}\n" "${ltext}" "${rtext}"
  done

  echo ""
  print_line "-"
  printf "${C_BOLD}  페이지 %d/%d  |  [n]다음 [p]이전 [b]뒤로 [q]종료  |  번호 입력 후 Enter${C_RESET}\n" \
         "$(( page + 1 ))" "${total_pages}"
  print_line "-"
}

######################################################################################################
##  Function Name : select_from_list
##  Description : 페이지형 메뉴에서 사용자의 선택(번호/네비게이션)을 처리한다.
##  information : input $1=제목, $2=결과변수명(선택된 0-base 인덱스 저장)
##                     표시 항목은 전역 RENDER_ITEMS[] 에 미리 채워둔다.
##                output 0=항목선택(인덱스 저장), 1=뒤로(b), 2=종료(q)
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
    printf "  ${C_BOLD}선택: ${C_RESET}"
    # read 가 EOF(입력 종료)를 만나면 종료로 처리하여 무한 루프를 방지한다.
    if ! read -r input; then
      return 2
    fi

    case "${input}" in
      q|Q) return 2 ;;
      b|B) return 1 ;;
      n|N)
        if [ $(( page + 1 )) -lt ${RENDER_TOTAL_PAGES} ]; then page=$(( page + 1 )); fi
        ;;
      p|P)
        if [ ${page} -gt 0 ]; then page=$(( page - 1 )); fi
        ;;
      ''|*[!0-9]*)
        # 숫자가 아니면 무시
        ;;
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
##  Function Name : select_oc_resource
##  Description : oc 리소스 목록을 조회하여 메뉴로 제공하거나, 직접 입력을 받는다.
##                요구사항5: node/pod 등 리소스 인자를 조회 결과에서 선택 or 직접 입력.
##  information : input $1=리소스종류(node/pod/...), $2=결과변수명, $3=(선택)namespace 옵션 문자열
##                output 0=선택/입력완료(값 저장), 1=취소
######################################################################################################
select_oc_resource()
{
  local rtype="$1"
  local __resultvar="$2"
  local ns_opt="$3"
  local choice picked

  echo ""
  printf "  ${C_BOLD}%s 를 선택하는 방법: [1] 목록에서 선택  [2] 직접 입력  [b] 취소${C_RESET}\n" "${rtype}"
  printf "  ${C_BOLD}선택: ${C_RESET}"
  read -r choice

  case "${choice}" in
    2)
      ask_input "${rtype} 이름 입력" picked ""
      [ -z "${picked}" ] && return 1
      eval "${__resultvar}=\"\${picked}\""
      return 0
      ;;
    b|B)
      return 1
      ;;
    *)
      # 목록에서 선택 (기본 동작)
      check_oc_login || { pause_enter; return 1; }
      echo "  ${rtype} 목록 조회 중..."
      # 이름만 추출
      local names
      names=$(eval "oc get ${rtype} ${ns_opt} -o custom-columns=NAME:.metadata.name --no-headers 2>/dev/null")
      if [ -z "${names}" ]; then
        printf "${C_BOLD}  %s 목록을 가져올 수 없습니다. 직접 입력으로 전환합니다.${C_RESET}\n" "${rtype}"
        ask_input "${rtype} 이름 입력" picked ""
        [ -z "${picked}" ] && return 1
        eval "${__resultvar}=\"\${picked}\""
        return 0
      fi

      # RENDER_ITEMS 채우기
      RENDER_ITEMS=()
      local nm
      while IFS= read -r nm; do
        [ -n "${nm}" ] && RENDER_ITEMS+=( "${nm}" )
      done <<< "${names}"

      local idx
      select_from_list "${rtype} 선택" idx
      local rc=$?
      [ ${rc} -ne 0 ] && return 1
      eval "${__resultvar}=\"\${RENDER_ITEMS[${idx}]}\""
      return 0
      ;;
  esac
}

######################################################################################################
##  Function Name : select_namespace
##  Description : namespace 목록을 조회하여 선택하거나, 전체(-A)/직접입력을 받는다.
##  information : input $1=결과변수명(ns 옵션 문자열 저장: "-A" | "-n <ns>" | "")
##                output 0=완료, 1=취소
######################################################################################################
select_namespace()
{
  local __resultvar="$1"
  local choice picked

  echo ""
  printf "  ${C_BOLD}Namespace: [0] 전체(-A)  [1] 목록선택  [2] 직접입력  [b] 취소${C_RESET}\n"
  printf "  ${C_BOLD}선택: ${C_RESET}"
  read -r choice

  case "${choice}" in
    0)  eval "${__resultvar}=\"-A\""; return 0 ;;
    2)
      ask_input "namespace 입력" picked ""
      [ -z "${picked}" ] && return 1
      eval "${__resultvar}=\"-n ${picked}\""
      return 0
      ;;
    b|B) return 1 ;;
    *)
      check_oc_login || { pause_enter; return 1; }
      local names
      names=$(oc get ns -o custom-columns=NAME:.metadata.name --no-headers 2>/dev/null | sort)
      if [ -z "${names}" ]; then
        ask_input "namespace 입력" picked ""
        [ -z "${picked}" ] && return 1
        eval "${__resultvar}=\"-n ${picked}\""
        return 0
      fi
      RENDER_ITEMS=()
      local nm
      while IFS= read -r nm; do
        [ -n "${nm}" ] && RENDER_ITEMS+=( "${nm}" )
      done <<< "${names}"
      local idx
      select_from_list "Namespace 선택" idx
      [ $? -ne 0 ] && return 1
      eval "${__resultvar}=\"-n ${RENDER_ITEMS[${idx}]}\""
      return 0
      ;;
  esac
}

######################################################################################################
##  Function Name : register_cmd
##  Description : 세부 명령어 1건을 메타데이터(CMD_META)에 등록하고, 유형별 목록(CMDLIST)에 추가한다.
##                요구사항6: 명령어 유형/인자 확장을 array 방식으로 쉽게 추가할 수 있도록 한다.
##                요구사항8: 함수 포인터처럼 handler(함수명)를 문자열로 저장하여 eval 호출한다.
##  information : input $1=catid, $2=cmd_id, $3=label, $4=handler(함수명), $5=confirm(Y/N), $6=desc
##                output CMD_META["cmd_id|field"] 저장, CMDLIST[catid] 에 cmd_id 추가 (depth 2 유지)
######################################################################################################
register_cmd()
{
  local catid="$1" cmd_id="$2" label="$3" handler="$4" confirm="$5" desc="$6"
  CMD_META["${cmd_id}|label"]="${label}"
  CMD_META["${cmd_id}|handler"]="${handler}"
  CMD_META["${cmd_id}|confirm"]="${confirm:-N}"
  CMD_META["${cmd_id}|desc"]="${desc}"
  # 유형별 목록에 cmd_id 추가 (공백 구분 문자열 = depth 1 유지)
  if [ -z "${CMDLIST[${catid}]}" ]; then
    CMDLIST["${catid}"]="${cmd_id}"
  else
    CMDLIST["${catid}"]="${CMDLIST[${catid}]} ${cmd_id}"
  fi
}

######################################################################################################
##  Function Name : register_all_commands
##  Description : 모든 유형의 세부 명령어를 메타데이터에 등록한다.
##                여기에 register_cmd 한 줄과 handler 함수만 추가하면 메뉴가 자동 확장된다.
##  information : input none / output CMD_META, CMDLIST 채움
######################################################################################################
register_all_commands()
{
  # ---- [유형1] OCP 리소스 조회 (oc get) --------------------------------------------------------
  # 대표 리소스는 개별 메뉴로, 그 외는 공통 핸들러(임의 리소스 입력)로 처리
  register_cmd ocp_get g_co      "ClusterOperator (co) 조회"       "h_ocget_simple co"            N "클러스터 오퍼레이터 상태"
  register_cmd ocp_get g_mc      "MachineConfig (mc) 조회"         "h_ocget_simple mc"            N "머신 설정"
  register_cmd ocp_get g_mcp     "MachineConfigPool (mcp) 조회"    "h_ocget_simple mcp"           N "머신 설정 풀"
  register_cmd ocp_get g_cs      "CatalogSource 조회"              "h_ocget_ns catalogsource"     N "오퍼레이터 카탈로그 소스"
  register_cmd ocp_get g_idms    "IDMS 조회"                       "h_ocget_simple idms"          N "ImageDigestMirrorSet"
  register_cmd ocp_get g_itms    "ITMS 조회"                       "h_ocget_simple itms"          N "ImageTagMirrorSet"
  register_cmd ocp_get g_node    "Node 조회 (-o wide)"             "h_ocget_node"                 N "노드 상태/역할/버전"
  register_cmd ocp_get g_pod     "Pod 조회"                        "h_ocget_ns pod"               N "Pod 목록"
  register_cmd ocp_get g_svc     "Service 조회"                    "h_ocget_ns service"           N "서비스 목록"
  register_cmd ocp_get g_scc     "SCC 조회"                        "h_ocget_simple scc"           N "SecurityContextConstraints"
  register_cmd ocp_get g_pdb     "PDB 조회"                        "h_ocget_ns pdb"               N "PodDisruptionBudget"
  register_cmd ocp_get g_job     "Job 조회"                        "h_ocget_ns job"               N "Job 목록"
  register_cmd ocp_get g_sts     "StatefulSet 조회"                "h_ocget_ns statefulset"       N "StatefulSet 목록"
  register_cmd ocp_get g_pv      "PV 조회"                         "h_ocget_simple pv"            N "PersistentVolume"
  register_cmd ocp_get g_pvc     "PVC 조회"                        "h_ocget_ns pvc"               N "PersistentVolumeClaim"
  register_cmd ocp_get g_csr     "CSR 조회"                        "h_ocget_simple csr"           N "CertificateSigningRequest"
  register_cmd ocp_get g_cm      "ConfigMap 조회"                  "h_ocget_ns configmap"         N "ConfigMap 목록"
  register_cmd ocp_get g_secret  "Secret 조회"                     "h_ocget_ns secret"            N "Secret 목록"
  # 전문가 관점 보완 리소스
  register_cmd ocp_get g_cv      "ClusterVersion 조회"             "h_ocget_simple clusterversion" N "클러스터 버전/업그레이드 상태"
  register_cmd ocp_get g_operator "Operator(CSV) 조회"             "h_ocget_ns csv"               N "설치된 Operator(ClusterServiceVersion)"
  register_cmd ocp_get g_ip      "InstallPlan 조회"                "h_ocget_ns installplan"       N "Operator 설치 계획"
  register_cmd ocp_get g_event   "Event 조회 (시간순)"             "h_ocget_event"                N "네임스페이스 이벤트"
  register_cmd ocp_get g_podimg  "Pod 이미지 정보 조회"            "h_pod_images"                 N "Pod 컨테이너/이미지(이름·이미지·imageID) 목록"
  register_cmd ocp_get g_free    "임의 리소스 직접 조회"           "h_ocget_free"                 N "리소스 종류를 직접 입력하여 조회"

  # ---- [유형1-2] OCP 인증서 조회 -----------------------------------------------------------------
  register_cmd ocp_cert c_all     "전체 TLS Secret 만료일 조회"    "h_cert_all"        N "모든 namespace 의 kubernetes.io/tls Secret 만료일"
  register_cmd ocp_cert c_one     "특정 Secret 인증서 상세/만료"   "h_cert_secret"     N "선택 Secret 의 인증서 상세 및 enddate"
  register_cmd ocp_cert c_node    "Node kubelet 인증서 만료일"     "h_cert_node"       N "노드 kubelet client/serving 인증서 만료일"
  register_cmd ocp_cert c_apiurl  "API endpoint 인증서 만료일"     "h_cert_apiurl"     N "openssl s_client 로 서버 인증서 만료일 확인"

  # ---- [유형1-3] OCP 관리 작업 (oc adm / patch) --------------------------------------------------
  register_cmd ocp_adm a_patch    "리소스 patch (oc patch)"        "h_adm_patch"       Y "리소스에 JSON/merge patch 적용 (변경 주의)"
  register_cmd ocp_adm a_cordon   "노드 cordon (스케줄 차단)"      "h_adm_cordon"      Y "oc adm cordon <node>"
  register_cmd ocp_adm a_uncordon "노드 uncordon (스케줄 허용)"    "h_adm_uncordon"    Y "oc adm uncordon <node>"
  register_cmd ocp_adm a_drain    "노드 drain (Pod 축출)"          "h_adm_drain"       Y "oc adm drain <node> (주의)"
  register_cmd ocp_adm a_top_node "노드 리소스 사용량 (top node)"  "h_adm_top_node"    N "oc adm top node"
  register_cmd ocp_adm a_top_pod  "Pod 리소스 사용량 (top pod)"    "h_adm_top_pod"     N "oc adm top pod -n <ns>"

  # ---- [유형2] OCP 노드 접속 실행 (oc debug node) ----------------------------------------------
  register_cmd ocp_node n_multipath "multipath 설정 확인"          "h_node_run 'cat /etc/multipath.conf'"    N "멀티패스 설정 파일"
  register_cmd ocp_node n_mount     "마운트 정보 확인"             "h_node_run 'mount'"                      N "마운트 목록"
  register_cmd ocp_node n_lsblk     "블록 디바이스 확인"           "h_node_run 'lsblk'"                      N "디스크/파티션"
  register_cmd ocp_node n_chrony    "chrony 시간 동기화 확인"      "h_node_run 'chronyc sources -v'"         N "노드 시간 동기화"
  register_cmd ocp_node n_nic       "네트워크 인터페이스 확인"     "h_node_run 'ip -br addr'"                N "NIC 상태/IP"
  register_cmd ocp_node n_route     "라우팅 테이블 확인"           "h_node_run 'ip route'"                   N "라우팅"
  register_cmd ocp_node n_journal   "kubelet 로그 확인(최근100)"   "h_node_run 'journalctl -u kubelet --no-pager -n 100'" N "kubelet 저널"
  register_cmd ocp_node n_ss        "노드 소켓/포트 상태(ss)"      "h_node_run 'ss -tulnp'"                  N "노드 리스닝 포트/연결 상태"
  register_cmd ocp_node n_tcpdump   "노드 tcpdump 패킷 캡처"       "h_node_tcpdump"                          Y "노드에서 인터페이스/필터 기반 캡처(-c 제한)"
  register_cmd ocp_node n_free      "노드 명령 직접 입력"          "h_node_free"                             N "임의 명령을 노드에서 실행"

  # ---- [유형6-2] 테스트 이미지 (busybox/toolbox/nginx) -----------------------------------------
  register_cmd test_img t_busybox   "busybox 테스트 Pod 실행"      "h_test_busybox"    N "임시 busybox Pod 로 네트워크/DNS 테스트"
  register_cmd test_img t_nginx     "nginx 테스트 Pod 실행"        "h_test_nginx"      N "임시 nginx Pod 배포 후 curl 테스트"
  register_cmd test_img t_toolbox   "toolbox 사용 안내(노드)"      "h_test_toolbox"    N "노드에서 toolbox 로 진단 도구 사용"
  register_cmd test_img t_cleanup   "테스트 리소스 정리"           "h_test_cleanup"    Y "생성한 테스트 Pod 삭제"

  # ---- [유형] Istio 서비스메시 (istioctl) --------------------------------------------------------
  register_cmd istio i_version   "istioctl version"             "h_istio_version"       N "istioctl/컨트롤플레인 버전"
  register_cmd istio i_pstatus   "proxy-status 조회"            "h_istio_proxy_status"  N "istioctl proxy-status (sidecar 동기화 상태)"
  register_cmd istio i_pconfig   "proxy-config 조회"            "h_istio_proxy_config"  N "istioctl proxy-config (cluster/listener/route 등)"
  register_cmd istio i_analyze   "구성 분석 (analyze)"          "h_istio_analyze"       N "istioctl analyze (설정 문제 진단)"
  register_cmd istio i_free      "istioctl 명령 직접 입력"      "h_istio_free"          N "임의 istioctl 하위명령 실행"

  # ---- [유형] 유틸리티 (crt merge / json merge / openssl) ---------------------------------------
  register_cmd util u_crt_cm     "crt merge -> ConfigMap 생성/patch" "h_util_crt_configmap"  Y "복수 crt 를 하나로 합쳐 CA bundle ConfigMap 생성/patch"
  register_cmd util u_json_merge "복수 JSON -> merged JSON (jq)"     "h_util_json_merge"     N "여러 JSON 파일을 하나로 병합"
  register_cmd util u_openssl    "openssl 사용법/실행"               "h_util_openssl"        N "인증서 확인/변환 등 openssl 대표 명령"

  # ---- [유형3] OCP 파일 송수신 (oc cp / rsync) -------------------------------------------------
  register_cmd ocp_file f_download  "Pod -> 로컬 다운로드 (oc cp)" "h_cp_download"   N "Pod 내부 파일을 로컬로 복사"
  register_cmd ocp_file f_upload    "로컬 -> Pod 업로드 (oc cp)"   "h_cp_upload"     N "로컬 파일을 Pod로 복사"
  register_cmd ocp_file f_rsync     "디렉토리 동기화 (oc rsync)"   "h_rsync"         N "Pod 디렉토리 rsync"

  # ---- [유형4] OCP Pod 실행/진입 (oc exec/rsh/logs) --------------------------------------------
  register_cmd ocp_exec e_exec      "Pod 명령 실행 (oc exec)"      "h_pod_exec"      N "Pod에서 단일 명령 실행"
  register_cmd ocp_exec e_rsh       "Pod 접속 (oc rsh)"            "h_pod_rsh"       N "Pod 셸 접속"
  register_cmd ocp_exec e_logs      "Pod 로그 (oc logs)"           "h_pod_logs"      N "Pod 로그 tail"

  # ---- [유형5] Podman 레지스트리 ----------------------------------------------------------------
  register_cmd podman_reg p_login   "레지스트리 로그인"            "h_podman_login"       N "podman login <registry>"
  register_cmd podman_reg p_catalog "카탈로그 조회(_catalog)"      "h_podman_catalog"     N "curl _catalog 로 저장소 목록"
  register_cmd podman_reg p_tags    "태그 목록 조회(tags/list)"    "h_podman_tags"        N "curl tags/list 로 태그 목록"
  register_cmd podman_reg p_inspect "이미지 상세(inspect)"         "h_podman_inspect"     N "skopeo/podman inspect"
  register_cmd podman_reg p_pull    "이미지 pull"                  "h_podman_pull"        N "podman pull"
  register_cmd podman_reg p_tag     "이미지 태그 추가/복사"        "h_podman_tag"         N "podman tag (신규 태그 부여)"
  register_cmd podman_reg p_push    "이미지 push"                  "h_podman_push"        N "podman push (레지스트리 업로드)"
  register_cmd podman_reg p_rmi     "이미지 삭제(rmi)"             "h_podman_rmi"         Y "로컬 이미지 삭제 (주의)"
  register_cmd podman_reg p_delete  "레지스트리 태그 삭제"         "h_podman_delete_tag"  Y "레지스트리에서 태그 삭제 (주의)"

  # ---- [유형6] 네트워크 진단 --------------------------------------------------------------------
  register_cmd net_diag d_curl      "curl 호출 테스트"             "h_curl_basic"     N "URL 호출/응답 확인"
  register_cmd net_diag d_curl_res  "curl --resolve 도메인 치환"   "h_curl_resolve"   N "DNS 우회하여 특정 IP로 호출"
  register_cmd net_diag d_curl_conn "curl --connect-to 포트/호스트 변경" "h_curl_connect_to" N "도메인 유지+다른 host:port로 접속(예 8081)"
  register_cmd net_diag d_ncat      "ncat 포트 연결 테스트"        "h_ncat"           N "TCP 포트 오픈 여부/패킷 확인"
  register_cmd net_diag d_ping      "ping 테스트"                  "h_ping"           N "ICMP 도달성"
  register_cmd net_diag d_ss        "소켓/포트 상태(ss)"           "h_ss"             N "리스닝 포트/연결 상태"
  register_cmd net_diag d_tcpdump   "tcpdump 패킷 캡처"            "h_tcpdump"        Y "인터페이스/필터 기반 패킷 캡처"

  # ---- [유형7] 시스템/네트워크 ------------------------------------------------------------------
  register_cmd sys_net s_chrony     "chrony 소스 확인"             "h_chrony_sources"  N "chronyc sources"
  register_cmd sys_net s_chrony_track "chrony 동기화 상태"         "h_chrony_tracking" N "chronyc tracking"
  register_cmd sys_net s_nic_info   "NIC 정보 조회"                "h_nic_info"        N "ip -br addr / nmcli"
  register_cmd sys_net s_nic_up     "NIC UP (활성화)"              "h_nic_up"          Y "인터페이스 활성화"
  register_cmd sys_net s_nic_down   "NIC DOWN (비활성화)"          "h_nic_down"        Y "인터페이스 비활성화 (주의)"
  register_cmd sys_net s_route      "라우팅 테이블 조회"           "h_route"           N "ip route"
}

# --------------------------------------------------------------------------------------------------
# [유형1] OCP 리소스 조회 핸들러
# --------------------------------------------------------------------------------------------------

######################################################################################################
##  Function Name : h_ocget_simple
##  Description : 클러스터 스코프 리소스를 조회한다. (namespace 불필요)
##  information : input $1=리소스종류(co/mc/mcp/scc/pv/csr/clusterversion 등) / output 조회 결과
######################################################################################################
h_ocget_simple()
{
  local rtype="$1"
  check_oc_login || { pause_enter; return 1; }
  run_cmd "oc get ${rtype} -o wide 2>/dev/null || oc get ${rtype}"
  pause_enter
}

######################################################################################################
##  Function Name : h_ocget_ns
##  Description : namespace 스코프 리소스를 조회한다. (전체/특정 NS 선택)
##  information : input $1=리소스종류(pod/svc/pvc/cm/secret 등) / output 조회 결과
######################################################################################################
h_ocget_ns()
{
  local rtype="$1"
  local ns_opt=""
  check_oc_login || { pause_enter; return 1; }

  select_namespace ns_opt
  [ $? -ne 0 ] && return 1

  run_cmd "oc get ${rtype} ${ns_opt}"
  pause_enter
}

######################################################################################################
##  Function Name : h_ocget_node
##  Description : Node 목록을 상세(-o wide)로 조회한다.
##  information : input none / output 노드 상태/역할/버전
######################################################################################################
h_ocget_node()
{
  check_oc_login || { pause_enter; return 1; }
  run_cmd "oc get node -o wide"
  pause_enter
}

######################################################################################################
##  Function Name : h_ocget_event
##  Description : 이벤트를 시간순으로 조회한다. (전체/특정 NS 선택)
##  information : input none / output 이벤트 목록
######################################################################################################
h_ocget_event()
{
  local ns_opt=""
  check_oc_login || { pause_enter; return 1; }
  select_namespace ns_opt
  [ $? -ne 0 ] && return 1
  run_cmd "oc get events ${ns_opt} --sort-by='.lastTimestamp'"
  pause_enter
}

######################################################################################################
##  Function Name : h_ocget_free
##  Description : 사용자가 리소스 종류를 직접 입력하여 조회한다. (확장/학습용)
##  information : input none / output 조회 결과
######################################################################################################
h_ocget_free()
{
  local rtype ns_opt="" extra
  check_oc_login || { pause_enter; return 1; }

  ask_input "조회할 리소스 종류 입력 (예: deployment, ingress, clusteroperator)" rtype ""
  [ -z "${rtype}" ] && return 1

  echo ""
  printf "  ${C_BOLD}namespace 스코프 리소스입니까? [y] 예(NS선택)  [N] 아니오(클러스터)${C_RESET}\n"
  printf "  ${C_BOLD}선택: ${C_RESET}"
  local scope
  read -r scope
  if [ "${scope}" = "y" ] || [ "${scope}" = "Y" ]; then
    select_namespace ns_opt
    [ $? -ne 0 ] && return 1
  fi

  ask_input "추가 옵션 입력(선택, 예: -o wide / -o yaml)" extra ""
  run_cmd "oc get ${rtype} ${ns_opt} ${extra}"
  pause_enter
}

# --------------------------------------------------------------------------------------------------
# [유형2] OCP 노드 접속 실행 핸들러 (oc debug node)
# --------------------------------------------------------------------------------------------------

######################################################################################################
##  Function Name : h_node_run
##  Description : 노드에 oc debug 로 접속하여 chroot /host 후 지정된 명령을 실행한다.
##                요구사항5: oc debug node/<node> -- chroot /host <cmd> 형태.
##  information : input $1=노드에서 실행할 명령 문자열 / output 실행 결과
######################################################################################################
h_node_run()
{
  local inner_cmd="$1"
  local node=""
  check_oc_login || { pause_enter; return 1; }

  # 노드 선택 (목록/직접입력)
  select_oc_resource "node" node ""
  [ $? -ne 0 ] && return 1
  [ -z "${node}" ] && { echo "  노드가 지정되지 않았습니다."; pause_enter; return 1; }

  # oc debug 는 chroot /host 후 명령 실행. -q 로 부가메시지 최소화.
  run_cmd "oc debug node/${node} -q -- chroot /host /bin/bash -c \"${inner_cmd}\""
  pause_enter
}

######################################################################################################
##  Function Name : h_node_free
##  Description : 노드에서 실행할 명령을 직접 입력받아 실행한다. (학습/확장용)
##  information : input none / output 실행 결과
######################################################################################################
h_node_free()
{
  local node="" inner_cmd=""
  check_oc_login || { pause_enter; return 1; }

  select_oc_resource "node" node ""
  [ $? -ne 0 ] && return 1

  ask_input "노드에서 실행할 명령 입력 (예: cat /etc/resolv.conf)" inner_cmd ""
  [ -z "${inner_cmd}" ] && return 1

  run_cmd "oc debug node/${node} -q -- chroot /host /bin/bash -c \"${inner_cmd}\""
  pause_enter
}

# --------------------------------------------------------------------------------------------------
# [유형3] OCP 파일 송수신 핸들러 (oc cp / rsync)
# --------------------------------------------------------------------------------------------------

######################################################################################################
##  Function Name : h_cp_download
##  Description : Pod 내부 파일을 로컬로 다운로드한다. (oc cp <ns>/<pod>:<path> <local>)
##  information : input none / output 복사 결과
######################################################################################################
h_cp_download()
{
  local ns_opt="" ns pod src dst
  check_oc_login || { pause_enter; return 1; }

  select_namespace ns_opt
  [ $? -ne 0 ] && return 1
  # ns_opt 는 "-n <ns>" 형태 -> ns 이름만 추출 (oc cp 는 <ns>/<pod> 형식 사용)
  ns=$(echo "${ns_opt}" | sed 's/^-n //')
  [ "${ns_opt}" = "-A" ] && { echo "  파일 복사는 특정 namespace를 선택해야 합니다."; pause_enter; return 1; }

  select_oc_resource "pod" pod "-n ${ns}"
  [ $? -ne 0 ] && return 1

  ask_input "Pod 내부 원본 경로 (예: /etc/multipath.conf)" src ""
  ask_input "로컬 저장 경로" dst "./$(basename "${src}")"
  [ -z "${src}" ] && return 1

  run_cmd "oc cp ${ns}/${pod}:${src} ${dst}"
  pause_enter
}

######################################################################################################
##  Function Name : h_cp_upload
##  Description : 로컬 파일을 Pod 내부로 업로드한다. (oc cp <local> <ns>/<pod>:<path>)
##  information : input none / output 복사 결과
######################################################################################################
h_cp_upload()
{
  local ns_opt="" ns pod src dst
  check_oc_login || { pause_enter; return 1; }

  select_namespace ns_opt
  [ $? -ne 0 ] && return 1
  ns=$(echo "${ns_opt}" | sed 's/^-n //')
  [ "${ns_opt}" = "-A" ] && { echo "  파일 복사는 특정 namespace를 선택해야 합니다."; pause_enter; return 1; }

  select_oc_resource "pod" pod "-n ${ns}"
  [ $? -ne 0 ] && return 1

  ask_input "로컬 원본 경로" src ""
  ask_input "Pod 내부 대상 경로 (예: /tmp/upload.dat)" dst ""
  [ -z "${src}" ] && return 1
  [ -z "${dst}" ] && return 1

  run_cmd "oc cp ${src} ${ns}/${pod}:${dst}"
  pause_enter
}

######################################################################################################
##  Function Name : h_rsync
##  Description : Pod 디렉토리를 oc rsync 로 동기화한다.
##  information : input none / output 동기화 결과
######################################################################################################
h_rsync()
{
  local ns_opt="" ns pod direction src dst
  check_oc_login || { pause_enter; return 1; }

  select_namespace ns_opt
  [ $? -ne 0 ] && return 1
  ns=$(echo "${ns_opt}" | sed 's/^-n //')
  [ "${ns_opt}" = "-A" ] && { echo "  rsync 는 특정 namespace를 선택해야 합니다."; pause_enter; return 1; }

  select_oc_resource "pod" pod "-n ${ns}"
  [ $? -ne 0 ] && return 1

  echo ""
  printf "  ${C_BOLD}방향: [1] Pod->로컬(다운로드)  [2] 로컬->Pod(업로드)${C_RESET}\n"
  printf "  ${C_BOLD}선택: ${C_RESET}"
  read -r direction

  if [ "${direction}" = "2" ]; then
    ask_input "로컬 원본 디렉토리" src "./"
    ask_input "Pod 내부 대상 디렉토리" dst "/tmp/"
    run_cmd "oc rsync ${src} ${ns}/${pod}:${dst}"
  else
    ask_input "Pod 내부 원본 디렉토리" src "/tmp/"
    ask_input "로컬 대상 디렉토리" dst "./"
    run_cmd "oc rsync ${ns}/${pod}:${src} ${dst}"
  fi
  pause_enter
}

# --------------------------------------------------------------------------------------------------
# [유형4] OCP Pod 실행/진입 핸들러 (oc exec / rsh / logs)
# --------------------------------------------------------------------------------------------------

######################################################################################################
##  Function Name : h_pod_exec
##  Description : Pod에서 단일 명령을 실행한다. (oc exec)
##  information : input none / output 실행 결과
######################################################################################################
h_pod_exec()
{
  local ns_opt="" ns pod inner_cmd
  check_oc_login || { pause_enter; return 1; }

  select_namespace ns_opt
  [ $? -ne 0 ] && return 1
  ns=$(echo "${ns_opt}" | sed 's/^-n //')
  [ "${ns_opt}" = "-A" ] && { echo "  exec 는 특정 namespace를 선택해야 합니다."; pause_enter; return 1; }

  select_oc_resource "pod" pod "-n ${ns}"
  [ $? -ne 0 ] && return 1

  ask_input "Pod에서 실행할 명령 (예: cat /etc/multipath.conf)" inner_cmd ""
  [ -z "${inner_cmd}" ] && return 1

  run_cmd "oc exec -n ${ns} pod/${pod} -- /bin/sh -c \"${inner_cmd}\""
  pause_enter
}

######################################################################################################
##  Function Name : h_pod_rsh
##  Description : Pod에 셸로 접속한다. (oc rsh) - 대화형이므로 실행문만 안내 후 접속.
##  information : input none / output 대화형 셸 세션
######################################################################################################
h_pod_rsh()
{
  local ns_opt="" ns pod
  check_oc_login || { pause_enter; return 1; }

  select_namespace ns_opt
  [ $? -ne 0 ] && return 1
  ns=$(echo "${ns_opt}" | sed 's/^-n //')
  [ "${ns_opt}" = "-A" ] && { echo "  rsh 는 특정 namespace를 선택해야 합니다."; pause_enter; return 1; }

  select_oc_resource "pod" pod "-n ${ns}"
  [ $? -ne 0 ] && return 1

  # 대화형 세션: 실행문 표시 후 그대로 실행 (종료 시 메뉴로 복귀)
  run_cmd "oc rsh -n ${ns} pod/${pod}"
  pause_enter
}

######################################################################################################
##  Function Name : h_pod_logs
##  Description : Pod 로그를 tail 로 조회한다. (oc logs)
##  information : input none / output 로그 출력
######################################################################################################
h_pod_logs()
{
  local ns_opt="" ns pod tail_n
  check_oc_login || { pause_enter; return 1; }

  select_namespace ns_opt
  [ $? -ne 0 ] && return 1
  ns=$(echo "${ns_opt}" | sed 's/^-n //')
  [ "${ns_opt}" = "-A" ] && { echo "  logs 는 특정 namespace를 선택해야 합니다."; pause_enter; return 1; }

  select_oc_resource "pod" pod "-n ${ns}"
  [ $? -ne 0 ] && return 1

  ask_input "출력할 로그 줄 수(tail)" tail_n "100"
  run_cmd "oc logs -n ${ns} pod/${pod} --tail=${tail_n}"
  pause_enter
}

# --------------------------------------------------------------------------------------------------
# [유형5] Podman 레지스트리 핸들러
#   - catalog/tags 조회는 Docker Registry HTTP API v2 를 curl 로 호출한다.
#   - 인증이 필요한 경우 -u <user>:<pass> 또는 사전 podman login 을 사용한다.
# --------------------------------------------------------------------------------------------------

######################################################################################################
##  Function Name : h_podman_login
##  Description : private registry 에 로그인한다. (podman login)
##  information : input none / output 로그인 결과
######################################################################################################
h_podman_login()
{
  local reg user
  check_cmd_exist "podman" || { pause_enter; return 1; }
  ask_input "레지스트리 주소 (엔터 시 기본값 사용)" reg "${DEFAULT_REGISTRY}"
  [ -z "${reg}" ] && return 1
  ask_input "사용자명" user ""
  # 비밀번호는 podman 이 대화형으로 안전하게 입력받도록 --password-stdin 대신 프롬프트 사용
  run_cmd "podman login ${reg} -u ${user}"
  pause_enter
}

######################################################################################################
##  Function Name : h_podman_catalog
##  Description : 레지스트리의 저장소(repository) 목록을 조회한다. (_catalog API)
##                _catalog 는 기본적으로 일부만(페이지) 반환할 수 있으므로, 조회 방식을 선택한다.
##                  [1] 전체 목록  : ?n=<큰수> 로 한 번에 많이 가져온 뒤, Link 헤더가 있으면
##                                   추가 페이지(last 기준)를 반복 조회하여 모두 합친다.
##                  [2] 개수 지정   : ?n=<입력값> 로 지정 개수만 조회.
##                  [3] 기본 조회   : 옵션 없이 조회(레지스트리 기본 동작).
##  information : input none / output 저장소(repository) 전체 목록
######################################################################################################
h_podman_catalog()
{
  local reg auth mode nval
  check_cmd_exist "curl" || { pause_enter; return 1; }
  ask_input "레지스트리 주소 (엔터 시 기본값 사용)" reg "${DEFAULT_REGISTRY}"
  [ -z "${reg}" ] && return 1
  ask_input "인증 옵션(선택, 예: -u user:pass)" auth ""

  echo ""
  printf "  ${C_BOLD}조회 방식: [1] 전체 목록(권장)  [2] 개수 지정(n)  [3] 기본 조회${C_RESET}\n"
  printf "  ${C_BOLD}선택: ${C_RESET}"
  read -r mode

  local jq_filter="cat"
  if command -v jq >/dev/null 2>&1; then
    jq_filter="jq ."
  fi

  case "${mode}" in
    2)
      ask_input "가져올 repository 개수(n)" nval "1000"
      run_cmd "curl -sk ${auth} 'https://${reg}/v2/_catalog?n=${nval}' | ${jq_filter}"
      pause_enter
      ;;
    3)
      run_cmd "curl -sk ${auth} https://${reg}/v2/_catalog | ${jq_filter}"
      pause_enter
      ;;
    *)
      # [1] 전체 목록: Link 헤더 기반 페이지네이션을 따라가며 모든 repository 를 수집한다.
      #    Registry API 는 결과가 많으면 응답 헤더에 다음 페이지를 가리키는 Link 를 준다.
      #    학습을 위해 대표 실행문을 먼저 보여준 뒤, 실제 수집은 반복 호출로 처리한다.
      show_exec_cmd "curl -sk ${auth} 'https://${reg}/v2/_catalog?n=1000' (Link 헤더가 있으면 ?last=<마지막repo> 로 반복)"

      if ! command -v jq >/dev/null 2>&1; then
        printf "${C_BOLD}  [참고] jq 미설치: 페이지 자동 병합이 제한됩니다. n=100000 로 일괄 조회합니다.${C_RESET}\n"
        run_cmd "curl -sk ${auth} 'https://${reg}/v2/_catalog?n=100000'"
        pause_enter
        return 0
      fi

      local page_size=1000
      local last=""
      local url resp names all_file hdr_file
      init_meta
      all_file="${META_DIR}/catalog_all.txt"
      hdr_file="${META_DIR}/catalog_hdr.txt"
      : > "${all_file}"

      echo ""
      while true; do
        if [ -z "${last}" ]; then
          url="https://${reg}/v2/_catalog?n=${page_size}"
        else
          # last 값은 URL 인코딩이 필요할 수 있으나 일반 repo 명은 그대로 사용 가능
          url="https://${reg}/v2/_catalog?n=${page_size}&last=${last}"
        fi

        # 헤더(-D)와 본문을 함께 받아 다음 페이지 존재 여부를 판단한다.
        resp=$(eval "curl -sk ${auth} -D '${hdr_file}' '${url}'" 2>/dev/null)
        names=$(echo "${resp}" | jq -r '.repositories[]?' 2>/dev/null)

        if [ -z "${names}" ]; then
          break
        fi
        echo "${names}" >> "${all_file}"

        # 다음 페이지(Link 헤더) 존재 여부 확인. 없으면 종료.
        if ! grep -qi '^Link:' "${hdr_file}" 2>/dev/null; then
          break
        fi
        # 이번 페이지의 마지막 repo 를 다음 요청의 last 로 사용
        last=$(echo "${names}" | tail -n 1)
        [ -z "${last}" ] && break
      done

      local total
      total=$(grep -c . "${all_file}" 2>/dev/null)
      printf "${C_BOLD}  전체 repository 수: %s${C_RESET}\n" "${total:-0}"
      print_line "-"
      sort "${all_file}" 2>/dev/null
      pause_enter
      ;;
  esac
}

######################################################################################################
##  Function Name : h_podman_tags
##  Description : 특정 저장소(image)의 태그 목록을 조회한다. (tags/list API)
##  information : input none / output 태그 목록(JSON)
######################################################################################################
h_podman_tags()
{
  local reg repo auth
  check_cmd_exist "curl" || { pause_enter; return 1; }
  ask_input "레지스트리 주소 (엔터 시 기본값 사용)" reg "${DEFAULT_REGISTRY}"
  [ -z "${reg}" ] && return 1
  ask_input "이미지(저장소) 경로 (예: openshift/ose-cli)" repo ""
  [ -z "${repo}" ] && return 1
  ask_input "인증 옵션(선택, 예: -u user:pass)" auth ""
  if command -v jq >/dev/null 2>&1; then
    run_cmd "curl -sk ${auth} https://${reg}/v2/${repo}/tags/list | jq ."
  else
    run_cmd "curl -sk ${auth} https://${reg}/v2/${repo}/tags/list"
  fi
  pause_enter
}

######################################################################################################
##  Function Name : h_podman_inspect
##  Description : 원격/로컬 이미지의 상세 정보를 조회한다. (skopeo inspect 우선, 없으면 podman)
##  information : input none / output 이미지 메타데이터
######################################################################################################
h_podman_inspect()
{
  local image auth
  ask_input "이미지 전체 경로 (예: registry.example.com:5000/openshift/ose-cli:latest)" image ""
  [ -z "${image}" ] && return 1

  if command -v skopeo >/dev/null 2>&1; then
    ask_input "인증 옵션(선택, 예: --creds user:pass)" auth ""
    run_cmd "skopeo inspect --tls-verify=false ${auth} docker://${image}"
  else
    check_cmd_exist "podman" || { pause_enter; return 1; }
    run_cmd "podman inspect ${image}"
  fi
  pause_enter
}

######################################################################################################
##  Function Name : h_podman_pull
##  Description : 이미지를 pull 한다. (podman pull)
##  information : input none / output pull 결과
######################################################################################################
h_podman_pull()
{
  local image
  check_cmd_exist "podman" || { pause_enter; return 1; }
  ask_input "pull 할 이미지 경로 (예: registry.example.com:5000/app:1.0)" image ""
  [ -z "${image}" ] && return 1
  run_cmd "podman pull --tls-verify=false ${image}"
  pause_enter
}

######################################################################################################
##  Function Name : h_podman_tag
##  Description : 기존 이미지에 새 태그를 추가/복사한다. (podman tag)
##                이미지 복사(레지스트리 이관) 시 tag -> push 흐름의 첫 단계.
##  information : input none / output 태그 결과
######################################################################################################
h_podman_tag()
{
  local src dst
  check_cmd_exist "podman" || { pause_enter; return 1; }
  ask_input "원본 이미지 (예: app:1.0 또는 registry/app:1.0)" src ""
  ask_input "새 태그 (예: registry.example.com:5000/app:1.0)" dst ""
  [ -z "${src}" ] && return 1
  [ -z "${dst}" ] && return 1
  run_cmd "podman tag ${src} ${dst}"
  pause_enter
}

######################################################################################################
##  Function Name : h_podman_push
##  Description : 이미지를 레지스트리로 push 한다. (podman push)
##  information : input none / output push 결과
######################################################################################################
h_podman_push()
{
  local image
  check_cmd_exist "podman" || { pause_enter; return 1; }
  ask_input "push 할 이미지 경로 (예: registry.example.com:5000/app:1.0)" image ""
  [ -z "${image}" ] && return 1
  run_cmd "podman push --tls-verify=false ${image}"
  pause_enter
}

######################################################################################################
##  Function Name : h_podman_rmi
##  Description : 로컬 이미지를 삭제한다. (podman rmi) - 되돌리기 어려우므로 confirm.
##  information : input none / output 삭제 결과
######################################################################################################
h_podman_rmi()
{
  local image
  check_cmd_exist "podman" || { pause_enter; return 1; }
  ask_input "삭제할 로컬 이미지 (예: app:1.0 또는 이미지ID)" image ""
  [ -z "${image}" ] && return 1
  # confirm 은 register_cmd 의 confirm=Y 로 run_cmd 에서 처리하도록 전달
  run_cmd "podman rmi ${image}" "Y"
  pause_enter
}

######################################################################################################
##  Function Name : h_podman_delete_tag
##  Description : 레지스트리에서 특정 태그(매니페스트)를 삭제한다. (Registry API DELETE)
##                digest 를 먼저 조회한 뒤 삭제한다. 되돌리기 어려우므로 confirm.
##  information : input none / output 삭제 결과
######################################################################################################
h_podman_delete_tag()
{
  local reg repo tag auth digest
  check_cmd_exist "curl" || { pause_enter; return 1; }
  ask_input "레지스트리 주소 (엔터 시 기본값 사용)" reg "${DEFAULT_REGISTRY}"
  ask_input "이미지(저장소) 경로 (예: openshift/ose-cli)" repo ""
  ask_input "삭제할 태그 (예: v1.0)" tag ""
  ask_input "인증 옵션(선택, 예: -u user:pass)" auth ""
  [ -z "${reg}" ] && return 1
  [ -z "${repo}" ] && return 1
  [ -z "${tag}" ] && return 1

  # 1) 태그의 digest 조회 (Accept 헤더로 manifest v2 요청)
  show_exec_cmd "curl -sk ${auth} -I -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' https://${reg}/v2/${repo}/manifests/${tag}"
  digest=$(curl -sk ${auth} -I -H 'Accept: application/vnd.docker.distribution.manifest.v2+json' \
           "https://${reg}/v2/${repo}/manifests/${tag}" 2>/dev/null \
           | tr -d '\r' | awk -F': ' '/[Dd]ocker-[Cc]ontent-[Dd]igest/ {print $2}')

  if [ -z "${digest}" ]; then
    printf "${C_BOLD}  digest 를 조회하지 못했습니다. (레지스트리 삭제 활성화 여부/권한 확인)${C_RESET}\n"
    pause_enter
    return 1
  fi
  echo "  조회된 digest: ${digest}"

  # 2) digest 기준으로 삭제 (confirm)
  run_cmd "curl -sk ${auth} -X DELETE https://${reg}/v2/${repo}/manifests/${digest}" "Y"
  pause_enter
}

# --------------------------------------------------------------------------------------------------
# [유형6] 네트워크 진단 핸들러 (curl / ncat / ping / ss)
# --------------------------------------------------------------------------------------------------

######################################################################################################
##  Function Name : h_curl_basic
##  Description : URL 을 호출하여 응답 헤더/상태를 확인한다. (curl -v)
##  information : input none / output 호출 결과
######################################################################################################
h_curl_basic()
{
  local url extra
  check_cmd_exist "curl" || { pause_enter; return 1; }
  ask_input "호출할 URL (예: https://api.example.com/healthz)" url ""
  [ -z "${url}" ] && return 1
  ask_input "추가 옵션(선택, 예: -k -H 'Host: a.b.c')" extra "-sk -o /dev/null -w 'HTTP:%{http_code} time:%{time_total}s\\n'"
  run_cmd "curl ${extra} ${url}"
  pause_enter
}

######################################################################################################
##  Function Name : h_curl_resolve
##  Description : --resolve 로 도메인을 특정 IP로 치환하여 호출한다. (DNS 우회 테스트)
##                표준 문법: --resolve <HOST>:<PORT>:<ADDRESS>[,ADDRESS...]
##                  - HOST    : 이름 해석 대상 도메인
##                  - PORT    : 접속하려는 "요청 URL의 포트" (커스텀 포트면 URL 포트와 반드시 일치)
##                  - ADDRESS : 실제 IP. 여러 개는 콤마(,)로 구분 가능.
##                요구사항: 커스텀 포트(예: 8081) 호출 시에는 PORT 를 8081 로 지정하고
##                          URL 도 https://<host>:8081/... 형태로 호출해야 한다.
##                참고: 접속 host/port 자체를 다른 대상으로 바꾸려면(포트 매핑) --connect-to 사용.
##  information : input none / output 호출 결과
######################################################################################################
h_curl_resolve()
{
  local host port ip url extra
  check_cmd_exist "curl" || { pause_enter; return 1; }
  ask_input "도메인(host) (예: api.example.com)" host ""
  ask_input "요청 포트(port) (예: 443, 8081 등 URL과 동일해야 함)" port "443"
  ask_input "치환할 실제 IP (여러개는 콤마, 예: 10.0.0.10 또는 10.0.0.10,10.0.0.11)" ip ""
  ask_input "요청 URL (포트 포함, 예: https://${host}:${port}/healthz)" url "https://${host}:${port}/"
  [ -z "${host}" ] && return 1
  [ -z "${ip}" ] && return 1
  ask_input "추가 옵션(선택)" extra "-sk -v"
  # --resolve HOST:PORT:ADDRESS[,ADDRESS...] 형식
  run_cmd "curl ${extra} --resolve ${host}:${port}:${ip} ${url}"
  pause_enter
}

######################################################################################################
##  Function Name : h_curl_connect_to
##  Description : --connect-to 로 접속 대상 host/port 를 다른 host/port 로 바꿔 호출한다.
##                문법: --connect-to <HOST1>:<PORT1>:<HOST2>:<PORT2>
##                  - HOST1:PORT1 : 요청 URL 상의 원래 대상(빈 값이면 요청 그대로 매칭)
##                  - HOST2:PORT2 : 실제로 접속할 대상 host/port
##                용도: 도메인(SNI/Host 헤더)은 유지하면서 다른 IP나 "다른 포트"(예: 8081)로
##                      우회 접속할 때 사용. (--resolve 는 포트 변경이 아니라 이름->IP 치환)
##                요구사항3: host:port:ip:port 형태로 접속하고 싶을 때는 이 옵션이 정확하다.
##  information : input none / output 호출 결과
######################################################################################################
h_curl_connect_to()
{
  local host1 port1 host2 port2 url extra
  check_cmd_exist "curl" || { pause_enter; return 1; }
  ask_input "요청 도메인(HOST1) (예: api.example.com)" host1 ""
  ask_input "요청 포트(PORT1) (URL의 포트, 예: 443)" port1 "443"
  ask_input "실제 접속 host/IP(HOST2) (예: 10.0.0.10)" host2 ""
  ask_input "실제 접속 포트(PORT2) (예: 8081)" port2 ""
  ask_input "요청 URL (예: https://${host1}:${port1}/healthz)" url "https://${host1}:${port1}/"
  [ -z "${host1}" ] && return 1
  [ -z "${host2}" ] && return 1
  [ -z "${port2}" ] && return 1
  ask_input "추가 옵션(선택)" extra "-sk -v"
  # --connect-to HOST1:PORT1:HOST2:PORT2 형식
  run_cmd "curl ${extra} --connect-to ${host1}:${port1}:${host2}:${port2} ${url}"
  pause_enter
}

######################################################################################################
##  Function Name : h_ncat
##  Description : ncat/nc 로 특정 호스트:포트 연결 및 패킷을 확인한다.
##  information : input none / output 연결 결과
######################################################################################################
h_ncat()
{
  local host port mode ncbin
  if command -v ncat >/dev/null 2>&1; then
    ncbin="ncat"
  elif command -v nc >/dev/null 2>&1; then
    ncbin="nc"
  else
    printf "${C_BOLD}  ncat/nc 를 찾을 수 없습니다.${C_RESET}\n"; pause_enter; return 1
  fi

  ask_input "대상 호스트 (예: 10.0.0.10)" host ""
  ask_input "포트" port ""
  [ -z "${host}" ] && return 1
  [ -z "${port}" ] && return 1
  echo ""
  printf "  ${C_BOLD}모드: [1] 포트 오픈 확인(-z -v)  [2] 배너/응답 확인(대화형)${C_RESET}\n"
  printf "  ${C_BOLD}선택: ${C_RESET}"
  read -r mode
  if [ "${mode}" = "2" ]; then
    run_cmd "${ncbin} -v ${host} ${port}"
  else
    run_cmd "${ncbin} -z -v -w 3 ${host} ${port}"
  fi
  pause_enter
}

######################################################################################################
##  Function Name : h_ping
##  Description : ICMP 도달성을 확인한다. (ping)
##  information : input none / output ping 결과
######################################################################################################
h_ping()
{
  local host cnt
  check_cmd_exist "ping" || { pause_enter; return 1; }
  ask_input "대상 호스트/IP" host ""
  [ -z "${host}" ] && return 1
  ask_input "횟수(count)" cnt "4"
  run_cmd "ping -c ${cnt} ${host}"
  pause_enter
}

######################################################################################################
##  Function Name : h_ss
##  Description : 리스닝 포트/연결 상태를 조회한다. (ss)
##  information : input none / output 소켓 상태
######################################################################################################
h_ss()
{
  local filter
  if ! command -v ss >/dev/null 2>&1; then
    # ss 가 없으면 netstat 로 대체
    check_cmd_exist "netstat" || { pause_enter; return 1; }
    run_cmd "netstat -tlnp"
    pause_enter
    return 0
  fi
  ask_input "필터(선택, 예: sport = :443 / state established)" filter ""
  if [ -n "${filter}" ]; then
    run_cmd "ss -tlnp state all '${filter}'"
  else
    run_cmd "ss -tlnp"
  fi
  pause_enter
}

######################################################################################################
##  Function Name : h_tcpdump
##  Description : tcpdump 로 패킷을 캡처한다. 인터페이스/호스트/포트 필터와 캡처 개수를 지정한다.
##                루트 권한이 필요하므로 sudo 를 사용하며, 실행 전 확인(confirm)을 거친다.
##                기본은 화면 출력(-c 개수 제한). 파일 저장(-w)도 선택 가능.
##  information : input none / output 캡처 결과 또는 저장 파일 경로
######################################################################################################
h_tcpdump()
{
  local tdbin iface host port cnt extra filter save wfile
  # tcpdump 존재 확인
  if ! command -v tcpdump >/dev/null 2>&1; then
    printf "${C_BOLD}  tcpdump 를 찾을 수 없습니다. 설치가 필요합니다. (예: dnf install -y tcpdump)${C_RESET}\n"
    pause_enter
    return 1
  fi
  tdbin="tcpdump"

  # 인터페이스 선택: NIC 목록에서 선택하거나 any/직접입력
  echo ""
  printf "  ${C_BOLD}인터페이스: [1] 목록에서 선택  [2] any(전체)  [3] 직접 입력${C_RESET}\n"
  printf "  ${C_BOLD}선택: ${C_RESET}"
  local ich
  read -r ich
  case "${ich}" in
    2) iface="any" ;;
    3) ask_input "인터페이스명 (예: eth0, ens192)" iface "any" ;;
    *)
      if select_nic iface; then :; else iface="any"; fi
      ;;
  esac
  [ -z "${iface}" ] && iface="any"

  # 필터 구성 (host/port) - BPF 표현식으로 조립
  ask_input "대상 host/IP 필터(선택, 예: 10.0.0.10)" host ""
  ask_input "포트 필터(선택, 예: 443 또는 8081)" port ""
  filter=""
  if [ -n "${host}" ]; then
    filter="host ${host}"
  fi
  if [ -n "${port}" ]; then
    if [ -n "${filter}" ]; then
      filter="${filter} and port ${port}"
    else
      filter="port ${port}"
    fi
  fi

  # 캡처 개수 및 추가 옵션
  ask_input "캡처할 패킷 개수(-c, 무제한은 0)" cnt "20"
  # -n: 이름 해석 생략, -nn: 포트도 숫자로. -vv 상세. 필요 시 사용자가 조정 가능.
  ask_input "추가 옵션(선택, 예: -nn -vv -s0)" extra "-nn -vv"

  # -c 0 은 무제한을 의미하도록 처리 (tcpdump 는 -c 0 을 즉시 종료로 해석하므로 옵션 제외)
  local cnt_opt=""
  if [ -n "${cnt}" ] && [ "${cnt}" != "0" ]; then
    cnt_opt="-c ${cnt}"
  fi

  # 파일 저장 여부
  echo ""
  printf "  ${C_BOLD}결과 저장: [1] 화면 출력(기본)  [2] pcap 파일로 저장(-w)${C_RESET}\n"
  printf "  ${C_BOLD}선택: ${C_RESET}"
  read -r save
  wfile=""
  if [ "${save}" = "2" ]; then
    ask_input "저장할 파일 경로" wfile "$HOME/tmp/tcpdump_$(date +%Y%m%d_%H%M%S).pcap"
  fi

  # 실행문 조립 (루트 권한 필요 -> sudo)
  local cmd="sudo ${tdbin} -i ${iface} ${extra} ${cnt_opt}"
  if [ -n "${wfile}" ]; then
    cmd="${cmd} -w ${wfile}"
  fi
  if [ -n "${filter}" ]; then
    cmd="${cmd} '${filter}'"
  fi

  # 위험/장시간 실행 가능성 -> confirm. (무제한 캡처는 Ctrl+C 로 중단)
  if [ -z "${cnt_opt}" ]; then
    printf "${C_BOLD}  참고: 패킷 개수 무제한입니다. 중단하려면 Ctrl+C 를 누르세요.${C_RESET}\n"
  fi
  run_cmd "${cmd}" "Y"

  if [ -n "${wfile}" ]; then
    echo ""
    printf "${C_BOLD}  저장 완료(있는 경우): %s${C_RESET}\n" "${wfile}"
    printf "  ${C_BOLD}저장 파일 분석 예: tcpdump -nn -r %s${C_RESET}\n" "${wfile}"
  fi
  pause_enter
}

# --------------------------------------------------------------------------------------------------
# [유형7] 시스템/네트워크 핸들러 (chrony / NIC)
# --------------------------------------------------------------------------------------------------

######################################################################################################
##  Function Name : h_chrony_sources
##  Description : chrony 시간 동기화 소스를 조회한다. (chronyc sources)
##  information : input none / output 소스 목록
######################################################################################################
h_chrony_sources()
{
  check_cmd_exist "chronyc" || { pause_enter; return 1; }
  run_cmd "chronyc sources -v"
  pause_enter
}

######################################################################################################
##  Function Name : h_chrony_tracking
##  Description : chrony 동기화 상태(오프셋 등)를 조회한다. (chronyc tracking)
##  information : input none / output 동기화 상태
######################################################################################################
h_chrony_tracking()
{
  check_cmd_exist "chronyc" || { pause_enter; return 1; }
  run_cmd "chronyc tracking"
  pause_enter
}

######################################################################################################
##  Function Name : select_nic
##  Description : 시스템의 네트워크 인터페이스 목록을 메뉴로 제공하거나 직접 입력받는다.
##  information : input $1=결과변수명 / output 0=선택완료, 1=취소
######################################################################################################
select_nic()
{
  local __resultvar="$1"
  local names picked

  if command -v ip >/dev/null 2>&1; then
    names=$(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -v '^lo$')
  fi

  if [ -z "${names}" ]; then
    ask_input "NIC 이름 입력 (예: eth0, ens192)" picked ""
    [ -z "${picked}" ] && return 1
    eval "${__resultvar}=\"\${picked}\""
    return 0
  fi

  RENDER_ITEMS=()
  local nm
  while IFS= read -r nm; do
    [ -n "${nm}" ] && RENDER_ITEMS+=( "${nm}" )
  done <<< "${names}"

  local idx
  select_from_list "NIC 선택" idx
  [ $? -ne 0 ] && return 1
  eval "${__resultvar}=\"\${RENDER_ITEMS[${idx}]}\""
  return 0
}

######################################################################################################
##  Function Name : h_nic_info
##  Description : NIC 정보를 조회한다. (ip -br addr + nmcli 요약)
##  information : input none / output NIC 정보
######################################################################################################
h_nic_info()
{
  check_cmd_exist "ip" || { pause_enter; return 1; }
  if command -v nmcli >/dev/null 2>&1; then
    run_cmd "ip -br addr; echo '---- nmcli ----'; nmcli device status"
  else
    run_cmd "ip -br addr"
  fi
  pause_enter
}

######################################################################################################
##  Function Name : h_nic_up
##  Description : NIC 를 활성화(UP)한다. - 상태 변경이므로 confirm.
##  information : input none / output 결과
######################################################################################################
h_nic_up()
{
  local nic
  check_cmd_exist "ip" || { pause_enter; return 1; }
  select_nic nic
  [ $? -ne 0 ] && return 1
  run_cmd "sudo ip link set ${nic} up" "Y"
  pause_enter
}

######################################################################################################
##  Function Name : h_nic_down
##  Description : NIC 를 비활성화(DOWN)한다. - 원격 접속 차단 위험이 있으므로 confirm.
##  information : input none / output 결과
######################################################################################################
h_nic_down()
{
  local nic
  check_cmd_exist "ip" || { pause_enter; return 1; }
  select_nic nic
  [ $? -ne 0 ] && return 1
  printf "${C_BOLD}  주의: 원격 접속 중인 인터페이스를 DOWN 하면 세션이 끊길 수 있습니다.${C_RESET}\n"
  run_cmd "sudo ip link set ${nic} down" "Y"
  pause_enter
}

######################################################################################################
##  Function Name : h_route
##  Description : 라우팅 테이블을 조회한다. (ip route)
##  information : input none / output 라우팅 테이블
######################################################################################################
h_route()
{
  check_cmd_exist "ip" || { pause_enter; return 1; }
  run_cmd "ip route"
  pause_enter
}

# --------------------------------------------------------------------------------------------------
# 메뉴 네비게이션 (유형 선택 -> 세부 명령 선택 -> handler 실행)
# --------------------------------------------------------------------------------------------------

######################################################################################################
##  Function Name : show_command_submenu
##  Description : 선택된 유형(catid)의 세부 명령어 목록을 표시하고, 선택 시 handler 를 실행한다.
##                요구사항8: CMD_META[cmd_id|handler] 를 eval 로 호출 (함수 포인터 방식, depth 2).
##  information : input $1=catid / output 없음 (루프)
######################################################################################################
show_command_submenu()
{
  local catid="$1"
  # 유형별 cmd_id 목록을 배열로 분리 (공백 구분 문자열 -> 배열)
  local -a cmd_ids
  read -r -a cmd_ids <<< "${CMDLIST[${catid}]}"

  while true; do
    # 표시 항목(RENDER_ITEMS) 구성 : 라벨 사용
    RENDER_ITEMS=()
    local cid
    for cid in "${cmd_ids[@]}"; do
      RENDER_ITEMS+=( "${CMD_META[${cid}|label]}" )
    done

    local idx
    select_from_list "${CAT_LABEL[${catid}]}" idx
    local rc=$?
    case ${rc} in
      2) do_exit ;;              # q : 종료
      1) return 0 ;;             # b : 유형 메뉴로 복귀
      0)
        local sel_id="${cmd_ids[${idx}]}"
        local handler="${CMD_META[${sel_id}|handler]}"
        local desc="${CMD_META[${sel_id}|desc]}"

        # 실행 전 설명 표시 (학습 지원)
        print_title "${CAT_LABEL[${catid}]} > ${CMD_META[${sel_id}|label]}"
        if [ -n "${desc}" ]; then
          printf "  ${C_BOLD}설명: %s${C_RESET}\n" "${desc}"
        fi

        # handler 문자열(함수명 + 인자)을 그대로 eval 호출
        eval "${handler}"
        ;;
    esac
  done
}

######################################################################################################
##  Function Name : show_main_menu
##  Description : 명령어 유형(Category) 목록을 표시하고 세부 메뉴로 진입한다.
##  information : input none / output 없음 (메인 루프)
######################################################################################################
show_main_menu()
{
  while true; do
    # 표시 항목(RENDER_ITEMS) 구성 : 유형 라벨 + 세부 명령 개수
    RENDER_ITEMS=()
    local cat
    for cat in "${CAT_IDS[@]}"; do
      local -a tmp_ids
      read -r -a tmp_ids <<< "${CMDLIST[${cat}]}"
      RENDER_ITEMS+=( "$(printf '%s (%d개)' "${CAT_LABEL[${cat}]}" "${#tmp_ids[@]}")" )
    done

    local idx
    select_from_list "ocptools - OCP/Podman/Network 운영 명령어 도구" idx
    local rc=$?
    case ${rc} in
      2) do_exit ;;              # q : 종료
      1) do_exit ;;              # b : 최상위에서 뒤로가기는 종료로 처리
      0)
        local sel_cat="${CAT_IDS[${idx}]}"
        show_command_submenu "${sel_cat}"
        ;;
    esac
  done
}

######################################################################################################
##  Function Name : do_exit
##  Description : 프로그램을 정상 종료한다. (메타 폴더는 EXIT trap 의 cleanup_meta 가 정리)
##  information : input none / output none (exit)
######################################################################################################
do_exit()
{
  clear
  echo "ocptools 를 종료합니다. 수고하셨습니다."
  exit 0
}

######################################################################################################
##  Function Name : preflight_check
##  Description : 시작 시 주요 도구 설치 여부를 점검하여 안내한다. (차단하지 않고 경고만)
##  information : input none / output 경고 메시지
######################################################################################################
preflight_check()
{
  local missing=""
  for c in oc podman curl; do
    command -v "${c}" >/dev/null 2>&1 || missing="${missing} ${c}"
  done
  if [ -n "${missing}" ]; then
    printf "${C_BOLD}  [참고] 다음 도구가 설치되어 있지 않습니다:%s${C_RESET}\n" "${missing}"
    printf "${C_BOLD}         관련 메뉴 사용 시 설치가 필요합니다.${C_RESET}\n"
    echo ""
    sleep 1
  fi
}
# --------------------------------------------------------------------------------------------------
# [추가] Pod 이미지 정보 조회
# --------------------------------------------------------------------------------------------------

######################################################################################################
##  Function Name : h_pod_images
##  Description : Pod 의 컨테이너 이름/이미지/imageID 목록을 조회한다.
##  information : input none / output 이미지 정보 (NS 선택: 전체/특정)
######################################################################################################
h_pod_images()
{
  local ns_opt=""
  check_oc_login || { pause_enter; return 1; }
  select_namespace ns_opt
  [ $? -ne 0 ] && return 1

  # 컨테이너/이미지/imageID 를 보기 좋게 출력 (initContainer 포함)
  run_cmd "oc get pod ${ns_opt} -o jsonpath='{range .items[*]}{.metadata.namespace}{\"/\"}{.metadata.name}{\"\\n\"}{range .spec.containers[*]}{\"  container: \"}{.name}{\" image: \"}{.image}{\"\\n\"}{end}{range .status.containerStatuses[*]}{\"  imageID: \"}{.imageID}{\"\\n\"}{end}{\"\\n\"}{end}'"
  pause_enter
}

# --------------------------------------------------------------------------------------------------
# [추가] OCP 인증서 조회 (만료일/상세)
# --------------------------------------------------------------------------------------------------

######################################################################################################
##  Function Name : h_cert_all
##  Description : 모든 namespace 의 kubernetes.io/tls Secret 인증서 만료일을 목록으로 조회한다.
##                (참고: Red Hat 권장 one-liner 를 재구성. openssl/base64 필요)
##  information : input none / output NAMESPACE/NAME/EXPIRY 표
######################################################################################################
h_cert_all()
{
  check_oc_login || { pause_enter; return 1; }
  check_cmd_exist "openssl" || { pause_enter; return 1; }

  # tls.crt 를 base64 디코드하여 enddate 추출
  local cmd
  cmd="echo -e 'NAMESPACE\\tNAME\\tEXPIRY' && oc get secrets -A -o go-template='{{range .items}}{{if eq .type \"kubernetes.io/tls\"}}{{.metadata.namespace}}{{\" \"}}{{.metadata.name}}{{\" \"}}{{index .data \"tls.crt\"}}{{\"\\n\"}}{{end}}{{end}}' | while read ns name cert; do echo -en \"\$ns\\t\$name\\t\"; echo \"\$cert\" | base64 -d 2>/dev/null | openssl x509 -noout -enddate 2>/dev/null; done | column -t"
  run_cmd "${cmd}"
  pause_enter
}

######################################################################################################
##  Function Name : h_cert_secret
##  Description : 특정 Secret 의 인증서 상세/만료일을 조회한다.
##  information : input none / output openssl x509 결과
######################################################################################################
h_cert_secret()
{
  local ns_opt="" ns secret key mode
  check_oc_login || { pause_enter; return 1; }
  check_cmd_exist "openssl" || { pause_enter; return 1; }

  select_namespace ns_opt
  [ $? -ne 0 ] && return 1
  ns=$(echo "${ns_opt}" | sed 's/^-n //')
  [ "${ns_opt}" = "-A" ] && { echo "  특정 namespace를 선택해야 합니다."; pause_enter; return 1; }

  select_oc_resource "secret" secret "-n ${ns}"
  [ $? -ne 0 ] && return 1

  ask_input "인증서 키 이름 (예: tls.crt, ca.crt)" key "tls.crt"
  # jsonpath 에서 '.' 이스케이프
  local key_esc
  key_esc=$(echo "${key}" | sed 's/\./\\./g')

  echo ""
  printf "  ${C_CYAN}출력: [1] 만료일만(enddate)  [2] 전체 상세(text)${C_RESET}\n"
  printf "  ${C_WHITE}선택: ${C_RESET}"
  read -r mode
  if [ "${mode}" = "2" ]; then
    run_cmd "oc get secret ${secret} -n ${ns} -o jsonpath='{.data.${key_esc}}' | base64 -d | openssl x509 -inform PEM -text -noout"
  else
    run_cmd "oc get secret ${secret} -n ${ns} -o jsonpath='{.data.${key_esc}}' | base64 -d | openssl x509 -inform PEM -noout -enddate"
  fi
  pause_enter
}

######################################################################################################
##  Function Name : h_cert_node
##  Description : 노드 kubelet 인증서(client/serving) 만료일을 조회한다. (oc debug node)
##  information : input none / output openssl enddate
######################################################################################################
h_cert_node()
{
  local node=""
  check_oc_login || { pause_enter; return 1; }
  select_oc_resource "node" node ""
  [ $? -ne 0 ] && return 1

  # 노드의 kubelet 인증서 경로에서 enddate 추출
  local inner='for f in /var/lib/kubelet/pki/kubelet-client-current.pem /var/lib/kubelet/pki/kubelet-server-current.pem; do echo "== $f =="; openssl x509 -in "$f" -noout -enddate 2>/dev/null; done'
  run_cmd "oc debug node/${node} -q -- chroot /host /bin/bash -c '${inner}'"
  pause_enter
}

######################################################################################################
##  Function Name : h_cert_apiurl
##  Description : URL(host:port)에 접속하여 서버 인증서 만료일을 확인한다. (openssl s_client)
##  information : input none / output 인증서 subject/issuer/enddate
######################################################################################################
h_cert_apiurl()
{
  local hostport
  check_cmd_exist "openssl" || { pause_enter; return 1; }
  ask_input "대상 host:port (예: api.cluster.example.com:6443)" hostport ""
  [ -z "${hostport}" ] && return 1
  local sni
  sni=$(echo "${hostport}" | cut -d: -f1)
  run_cmd "echo | openssl s_client -connect ${hostport} -servername ${sni} 2>/dev/null | openssl x509 -noout -subject -issuer -dates"
  pause_enter
}

# --------------------------------------------------------------------------------------------------
# [추가] OCP 관리 작업 (oc adm / patch)
# --------------------------------------------------------------------------------------------------

######################################################################################################
##  Function Name : h_adm_patch
##  Description : 리소스에 patch 를 적용한다. (oc patch) - 변경 작업이므로 confirm.
##  information : input none / output patch 결과
######################################################################################################
h_adm_patch()
{
  local ns_opt="" ns rtype rname ptype pbody scope
  check_oc_login || { pause_enter; return 1; }

  ask_input "리소스 종류 (예: deployment, node, machineconfigpool)" rtype ""
  [ -z "${rtype}" ] && return 1

  echo ""
  printf "  ${C_CYAN}namespace 스코프입니까? [y] 예(NS선택)  [N] 아니오(클러스터)${C_RESET}\n"
  printf "  ${C_WHITE}선택: ${C_RESET}"
  read -r scope
  if [ "${scope}" = "y" ] || [ "${scope}" = "Y" ]; then
    select_namespace ns_opt
    [ $? -ne 0 ] && return 1
    ns=$(echo "${ns_opt}" | sed 's/^-n //')
    [ "${ns_opt}" = "-A" ] && ns_opt=""
  fi

  ask_input "리소스 이름" rname ""
  [ -z "${rname}" ] && return 1

  ask_input "patch 타입 (merge/json/strategic)" ptype "merge"
  ask_input "patch 내용 (예: '{\"spec\":{\"paused\":true}}')" pbody ""
  [ -z "${pbody}" ] && return 1

  run_cmd "oc patch ${rtype} ${rname} ${ns_opt} --type=${ptype} -p '${pbody}'" "Y"
  pause_enter
}

######################################################################################################
##  Function Name : h_adm_cordon / h_adm_uncordon / h_adm_drain
##  Description : 노드 스케줄링 제어. cordon/uncordon/drain.
######################################################################################################
h_adm_cordon()
{
  local node=""
  check_oc_login || { pause_enter; return 1; }
  select_oc_resource "node" node ""
  [ $? -ne 0 ] && return 1
  run_cmd "oc adm cordon ${node}" "Y"
  pause_enter
}

h_adm_uncordon()
{
  local node=""
  check_oc_login || { pause_enter; return 1; }
  select_oc_resource "node" node ""
  [ $? -ne 0 ] && return 1
  run_cmd "oc adm uncordon ${node}" "Y"
  pause_enter
}

h_adm_drain()
{
  local node="" opts
  check_oc_login || { pause_enter; return 1; }
  select_oc_resource "node" node ""
  [ $? -ne 0 ] && return 1
  ask_input "drain 옵션" opts "--ignore-daemonsets --delete-emptydir-data --force"
  printf "${C_RED}  주의: drain 은 노드의 Pod 를 축출합니다.${C_RESET}\n"
  run_cmd "oc adm drain ${node} ${opts}" "Y"
  pause_enter
}

######################################################################################################
##  Function Name : h_adm_top_node / h_adm_top_pod
##  Description : 리소스 사용량 조회. (oc adm top)
######################################################################################################
h_adm_top_node()
{
  check_oc_login || { pause_enter; return 1; }
  run_cmd "oc adm top node"
  pause_enter
}

h_adm_top_pod()
{
  local ns_opt=""
  check_oc_login || { pause_enter; return 1; }
  select_namespace ns_opt
  [ $? -ne 0 ] && return 1
  run_cmd "oc adm top pod ${ns_opt}"
  pause_enter
}

# --------------------------------------------------------------------------------------------------
# [추가] 노드 tcpdump (oc debug node 기반)
# --------------------------------------------------------------------------------------------------

######################################################################################################
##  Function Name : h_node_tcpdump
##  Description : 노드에서 tcpdump 로 패킷을 캡처한다. (oc debug node -> chroot /host)
##                장시간 캡처 방지를 위해 -c(개수) 제한을 받는다. confirm 후 실행.
##  information : input none / output 캡처 결과
######################################################################################################
h_node_tcpdump()
{
  local node="" iface host port cnt filter
  check_oc_login || { pause_enter; return 1; }
  select_oc_resource "node" node ""
  [ $? -ne 0 ] && return 1

  ask_input "인터페이스 (예: any, ens192)" iface "any"
  ask_input "host 필터(선택, 예: 10.0.0.10)" host ""
  ask_input "port 필터(선택, 예: 443)" port ""
  ask_input "캡처 패킷 개수(-c)" cnt "20"

  filter=""
  [ -n "${host}" ] && filter="host ${host}"
  if [ -n "${port}" ]; then
    if [ -n "${filter}" ]; then filter="${filter} and port ${port}"; else filter="port ${port}"; fi
  fi

  local inner="tcpdump -i ${iface} -nn -c ${cnt}"
  [ -n "${filter}" ] && inner="${inner} '${filter}'"

  run_cmd "oc debug node/${node} -q -- chroot /host /bin/bash -c \"${inner}\"" "Y"
  pause_enter
}

# --------------------------------------------------------------------------------------------------
# [추가] 테스트 이미지 (busybox / nginx / toolbox)
#   - 임시 테스트 Pod 를 생성하여 네트워크/DNS/HTTP 테스트를 수행한다.
#   - 생성 리소스는 라벨(app=ocptools-test)로 관리하여 일괄 정리할 수 있다.
# --------------------------------------------------------------------------------------------------
TEST_LABEL="app=ocptools-test"

######################################################################################################
##  Function Name : h_test_busybox
##  Description : busybox 임시 Pod 로 네트워크/DNS 테스트를 수행한다.
##  information : input none / output 테스트 결과
######################################################################################################
h_test_busybox()
{
  local ns target
  check_oc_login || { pause_enter; return 1; }
  ask_input "테스트 실행 namespace" ns "default"
  ask_input "테스트 대상(host 또는 host:port)" target "kubernetes.default.svc"

  echo ""
  print_info "busybox 임시 Pod 로 일회성 명령을 실행합니다. (--rm, 종료 시 자동 삭제)"
  # nslookup + wget 로 DNS/HTTP 확인. --restart=Never, --rm 로 일회성 실행.
  run_cmd "oc run ocptools-busybox --namespace=${ns} --image=busybox:latest --restart=Never --rm -it --labels='${TEST_LABEL}' -- sh -c 'echo [nslookup]; nslookup ${target}; echo [wget]; wget -qO- --timeout=5 http://${target} 2>/dev/null | head -20 || echo (HTTP 응답 없음/비HTTP)'"
  pause_enter
}

######################################################################################################
##  Function Name : h_test_nginx
##  Description : nginx 임시 Pod 를 배포하고 curl 로 응답을 확인한다.
##  information : input none / output 배포/테스트 결과
######################################################################################################
h_test_nginx()
{
  local ns
  check_oc_login || { pause_enter; return 1; }
  ask_input "테스트 실행 namespace" ns "default"

  echo ""
  print_info "nginx 임시 Pod 를 배포합니다. (라벨: ${TEST_LABEL})"
  run_cmd "oc run ocptools-nginx --namespace=${ns} --image=nginx:latest --restart=Never --labels='${TEST_LABEL}' --port=80"
  echo ""
  print_info "Pod Ready 대기 후 내부에서 curl 로 자기 자신에 접속 테스트합니다."
  run_cmd "oc wait --for=condition=Ready pod/ocptools-nginx -n ${ns} --timeout=60s && oc exec -n ${ns} pod/ocptools-nginx -- curl -s -o /dev/null -w 'HTTP:%{http_code}\\n' http://localhost:80"
  echo ""
  print_info "정리는 [테스트 리소스 정리] 메뉴 또는 아래 명령으로 수행하세요."
  show_exec_cmd "oc delete pod -l ${TEST_LABEL} -n ${ns}"
  pause_enter
}

######################################################################################################
##  Function Name : h_test_toolbox
##  Description : 노드에서 toolbox 로 진단 도구를 사용하는 방법을 안내/실행한다.
##                toolbox 는 RHCOS 노드에서 진단용 컨테이너(support-tools)를 띄우는 도구이다.
##  information : input none / output 안내 및 실행문
######################################################################################################
h_test_toolbox()
{
  local node="" tcmd
  check_oc_login || { pause_enter; return 1; }
  print_info "toolbox 는 RHCOS 노드에서 진단 도구가 포함된 support-tools 컨테이너를 실행합니다."
  select_oc_resource "node" node ""
  [ $? -ne 0 ] && return 1
  ask_input "toolbox 내부에서 실행할 명령 (예: sos report, tcpdump -D)" tcmd "cat /etc/redhat-release"
  # oc debug node -> chroot /host -> toolbox <cmd>
  run_cmd "oc debug node/${node} -q -- chroot /host /bin/bash -c \"toolbox ${tcmd}\""
  pause_enter
}

######################################################################################################
##  Function Name : h_test_cleanup
##  Description : 생성한 테스트 Pod(라벨 기반)를 삭제한다. confirm 후 실행.
##  information : input none / output 삭제 결과
######################################################################################################
h_test_cleanup()
{
  local ns_opt=""
  check_oc_login || { pause_enter; return 1; }
  select_namespace ns_opt
  [ $? -ne 0 ] && return 1
  run_cmd "oc delete pod -l ${TEST_LABEL} ${ns_opt}" "Y"
  pause_enter
}

# --------------------------------------------------------------------------------------------------
# [추가] Istio 서비스메시 (istioctl)
# --------------------------------------------------------------------------------------------------

######################################################################################################
##  Function Name : h_istio_version
##  Description : istioctl 및 컨트롤플레인 버전을 조회한다.
##  information : input none / output 버전 정보
######################################################################################################
h_istio_version()
{
  check_cmd_exist "istioctl" || { pause_enter; return 1; }
  run_cmd "istioctl version"
  pause_enter
}

######################################################################################################
##  Function Name : h_istio_proxy_status
##  Description : sidecar proxy 동기화 상태를 조회한다. (istioctl proxy-status)
##  information : input none / output proxy-status
######################################################################################################
h_istio_proxy_status()
{
  check_cmd_exist "istioctl" || { pause_enter; return 1; }
  check_oc_login || { pause_enter; return 1; }
  run_cmd "istioctl proxy-status"
  pause_enter
}

######################################################################################################
##  Function Name : h_istio_proxy_config
##  Description : 특정 Pod 의 Envoy proxy 설정을 조회한다. (istioctl proxy-config)
##  information : input none / output proxy-config
######################################################################################################
h_istio_proxy_config()
{
  local ns_opt="" ns pod sub
  check_cmd_exist "istioctl" || { pause_enter; return 1; }
  check_oc_login || { pause_enter; return 1; }

  select_namespace ns_opt
  [ $? -ne 0 ] && return 1
  ns=$(echo "${ns_opt}" | sed 's/^-n //')
  [ "${ns_opt}" = "-A" ] && { echo "  proxy-config 는 특정 namespace를 선택해야 합니다."; pause_enter; return 1; }

  select_oc_resource "pod" pod "-n ${ns}"
  [ $? -ne 0 ] && return 1

  ask_input "조회 대상 (all/cluster/listener/route/endpoint/bootstrap/secret)" sub "all"
  run_cmd "istioctl proxy-config ${sub} ${pod}.${ns}"
  pause_enter
}

######################################################################################################
##  Function Name : h_istio_analyze
##  Description : Istio 구성 문제를 분석한다. (istioctl analyze)
##  information : input none / output analyze 결과
######################################################################################################
h_istio_analyze()
{
  local ns_opt=""
  check_cmd_exist "istioctl" || { pause_enter; return 1; }
  check_oc_login || { pause_enter; return 1; }
  select_namespace ns_opt
  [ $? -ne 0 ] && return 1
  # -A 이면 --all-namespaces 로 변환
  if [ "${ns_opt}" = "-A" ]; then
    run_cmd "istioctl analyze --all-namespaces"
  else
    run_cmd "istioctl analyze ${ns_opt}"
  fi
  pause_enter
}

######################################################################################################
##  Function Name : h_istio_free
##  Description : 임의의 istioctl 하위 명령을 직접 입력하여 실행한다. (학습/확장)
##  information : input none / output 실행 결과
######################################################################################################
h_istio_free()
{
  local sub
  check_cmd_exist "istioctl" || { pause_enter; return 1; }
  ask_input "istioctl 하위 명령 입력 (예: dashboard kiali, experimental describe pod X)" sub ""
  [ -z "${sub}" ] && return 1
  run_cmd "istioctl ${sub}"
  pause_enter
}

# --------------------------------------------------------------------------------------------------
# [추가] 유틸리티 (crt merge / json merge / openssl)
# --------------------------------------------------------------------------------------------------

######################################################################################################
##  Function Name : h_util_crt_configmap
##  Description : 복수의 crt(PEM) 파일을 하나로 merge 하여 CA bundle ConfigMap 을 생성하거나
##                기존 ConfigMap 을 patch 한다. (예: user-ca-bundle, trusted CA 등)
##  information : input none / output ConfigMap 생성 또는 patch 결과
######################################################################################################
h_util_crt_configmap()
{
  local files ns_opt ns cmname key mode merged
  check_oc_login || { pause_enter; return 1; }

  # 1) merge 할 crt 파일들 입력 (공백 구분, glob 허용)
  ask_input "merge 할 crt 파일들 (공백 구분, 예: a.crt b.crt 또는 /path/*.crt)" files ""
  [ -z "${files}" ] && return 1

  # 파일 존재 확인 및 병합 (임시 파일 사용)
  merged=$(mktemp 2>/dev/null || echo "/tmp/ocptools_ca_$$.pem")
  : > "${merged}"
  local f found=0
  for f in ${files}; do
    if [ -f "${f}" ]; then
      cat "${f}" >> "${merged}"
      echo "" >> "${merged}"   # 인증서 사이 개행 보장
      found=$((found+1))
    else
      print_warn "파일 없음(건너뜀): ${f}"
    fi
  done
  if [ ${found} -eq 0 ]; then
    print_error "merge 할 유효한 crt 파일이 없습니다."
    rm -f "${merged}"; pause_enter; return 1
  fi
  print_info "총 ${found}개 crt 파일을 병합했습니다: ${merged}"

  # 2) 대상 namespace / ConfigMap 이름 / key
  select_namespace ns_opt
  if [ $? -ne 0 ] || [ "${ns_opt}" = "-A" ]; then
    print_error "특정 namespace를 선택해야 합니다."
    rm -f "${merged}"; pause_enter; return 1
  fi
  ns=$(echo "${ns_opt}" | sed 's/^-n //')

  ask_input "ConfigMap 이름" cmname "user-ca-bundle"
  ask_input "데이터 key (파일명)" key "ca-bundle.crt"

  # 3) 생성 또는 patch 선택
  echo ""
  printf "  ${C_BOLD}적용 방식: [1] 신규 생성(create)  [2] 기존 갱신(create --dry-run | apply)  [3] 실행문만 보기${C_RESET}\n"
  printf "  ${C_BOLD}선택: ${C_RESET}"
  read -r mode

  local base_cmd="oc create configmap ${cmname} -n ${ns} --from-file=${key}=${merged}"
  case "${mode}" in
    2)
      # create --dry-run -o yaml | oc apply (있으면 갱신, 없으면 생성)
      run_cmd "oc create configmap ${cmname} -n ${ns} --from-file=${key}=${merged} --dry-run=client -o yaml | oc apply -f -" "Y"
      ;;
    3)
      show_exec_cmd "${base_cmd}"
      echo "  (갱신형)  ${base_cmd} --dry-run=client -o yaml | oc apply -f -"
      ;;
    *)
      run_cmd "${base_cmd}" "Y"
      ;;
  esac

  # 임시 병합 파일 정리
  rm -f "${merged}"
  pause_enter
}

######################################################################################################
##  Function Name : h_util_json_merge
##  Description : 복수의 JSON 파일을 하나의 merged JSON 으로 병합한다. (jq)
##                병합 방식: [1] 객체 깊은 병합(뒤 파일 우선), [2] 배열로 결합, [3] 얕은 병합.
##  information : input none / output merged JSON 파일 저장
######################################################################################################
h_util_json_merge()
{
  local files out mode f found=0
  check_cmd_exist "jq" || { pause_enter; return 1; }

  ask_input "merge 할 JSON 파일들 (공백 구분, 예: a.json b.json 또는 /path/*.json)" files ""
  [ -z "${files}" ] && return 1
  ask_input "출력 파일 경로" out "./merged.json"

  # 유효 파일 확인
  local valid_files=""
  for f in ${files}; do
    if [ -f "${f}" ] && jq -e . "${f}" >/dev/null 2>&1; then
      valid_files="${valid_files} ${f}"
      found=$((found+1))
    else
      print_warn "JSON 파일 아님/없음(건너뜀): ${f}"
    fi
  done
  if [ ${found} -eq 0 ]; then
    print_error "merge 할 유효한 JSON 파일이 없습니다."
    pause_enter; return 1
  fi

  echo ""
  printf "  ${C_BOLD}병합 방식: [1] 객체 깊은 병합(뒤 파일 우선)  [2] 배열로 결합  [3] 얕은 병합(+)${C_RESET}\n"
  printf "  ${C_BOLD}선택: ${C_RESET}"
  read -r mode

  case "${mode}" in
    2)
      # 각 파일을 배열 요소로 결합
      run_cmd "jq -s '.' ${valid_files} > ${out}"
      ;;
    3)
      # 얕은 병합: reduce with +
      run_cmd "jq -s 'reduce .[] as \$x ({}; . + \$x)' ${valid_files} > ${out}"
      ;;
    *)
      # 깊은 병합: reduce with * (뒤 파일이 우선)
      run_cmd "jq -s 'reduce .[] as \$x ({}; . * \$x)' ${valid_files} > ${out}"
      ;;
  esac

  if [ -f "${out}" ]; then
    print_ok "병합 완료: ${out}"
    echo "  미리보기(상위):"
    jq . "${out}" 2>/dev/null | head -20
  fi
  pause_enter
}

######################################################################################################
##  Function Name : h_util_openssl
##  Description : openssl 대표 사용법을 메뉴로 제공하고 실행한다. (학습형)
##                각 항목은 실행문을 보여주어 직접 사용법을 익히도록 한다.
##  information : input none / output openssl 실행 결과
######################################################################################################
h_util_openssl()
{
  check_cmd_exist "openssl" || { pause_enter; return 1; }

  RENDER_ITEMS=(
    "인증서 상세 보기 (x509 -text)"
    "인증서 만료일 (x509 -noout -enddate)"
    "인증서 subject/issuer (x509 -noout -subject -issuer)"
    "원격 서버 인증서 (s_client -connect)"
    "CSR 생성 (req -new)"
    "자체서명 인증서 생성 (req -x509)"
    "PFX/P12 -> PEM 변환 (pkcs12)"
    "인증서 지문 (x509 -fingerprint -sha256)"
    "개인키/인증서 modulus 일치 확인"
  )
  local idx
  select_from_list "openssl 사용법 선택" idx
  [ $? -ne 0 ] && return 1

  local f hostport out days
  case ${idx} in
    0)
      ask_input "인증서 파일 경로" f ""
      [ -z "${f}" ] && return 1
      run_cmd "openssl x509 -in ${f} -text -noout"
      ;;
    1)
      ask_input "인증서 파일 경로" f ""
      [ -z "${f}" ] && return 1
      run_cmd "openssl x509 -in ${f} -noout -enddate"
      ;;
    2)
      ask_input "인증서 파일 경로" f ""
      [ -z "${f}" ] && return 1
      run_cmd "openssl x509 -in ${f} -noout -subject -issuer"
      ;;
    3)
      ask_input "대상 host:port (예: api.example.com:6443)" hostport ""
      [ -z "${hostport}" ] && return 1
      local sni; sni=$(echo "${hostport}" | cut -d: -f1)
      run_cmd "echo | openssl s_client -connect ${hostport} -servername ${sni} 2>/dev/null | openssl x509 -noout -subject -issuer -dates"
      ;;
    4)
      ask_input "생성할 key 파일" f "server.key"
      ask_input "생성할 CSR 파일" out "server.csr"
      run_cmd "openssl req -new -newkey rsa:2048 -nodes -keyout ${f} -out ${out}"
      ;;
    5)
      ask_input "생성할 key 파일" f "selfsigned.key"
      ask_input "생성할 crt 파일" out "selfsigned.crt"
      ask_input "유효기간(일)" days "365"
      run_cmd "openssl req -x509 -newkey rsa:2048 -nodes -keyout ${f} -out ${out} -days ${days}"
      ;;
    6)
      ask_input "PFX/P12 파일" f ""
      ask_input "출력 PEM 파일" out "output.pem"
      [ -z "${f}" ] && return 1
      run_cmd "openssl pkcs12 -in ${f} -out ${out} -nodes"
      ;;
    7)
      ask_input "인증서 파일 경로" f ""
      [ -z "${f}" ] && return 1
      run_cmd "openssl x509 -in ${f} -noout -fingerprint -sha256"
      ;;
    8)
      ask_input "인증서(crt) 파일" f ""
      ask_input "개인키(key) 파일" out ""
      [ -z "${f}" ] && return 1
      [ -z "${out}" ] && return 1
      # modulus 해시가 같으면 짝이 맞음
      run_cmd "echo -n 'crt md5 : '; openssl x509 -noout -modulus -in ${f} | openssl md5; echo -n 'key md5 : '; openssl rsa -noout -modulus -in ${out} | openssl md5"
      ;;
    *) return 1 ;;
  esac
  pause_enter
}

# ======<<<< Function Registration Area (End) >>>>=================================================

# ======<<<< Main Logic Coding Area (Start) >>>>===================================================
# 1) 성능용 메타 폴더 생성 (종료 시 EXIT trap 의 cleanup_meta 가 삭제)
init_meta

# 2) 명령어 메타데이터 등록 (유형/세부명령)
register_all_commands

# 3) 시작 배너
print_title "ocptools - OCP / Podman / Network 운영 학습형 CLI"
echo "  이 도구는 실제 실행되는 명령어(실행문)를 함께 보여주어,"
echo "  명령어와 파라미터를 자연스럽게 익히도록 돕습니다."
echo ""
echo "  - 유형을 선택한 뒤 세부 명령을 고르면 실행문과 결과가 출력됩니다."
echo "  - 리소스(node/pod 등)는 목록에서 선택하거나 직접 입력할 수 있습니다."
echo "  - 삭제/NIC 변경 등 위험 명령은 실행 전 확인을 거칩니다."
echo ""
preflight_check
pause_enter

# 4) 메인 메뉴 진입
show_main_menu
# ======<<<< Main Logic Coding Area (End) >>>>=====================================================
