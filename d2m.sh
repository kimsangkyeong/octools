#!/bin/bash
####################################################################################################
##
## File name   : d2m.sh
## Description : oc-mirror plugin v2 (--v2) 를 사용하여 m2d.sh 로 다운로드해 둔 디스크 파일을
##               private registry 로 저장(disk-to-mirror)하는 래퍼 스크립트.
##               ImageSetConfiguration YAML, 디스크 경로, 대상 저장소(repository)를 지정하여 실행하며,
##               실행 전 조회/실행 정보를 Information 으로 출력한다.
## Information : - 실행 형식(disk to mirror):
##                   oc-mirror --config <imageset.yaml> --from file://<disk_path> \
##                             docker://<REGISTRY_HOST>/<repo> --v2 --cache-dir <CACHE_DIR>
##               - CACHE_DIR 은 내부 변수로 정의(기본 /data/ocp-file-mirror/cache).
##               - private registry 저장소(repo)는 내부 변수 목록(REPO_LIST)으로 관리하며,
##                 목록에서 선택하거나 인자로 직접 입력할 수 있다. 목록에 없는 값은 오류 처리 후
##                 선택 가능한 목록을 안내한다.
##               - 인증은 oc-mirror v2 가 참조하는 ${XDG_RUNTIME_DIR}/containers/auth.json 을 사용한다.
##                 실행 시 XDG_RUNTIME_DIR 을 실행 user 기준(/run/user/<uid>)으로 세팅하여
##                 XDG_RUNTIME_DIR 초기화로 인증 정보를 잃는 문제를 근본적으로 방지한다.
##               - REGISTRY_AUTH_FILE 이 설정되어 있으면 오류가 날 수 있어, 해당 명령 실행 환경에서만
##                 unset 하여 실행한다(전역 환경 미변경).
##               - 인자 없이 실행하면 -h(도움말)와 동일하게 사용법을 출력한다.
##               - signal 처리 로그는 $HOME/tmp 아래에 저장.
##
##==================================================================================================
##  version   date             author          reason
##--------------------------------------------------------------------------------------------------
##  1.0       2026.08.16       k.s.k & kiro     First Created
##  1.1       2026.08.16       k.s.k & kiro     REPO_LIST 저장소명 오타 수정(relese -> release)
##  1.2       2026.08.16       k.s.k & kiro     불필요한 --skip-signature 옵션 제거
##                                              (서명 포함/skip 은 다운로드 단계 m2d 에서 결정)
##  1.3       2026.08.16       k.s.k & kiro     인증 방식 개선: --authfile 강제 전달 대신
##                                              XDG_RUNTIME_DIR 을 실행 user 기준(/run/user/uid)으로
##                                              세팅하여 인증 유실 근본 방지. --authfile 은 선택 옵션.
##  1.4       2026.08.16       k.s.k & kiro     --authfile 옵션 완전 제거(XDG_RUNTIME_DIR 방식으로 일원화),
##                                              인증 파일 부재 안내 메시지 수정
##  1.5       2026.09.07       k.s.k & kiro     (1) 정상 완료 후 cluster-resources 후처리 추가:
##                                                  - release 등: signature-configmap.yaml 을 .origin 백업 후
##                                                    name 값에 -<disk_path 마지막 폴더명> 접미사(버전별 유니크)
##                                                  - additionalimages-nosignature 인자: itms*.yaml 을 .origin
##                                                    백업 후 name 값에 -nosignature 접미사
##                                                  (itms-*/idms-* 중복 허용분, Operator catalog index 는 미처리)
##                                              (2) 화면 출력을 C_BOLD 로 통일(색상 정의는 유지, 가독성 문제 회피)
##                                              (3) 누락된 print_warn 헬퍼 추가
##
####################################################################################################

# ======<<<< Signal common processing logic (Start) >>>>=============================================
logdatefmt="%Y%m%d-%H:%M:%S"
logdir="${HOME}/tmp"
[ -d "${logdir}" ] || mkdir -p "${logdir}" 2>/dev/null
logfnm="${logdir}/$(basename "$0").log"

trap ' echo "$(date +${logdatefmt}) $0 signal(SIGINT ) captured" | tee -a "${logfnm}"; exit 1;' SIGINT
trap ' echo "$(date +${logdatefmt}) $0 signal(SIGQUIT) captured" | tee -a "${logfnm}"; exit 1;' SIGQUIT
trap ' echo "$(date +${logdatefmt}) $0 signal(SIGTERM) captured" | tee -a "${logfnm}"; exit 1;' SIGTERM
# ======<<<< Signal common processing logic (End) >>>>===============================================

# ======<<<< Important Global Variable Registration Area (Start) >>>>================================
# 색상 코드
C_RED='\033[0;91m'  ; C_GREEN='\033[0;92m' ; C_YELLOW='\033[0;93m'
C_CYAN='\033[0;96m' ; C_WHITE='\033[0;97m' ; C_BOLD='\033[1m' ; C_RESET='\033[0m'

# oc-mirror 캐시 디렉토리 (요구사항3/5: 내부 변수, 기본값 지정)
CACHE_DIR="/data/ocp-file-mirror/cache"

# private registry 주소 (요구사항3)
REGISTRY_HOST="ocprgst.bss.skt:5000"

# private registry 저장소(repository) 목록 (요구사항4: 내부 변수 목록으로 관리, 확장 용이)
# 저장소 확대/변경 시 이 배열만 수정하면 된다.
REPO_LIST=(
  "ocp4/release"
  "ocp4/olm"
  "ocp4/infra"
)

# private registry 인증:
# oc-mirror v2 는 내부적으로 ${XDG_RUNTIME_DIR}/containers/auth.json 을 참조하므로,
# 실행 시 XDG_RUNTIME_DIR 을 실행 user 기준으로 세팅하여 인증을 인식하게 한다.
# 표준값: /run/user/<uid>  (root 는 /run/user/0)
XDG_RUNTIME_DIR_FIXED="/run/user/$(id -u 2>/dev/null)"

# 도구 이름 (Information 출력용)
TOOL_NAME="d2m.sh"

# 인자로 채워질 변수
CONFIG_FILE=""      # ImageSetConfiguration YAML 경로
DISK_PATH=""        # disk-to-mirror 원본(디스크) 경로
REPO=""             # 대상 저장소(repository) 경로 (예: ocp4/release)
# ======<<<< Important Global Variable Registration Area (End) >>>>==================================

# ======<<<< Function Registration Area (Start) >>>>================================================

######################################################################################################
##  Function Name : print_repo_list
##  Description : 선택 가능한 private registry 저장소 목록을 번호와 함께 출력한다.
##  information : input none / output 저장소 목록
######################################################################################################
print_repo_list()
{
  local i=1 r
  echo "  선택 가능한 저장소 목록:"
  for r in "${REPO_LIST[@]}"; do
    printf "    [%d] %s/%s\n" "${i}" "${REGISTRY_HOST}" "${r}"
    i=$(( i + 1 ))
  done
}

######################################################################################################
##  Function Name : print_usage
##  Description : 사용법(도움말)을 출력한다. 인자 없이 실행하거나 -h/--help 시 호출된다.
##  information : input none / output 사용법 문자열
######################################################################################################
print_usage()
{
  cat <<EOF
${TOOL_NAME} - oc-mirror v2 를 이용한 disk-to-mirror(디스크 -> private registry) 도구

[사용법]
  ${TOOL_NAME} <imagesetconfig_yaml> <disk_path> [repo] [옵션]

[인자]
  imagesetconfig_yaml   ImageSetConfiguration 이 정의된 YAML 파일 경로 (필수)
  disk_path             m2d 로 내려받은 디스크 경로 (필수, file:// 자동 부여)
  repo                  대상 private registry 저장소 (선택)
                        - 생략하면 목록에서 번호로 선택
                        - 직접 입력 시 아래 관리 목록에 있는 값이어야 함

$(print_repo_list)

[옵션]
  -h, --help            이 도움말을 출력한다.

[내부 설정]
  REGISTRY_HOST         ${REGISTRY_HOST}
  CACHE_DIR             ${CACHE_DIR}
  XDG_RUNTIME_DIR       ${XDG_RUNTIME_DIR_FIXED}  (실행 user 기준으로 세팅하여 전달)
  인증 파일             \${XDG_RUNTIME_DIR}/containers/auth.json

[예시]
  # 저장소를 목록에서 선택 (repo 생략)
  ${TOOL_NAME} ./imagesetconfig-release-4.22.10 ./relase-4.22.10

  # 저장소를 직접 지정
  ${TOOL_NAME} ./imagesetconfig-release-4.22.10 ./relase-4.22.10 ocp4/release

[참고]
  - 대상 이미지는 docker://${REGISTRY_HOST}/<repo> 로 전송됩니다.
  - oc-mirror v2 는 내부적으로 \${XDG_RUNTIME_DIR}/containers/auth.json 을 참조합니다.
    이 도구는 실행 시 XDG_RUNTIME_DIR 을 실행 user 기준(/run/user/<uid>)으로 세팅하여
    XDG_RUNTIME_DIR 초기화로 인한 인증 오류를 근본적으로 방지합니다.
  - 사전에 'podman login ${REGISTRY_HOST}' 등으로 위 경로에 인증 token 이 저장되어 있어야 합니다.
  - 실행 시 REGISTRY_AUTH_FILE 환경변수는 이 명령 실행 환경에서만 unset 됩니다.
EOF
}

######################################################################################################
##  Function Name : print_error / print_info / print_ok
##  Description : 메시지 출력 헬퍼.
######################################################################################################
## 화면 출력은 색상이 안 보이는 문제 회피를 위해 C_BOLD 로 통일한다.
## (색상 코드 정의는 유지하되, 필요 시 수동으로 색상으로 되돌릴 수 있도록 함)
print_error() { printf "${C_BOLD}[ERROR] %s${C_RESET}\n" "$1" >&2; }
print_info()  { printf "${C_BOLD}%s${C_RESET}\n" "$1"; }
print_ok()    { printf "${C_BOLD}%s${C_RESET}\n" "$1"; }
print_warn()  { printf "${C_BOLD}[WARN] %s${C_RESET}\n" "$1" >&2; }

######################################################################################################
##  Function Name : is_valid_repo
##  Description : 입력한 저장소(repo)가 관리 목록(REPO_LIST)에 있는지 확인한다.
##  information : input $1=repo / output 0=유효, 1=미관리
######################################################################################################
is_valid_repo()
{
  local target="$1" r
  for r in "${REPO_LIST[@]}"; do
    [ "${r}" = "${target}" ] && return 0
  done
  return 1
}

######################################################################################################
##  Function Name : select_repo_interactive
##  Description : 저장소를 번호로 선택하도록 안내하고 선택 결과를 전역 REPO 에 저장한다.
##  information : input none / output 0=선택완료(REPO 설정), 1=취소
######################################################################################################
select_repo_interactive()
{
  echo ""
  print_info "저장할 private registry 저장소를 선택하세요."
  print_repo_list
  echo ""
  printf "  ${C_BOLD}번호 선택 (취소: q): ${C_RESET}"
  local sel
  read -r sel || return 1
  case "${sel}" in
    q|Q) return 1 ;;
    ''|*[!0-9]*)
      print_error "숫자를 입력하세요."
      return 1
      ;;
    *)
      if [ "${sel}" -ge 1 ] && [ "${sel}" -le "${#REPO_LIST[@]}" ]; then
        REPO="${REPO_LIST[$(( sel - 1 ))]}"
        return 0
      fi
      print_error "유효하지 않은 번호입니다. (1~${#REPO_LIST[@]})"
      return 1
      ;;
  esac
}

######################################################################################################
##  Function Name : parse_args
##  Description : 명령행 인자를 파싱한다. (위치 인자 yaml, disk, [repo] + 옵션)
##  information : input "$@" / output 전역변수 설정, 비정상 시 usage 출력 후 종료
######################################################################################################
parse_args()
{
  # 인자 없이 실행하면 -h 와 동일 (요구사항7)
  if [ "$#" -eq 0 ]; then
    print_usage
    exit 0
  fi

  local positional=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -h|--help)
        print_usage
        exit 0
        ;;
      -*)
        print_error "알 수 없는 옵션: $1"
        echo ""
        print_usage
        exit 1
        ;;
      *)
        positional+=( "$1" )
        shift
        ;;
    esac
  done

  # 필수 위치 인자(yaml, disk) 검증
  if [ "${#positional[@]}" -lt 2 ]; then
    print_error "인자가 부족합니다. (imagesetconfig_yaml, disk_path 필요)"
    echo ""
    print_usage
    exit 1
  fi

  CONFIG_FILE="${positional[0]}"
  DISK_PATH="${positional[1]}"
  # 3번째 위치 인자(repo)는 선택
  if [ "${#positional[@]}" -ge 3 ]; then
    REPO="${positional[2]}"
  fi
}

######################################################################################################
##  Function Name : resolve_repo
##  Description : 저장소(repo)를 확정한다. 인자로 받았으면 유효성 검사, 없으면 목록 선택.
##  information : input none / output 0=확정(REPO 설정), 1=실패
######################################################################################################
resolve_repo()
{
  if [ -n "${REPO}" ]; then
    # 인자로 직접 지정 -> 관리 목록에 있는지 검증 (요구사항4)
    if is_valid_repo "${REPO}"; then
      return 0
    fi
    print_error "관리되지 않는 저장소입니다: ${REPO}"
    echo ""
    print_repo_list
    return 1
  fi

  # 인자 없음 -> 목록에서 선택
  select_repo_interactive
  return $?
}

######################################################################################################
##  Function Name : validate_env
##  Description : 실행 전 필수 조건(oc-mirror, config, disk, cache, 인증)을 점검한다.
##                인증은 XDG_RUNTIME_DIR/containers/auth.json 존재를 확인한다(경고 수준).
##  information : input none / output 0=정상, 1=실패
######################################################################################################
validate_env()
{
  if ! command -v oc-mirror >/dev/null 2>&1; then
    print_error "oc-mirror 명령을 찾을 수 없습니다. 설치 및 PATH를 확인하세요."
    return 1
  fi
  if [ ! -f "${CONFIG_FILE}" ]; then
    print_error "ImageSetConfiguration YAML 파일이 없습니다: ${CONFIG_FILE}"
    return 1
  fi
  if [ ! -d "${DISK_PATH}" ]; then
    print_error "디스크 경로가 존재하지 않습니다: ${DISK_PATH}"
    return 1
  fi

  # 인증 점검: XDG_RUNTIME_DIR/containers/auth.json 존재 확인 (없으면 경고 후 진행)
  local auth_path="${XDG_RUNTIME_DIR_FIXED}/containers/auth.json"
  if [ ! -f "${auth_path}" ]; then
    print_warn "인증 파일이 없습니다: ${auth_path}"
    print_info "먼저 'podman login ${REGISTRY_HOST}' 로 로그인하거나, 인증서파일을 \"${auth_path}\" 로 복사하세요."
    # 인증 실패는 oc-mirror 가 최종 판단하므로 여기서는 경고만 하고 진행한다.
  fi

  if [ ! -d "${CACHE_DIR}" ]; then
    if ! mkdir -p "${CACHE_DIR}" 2>/dev/null; then
      print_error "캐시 디렉토리를 생성할 수 없습니다: ${CACHE_DIR}"
      return 1
    fi
  fi
  return 0
}

######################################################################################################
##  Function Name : build_command
##  Description : 실제 실행할 oc-mirror disk-to-mirror 명령 문자열을 조립한다.
##                인증은 XDG_RUNTIME_DIR/containers/auth.json 을 참조하므로 별도 인자를 넣지 않는다.
##  information : input $1=결과변수명 / output 조립된 명령 문자열 저장
######################################################################################################
build_command()
{
  local __resultvar="$1"

  local cmd
  cmd="oc-mirror --config ${CONFIG_FILE} --from file://${DISK_PATH} docker://${REGISTRY_HOST}/${REPO} --v2 --cache-dir ${CACHE_DIR}"
  eval "${__resultvar}=\"\${cmd}\""
}

######################################################################################################
##  Function Name : print_information
##  Description : oc-mirror 실행 전에 정보를 출력한다. (요구사항6)
##                - oc-mirror 버전, 도구 이름, 실행 명령어 전체
##  information : input $1=실행할 명령 문자열 / output Information 블록
######################################################################################################
print_information()
{
  local run_cmd="$1"
  local ocm_ver
  ocm_ver=$(oc-mirror version 2>/dev/null | head -3 | tr '\n' ' ')
  [ -z "${ocm_ver}" ] && ocm_ver="(버전 조회 실패)"

  echo ""
  printf "${C_BOLD}==================== [Information] ====================${C_RESET}\n"
  printf "  %-18s : %s\n" "도구 이름" "${TOOL_NAME}"
  printf "  %-18s : %s\n" "oc-mirror 버전" "${ocm_ver}"
  printf "  %-18s : %s\n" "config(yaml)" "${CONFIG_FILE}"
  printf "  %-18s : %s\n" "disk 경로(from)" "${DISK_PATH}"
  printf "  %-18s : %s\n" "대상 registry" "docker://${REGISTRY_HOST}/${REPO}"
  printf "  %-18s : %s\n" "cache 경로" "${CACHE_DIR}"
  printf "  %-18s : %s\n" "XDG_RUNTIME_DIR" "${XDG_RUNTIME_DIR_FIXED} (실행 환경에 세팅)"
  printf "  %-18s : %s\n" "인증(auth.json)" "${XDG_RUNTIME_DIR_FIXED}/containers/auth.json"
  printf "  %-18s : %s\n" "REGISTRY_AUTH_FILE" "이 명령 실행 환경에서 unset 처리"
  printf "  %-18s : %s\n" "실행 명령어" ""
  printf "${C_BOLD}    %s${C_RESET}\n" "${run_cmd}"
  printf "${C_BOLD}======================================================${C_RESET}\n"
  echo ""
}

######################################################################################################
##  Function Name : run_mirror
##  Description : oc-mirror 를 실행한다. 이때 해당 실행 환경에만 다음을 적용한다(전역 환경 미변경).
##                - XDG_RUNTIME_DIR 을 실행 user 기준(/run/user/<uid>)으로 명시 세팅
##                  -> oc-mirror v2 가 참조하는 ${XDG_RUNTIME_DIR}/containers/auth.json 인증 유실 방지
##                - REGISTRY_AUTH_FILE 은 unset (설정 시 oc-mirror 오류 유발 가능)
##  information : input $1=실행할 명령 문자열 / output oc-mirror 실행 결과, 종료코드 반환
######################################################################################################
run_mirror()
{
  local run_cmd="$1"
  # env 로 해당 프로세스 환경에만 XDG_RUNTIME_DIR 세팅 + REGISTRY_AUTH_FILE 제거하여 실행.
  # (현재/부모 셸 환경은 변경되지 않음)
  if command -v env >/dev/null 2>&1; then
    env -u REGISTRY_AUTH_FILE "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR_FIXED}" bash -c "${run_cmd}"
  else
    ( unset REGISTRY_AUTH_FILE; export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR_FIXED}"; eval "${run_cmd}" )
  fi
  return $?
}

######################################################################################################
##  Function Name : rewrite_yaml_name_suffix
##  Description : 지정한 YAML 파일의 첫 번째 metadata.name 값 뒤에 접미사(suffix)를 붙인다.
##                수정 전 원본을 <파일>.origin 으로 백업하며, 이미 .origin 백업이 있으면
##                (재실행으로 간주) 건너뛴다(중복 append 방지).
##                metadata: 블록 아래의 첫 번째 "name:" 만 변경한다.
##  information : input $1=yaml 파일 경로, $2=붙일 접미사 / output 0=처리(또는 스킵), 1=오류
######################################################################################################
rewrite_yaml_name_suffix()
{
  local yaml_file="$1"
  local suffix="$2"
  local backup="${yaml_file}.origin"

  [ -f "${yaml_file}" ] || { print_warn "대상 파일이 없어 건너뜁니다: ${yaml_file}"; return 0; }

  # 이미 백업이 존재하면 이전에 처리한 것으로 간주하여 재처리하지 않는다(중복 append 방지).
  if [ -f "${backup}" ]; then
    print_warn "이미 처리됨(백업 존재): ${backup} -> 재처리 건너뜀"
    return 0
  fi

  # 원본 백업
  if ! cp -p "${yaml_file}" "${backup}" 2>/dev/null; then
    print_error "백업 생성 실패: ${backup}"
    return 1
  fi

  # metadata: 블록 아래 첫 번째 name: 값에만 접미사를 붙인다.
  # in_meta: metadata: 진입 여부, done: 이미 한 번 수정했는지 여부
  if ! awk -v sfx="${suffix}" '
    BEGIN { in_meta=0; done=0 }
    {
      if (done==0 && $0 ~ /^[[:space:]]*metadata:[[:space:]]*$/) { in_meta=1; print; next }
      if (done==0 && in_meta==1 && $0 ~ /^[[:space:]]*name:[[:space:]]*/) {
        # 앞쪽 들여쓰기 + "name:" 뒤 공백을 보존하고, 값 뒤에 접미사를 붙인다.
        # 값에 감싸는 따옴표가 있을 수 있으나 release/itms 케이스는 평문 name 이므로 단순 치환.
        line=$0
        # name: 이후의 값 부분만 추출
        head=line
        sub(/name:[[:space:]]*.*/, "", head)          # 들여쓰기(name: 앞) 보존
        val=line
        sub(/^[[:space:]]*name:[[:space:]]*/, "", val) # 값만 추출
        printf "%sname: %s%s\n", head, val, sfx
        done=1
        in_meta=0
        next
      }
      print
    }
  ' "${backup}" > "${yaml_file}"; then
    print_error "name 수정 실패: ${yaml_file} (백업에서 복구하세요: ${backup})"
    return 1
  fi

  print_ok "수정 완료: ${yaml_file} (name 에 '${suffix}' 접미사 추가, 백업: ${backup})"
  return 0
}

######################################################################################################
##  Function Name : post_process_cluster_resources
##  Description : oc-mirror 정상 완료 후, <disk_path>/working-dir/cluster-resources 아래
##                생성된 YAML 의 name 중복 방지 후처리를 수행한다.
##                - disk_path 의 마지막 폴더명이 "additionalimages-nosignature" 인 경우(개별 이미지):
##                    itms*.yaml 을 itms*.yaml.origin 으로 백업 후 name 에 "-nosignature" 접미사 부여.
##                - 그 외(release 등):
##                    signature-configmap.yaml 을 .origin 으로 백업 후 name 에
##                    "-<disk_path 마지막 폴더명>" 접미사 부여(버전별 유니크 처리).
##                  (itms-*/idms-* 는 중복 허용이므로 손대지 않음. Operator 는 catalog index 처리로 조치 불필요)
##  information : input none(전역 DISK_PATH 사용) / output 0=완료(부분 스킵 포함), 1=오류
######################################################################################################
post_process_cluster_resources()
{
  # 마지막 폴더명 추출 (trailing slash 제거 후 basename)
  local disk_norm last_dir cr_dir
  disk_norm="${DISK_PATH%/}"
  last_dir="$(basename "${disk_norm}")"
  cr_dir="${disk_norm}/working-dir/cluster-resources"

  if [ ! -d "${cr_dir}" ]; then
    print_warn "cluster-resources 디렉토리가 없어 후처리를 건너뜁니다: ${cr_dir}"
    return 0
  fi

  echo ""
  print_info "cluster-resources 후처리를 시작합니다: ${cr_dir}"

  local rc=0

  if [ "${last_dir}" = "additionalimages-nosignature" ]; then
    # 개별 이미지(무서명) 케이스: itms*.yaml 에 -nosignature 접미사
    local f matched=0
    for f in "${cr_dir}"/itms*.yaml; do
      [ -e "${f}" ] || continue
      matched=1
      rewrite_yaml_name_suffix "${f}" "-nosignature" || rc=1
    done
    [ "${matched}" -eq 0 ] && print_warn "itms*.yaml 파일을 찾지 못했습니다: ${cr_dir}"
  else
    # release 등 일반 케이스: signature-configmap.yaml 에 -<마지막폴더명> 접미사
    local sig="${cr_dir}/signature-configmap.yaml"
    rewrite_yaml_name_suffix "${sig}" "-${last_dir}" || rc=1
  fi

  return ${rc}
}

# ======<<<< Function Registration Area (End) >>>>=================================================

# ======<<<< Main Logic Coding Area (Start) >>>>===================================================
# 1) 인자 파싱 (인자 없으면 usage 출력 후 종료)
parse_args "$@"

# 2) 저장소(repo) 확정 (인자 유효성 검사 또는 목록 선택)
if ! resolve_repo; then
  exit 1
fi

# 3) 실행 전 환경 점검
if ! validate_env; then
  exit 1
fi

# 4) 실행 명령 조립
RUN_CMD=""
build_command RUN_CMD

# 5) Information 출력
print_information "${RUN_CMD}"

# 6) oc-mirror 실행 (REGISTRY_AUTH_FILE 는 실행 환경에서만 unset)
print_info "oc-mirror disk-to-mirror 를 시작합니다..."
run_mirror "${RUN_CMD}"
RC=$?

echo ""
if [ ${RC} -eq 0 ]; then
  print_ok "완료되었습니다. (registry: docker://${REGISTRY_HOST}/${REPO})"
  # 7) 정상 완료 후 cluster-resources 후처리 (name 중복 방지)
  post_process_cluster_resources || print_warn "cluster-resources 후처리 중 일부 오류가 발생했습니다. 위 메시지를 확인하세요."
else
  print_error "oc-mirror 실행이 실패했습니다. (종료코드: ${RC})"
fi
exit ${RC}
# ======<<<< Main Logic Coding Area (End) >>>>=====================================================
