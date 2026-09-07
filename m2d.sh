#!/bin/bash
####################################################################################################
##
## File name   : m2d.sh
## Description : oc-mirror plugin v2 (--v2) 를 사용하여 인터넷망의 OCP/Operator/추가 이미지를
##               로컬 디스크(mirror-to-disk)로 다운로드/저장하는 래퍼 스크립트.
##               ImageSetConfiguration YAML 과 디스크 저장 경로를 인자로 받아 실행하며,
##               실행 전 조회/실행 정보를 Information 으로 출력한다.
## Information : - 실행 형식(mirror to disk):
##                   oc-mirror --config <imageset.yaml> file://<disk_path> --v2 \
##                             --cache-dir <CACHE_DIR> [--authfile <AUTHFILE>] \
##                             [--remove-signatures=<true|false>]
##               - CACHE_DIR 은 내부 변수로 정의(기본 /data/ocp-file-mirror/cache).
##               - 인증(인터넷망 Red Hat/vendor registry pull):
##                   * --authfile 지정 시: 해당 pull secret 파일로 인증한다.
##                   * --authfile 미지정 시: XDG_RUNTIME_DIR 을 실행 user 기준(/run/user/<uid>)으로
##                     세팅하고 ${XDG_RUNTIME_DIR}/containers/auth.json 을 참조한다.
##               - REGISTRY_AUTH_FILE 이 설정되어 있으면 oc-mirror 가 오류를 낼 수 있어,
##                 해당 명령 실행 환경에서만 이 변수를 unset 하여 실행한다(전역에는 영향 없음).
##               - signature: 기본은 서명 포함 다운로드(--remove-signatures=false).
##                 --skip-signature 지정 시 서명 다운로드를 건너뛴다(--remove-signatures=true).
##                 (참고: OCP 4.21+ 는 Red Hat 이미지 서명 미러링이 기본 동작이나, 서명이 없는
##                  파트너 이미지 때문에 실패하는 경우 서명 skip 이 필요할 수 있음)
##               - 인자 없이 실행하면 -h(도움말)와 동일하게 사용법을 출력한다.
##               - signal 처리 로그는 $HOME/tmp 아래에 저장.
##
##==================================================================================================
##  version   date             author          reason
##--------------------------------------------------------------------------------------------------
##  1.0       2026.08.16       k.s.k & kiro     First Created
##  1.1       2026.08.16       k.s.k & kiro     --authfile 옵션 추가(인터넷망 pull secret 지정).
##                                              미지정 시 XDG_RUNTIME_DIR 세팅 + auth.json 참조.
##  1.2       2026.09.07       k.s.k & kiro     화면 출력을 C_BOLD 로 통일(색상 정의는 유지, 가독성 문제 회피).
##                                              필요 시 개별 printf 의 C_BOLD 를 색상 변수로 수동 변경.
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
C_CYAN='\033[0;96m' ; C_BOLD='\033[1m'     ; C_RESET='\033[0m'

# oc-mirror 캐시 디렉토리 (요구사항3: 내부 변수로 정의, 기본값 지정)
CACHE_DIR="/data/ocp-file-mirror/cache"

# XDG_RUNTIME_DIR (실행 user 기준 표준 경로). --authfile 미지정 시 이 값을 세팅하여
# ${XDG_RUNTIME_DIR}/containers/auth.json 을 인증에 사용한다. (root 는 /run/user/0)
XDG_RUNTIME_DIR_FIXED="/run/user/$(id -u 2>/dev/null)"

# 도구 이름 (Information 출력용)
TOOL_NAME="m2d.sh"

# 인자로 채워질 변수
CONFIG_FILE=""      # ImageSetConfiguration YAML 경로
DISK_PATH=""        # mirror-to-disk 저장 경로
SKIP_SIGNATURE=0    # 0=서명 포함(기본), 1=서명 skip
AUTHFILE=""         # (선택) 인터넷망 pull secret 인증 파일 경로 (--authfile)
# ======<<<< Important Global Variable Registration Area (End) >>>>==================================

# ======<<<< Function Registration Area (Start) >>>>================================================

######################################################################################################
##  Function Name : print_usage
##  Description : 사용법(도움말)을 출력한다. 인자 없이 실행하거나 -h/--help 시 호출된다.
##  information : input none / output 사용법 문자열
######################################################################################################
print_usage()
{
  cat <<EOF
${TOOL_NAME} - oc-mirror v2 를 이용한 이미지 mirror-to-disk 도구

[사용법]
  ${TOOL_NAME} <imagesetconfig_yaml> <disk_path> [옵션]

[인자]
  imagesetconfig_yaml   ImageSetConfiguration 이 정의된 YAML 파일 경로 (필수)
  disk_path             이미지를 저장할 로컬 디스크 경로 (필수, file:// 자동 부여)

[옵션]
  --authfile <path>     (선택) 인터넷망 registry pull secret 인증 파일 경로를 지정한다.
                        지정 시 oc-mirror 에 --authfile 로 전달한다.
                        미지정 시 XDG_RUNTIME_DIR 을 실행 user 기준으로 세팅하고
                        \${XDG_RUNTIME_DIR}/containers/auth.json 을 참조한다.
  --skip-signature      서명(signature) 파일 다운로드를 건너뛴다.
                        (oc-mirror 의 --remove-signatures=true 로 실행)
                        기본값은 서명 포함 다운로드(--remove-signatures=false).
  -h, --help            이 도움말을 출력한다.

[내부 설정]
  CACHE_DIR             ${CACHE_DIR}
                        (oc-mirror --cache-dir 로 전달. 스크립트 내부 변수에서 변경 가능)
  XDG_RUNTIME_DIR       ${XDG_RUNTIME_DIR_FIXED}  (--authfile 미지정 시 세팅하여 전달)
  인증 파일(기본)       \${XDG_RUNTIME_DIR}/containers/auth.json

[예시]
  # 기본 실행 (인증: XDG_RUNTIME_DIR/containers/auth.json)
  ${TOOL_NAME} ./imagesetconfig-release-4.22.10 ./relase-4.22.10

  # pull secret 파일을 직접 지정하여 실행
  ${TOOL_NAME} ./imagesetconfig-release-4.22.10 ./relase-4.22.10 --authfile /data/pullsecret/pull-secret.json

  # 서명 다운로드 skip 실행 (서명 없는 파트너 이미지 포함 시)
  ${TOOL_NAME} ./imagesetconfig-release-4.22.10 ./relase-4.22.10 --skip-signature

[참고]
  - 실행 시 REGISTRY_AUTH_FILE 환경변수는 이 명령 실행 환경에서만 unset 됩니다.
  - 인터넷 연결이 가능한 시스템에서 실행해야 합니다. (Red Hat/vendor registry pull 인증 필요)
  - pull secret 은 https://console.redhat.com/openshift/install/pull-secret 에서 받을 수 있습니다.
EOF
}

######################################################################################################
##  Function Name : print_error / print_info / print_ok
##  Description : 메시지 출력 헬퍼.
######################################################################################################
## 화면 출력은 색상이 안 보이는 문제 회피를 위해 C_BOLD 로 통일한다.
## (색상 코드 정의는 유지하되, 필요 시 수동으로 색상으로 되돌릴 수 있도록 함)
print_error() { printf "${C_BOLD}[ERROR] %s${C_RESET}\n" "$1" >&2; }
print_warn()  { printf "${C_BOLD}[WARN] %s${C_RESET}\n" "$1" >&2; }
print_info()  { printf "${C_BOLD}%s${C_RESET}\n" "$1"; }
print_ok()    { printf "${C_BOLD}%s${C_RESET}\n" "$1"; }

######################################################################################################
##  Function Name : parse_args
##  Description : 명령행 인자를 파싱한다. (위치 인자 2개 + 옵션)
##  information : input "$@" / output 전역변수 CONFIG_FILE/DISK_PATH/SKIP_SIGNATURE 설정
##                output 0=정상, 비정상 시 usage 출력 후 종료
######################################################################################################
parse_args()
{
  # 인자 없이 실행하면 -h 와 동일하게 동작 (요구사항7)
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
      --authfile)
        if [ -z "$2" ]; then
          print_error "--authfile 값이 필요합니다."
          exit 1
        fi
        AUTHFILE="$2"
        shift 2
        ;;
      --skip-signature)
        SKIP_SIGNATURE=1
        shift
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

  # 위치 인자 검증
  if [ "${#positional[@]}" -lt 2 ]; then
    print_error "인자가 부족합니다. (imagesetconfig_yaml, disk_path 필요)"
    echo ""
    print_usage
    exit 1
  fi

  CONFIG_FILE="${positional[0]}"
  DISK_PATH="${positional[1]}"
}

######################################################################################################
##  Function Name : validate_env
##  Description : 실행 전 필수 조건(oc-mirror 설치, config 파일 존재, 디스크 경로)을 점검한다.
##  information : input none / output 0=정상, 1=실패(메시지)
######################################################################################################
validate_env()
{
  # oc-mirror 설치 확인
  if ! command -v oc-mirror >/dev/null 2>&1; then
    print_error "oc-mirror 명령을 찾을 수 없습니다. 설치 및 PATH를 확인하세요."
    return 1
  fi

  # config yaml 존재 확인
  if [ ! -f "${CONFIG_FILE}" ]; then
    print_error "ImageSetConfiguration YAML 파일이 없습니다: ${CONFIG_FILE}"
    return 1
  fi

  # 디스크 경로 준비 (없으면 생성 시도)
  if [ ! -d "${DISK_PATH}" ]; then
    if ! mkdir -p "${DISK_PATH}" 2>/dev/null; then
      print_error "디스크 저장 경로를 생성할 수 없습니다: ${DISK_PATH}"
      return 1
    fi
  fi

  # 캐시 디렉토리 준비
  if [ ! -d "${CACHE_DIR}" ]; then
    if ! mkdir -p "${CACHE_DIR}" 2>/dev/null; then
      print_error "캐시 디렉토리를 생성할 수 없습니다: ${CACHE_DIR}"
      return 1
    fi
  fi

  # 인증 점검
  if [ -n "${AUTHFILE}" ]; then
    # --authfile 지정된 경우: 해당 파일 필수
    if [ ! -f "${AUTHFILE}" ]; then
      print_error "지정한 인증 파일(--authfile)이 없습니다: ${AUTHFILE}"
      return 1
    fi
  else
    # 미지정: XDG_RUNTIME_DIR/containers/auth.json 확인 (없으면 경고 후 진행)
    local auth_path="${XDG_RUNTIME_DIR_FIXED}/containers/auth.json"
    if [ ! -f "${auth_path}" ]; then
      print_warn "인증 파일이 없습니다: ${auth_path}"
      print_info "먼저 'podman login <registry>' 로 로그인하거나, --authfile 로 pull secret 경로를 지정하세요."
      # 인증 실패는 oc-mirror 가 최종 판단하므로 여기서는 경고만 하고 진행한다.
    fi
  fi

  return 0
}

######################################################################################################
##  Function Name : build_command
##  Description : 실제 실행할 oc-mirror 명령 문자열을 조립하여 반환한다.
##  information : input $1=결과변수명 / output 조립된 명령 문자열 저장
##                signature: 기본 --remove-signatures=false(포함), skip 시 true
######################################################################################################
build_command()
{
  local __resultvar="$1"
  local remove_sig="false"           # 기본: 서명 포함 (remove-signatures=false)
  [ "${SKIP_SIGNATURE}" -eq 1 ] && remove_sig="true"

  # file:// 접두어로 mirror-to-disk 대상 지정
  local cmd
  cmd="oc-mirror --config ${CONFIG_FILE} file://${DISK_PATH} --v2 --cache-dir ${CACHE_DIR}"
  # --authfile 은 지정된 경우에만 추가 (미지정 시 XDG_RUNTIME_DIR/containers/auth.json 참조)
  if [ -n "${AUTHFILE}" ]; then
    cmd="${cmd} --authfile ${AUTHFILE}"
  fi
  cmd="${cmd} --remove-signatures=${remove_sig}"
  eval "${__resultvar}=\"\${cmd}\""
}

######################################################################################################
##  Function Name : print_information
##  Description : oc-mirror 다운로드(실행) 전에 정보를 출력한다. (요구사항6)
##                - oc-mirror 버전, 도구 이름, 실행 명령어 전체
##  information : input $1=실행할 명령 문자열 / output Information 블록
######################################################################################################
print_information()
{
  local run_cmd="$1"
  local ocm_ver
  # oc-mirror 버전 조회 (실패해도 진행)
  ocm_ver=$(oc-mirror version 2>/dev/null | head -3 | tr '\n' ' ')
  [ -z "${ocm_ver}" ] && ocm_ver="(버전 조회 실패)"

  echo ""
  printf "${C_BOLD}==================== [Information] ====================${C_RESET}\n"
  printf "  %-16s : %s\n" "도구 이름" "${TOOL_NAME}"
  printf "  %-16s : %s\n" "oc-mirror 버전" "${ocm_ver}"
  printf "  %-16s : %s\n" "config(yaml)" "${CONFIG_FILE}"
  printf "  %-16s : %s\n" "disk 경로" "${DISK_PATH}"
  printf "  %-16s : %s\n" "cache 경로" "${CACHE_DIR}"
  if [ -n "${AUTHFILE}" ]; then
    printf "  %-16s : %s\n" "인증(authfile)" "${AUTHFILE} (명시 지정)"
  else
    printf "  %-16s : %s\n" "XDG_RUNTIME_DIR" "${XDG_RUNTIME_DIR_FIXED} (실행 환경에 세팅)"
    printf "  %-16s : %s\n" "인증(auth.json)" "${XDG_RUNTIME_DIR_FIXED}/containers/auth.json"
  fi
  if [ "${SKIP_SIGNATURE}" -eq 1 ]; then
    printf "  %-16s : %s\n" "signature" "skip (--remove-signatures=true)"
  else
    printf "  %-16s : %s\n" "signature" "포함 (--remove-signatures=false, 기본)"
  fi
  printf "  %-16s : %s\n" "REGISTRY_AUTH_FILE" "이 명령 실행 환경에서 unset 처리"
  printf "  %-16s : %s\n" "실행 명령어" ""
  printf "${C_BOLD}    %s${C_RESET}\n" "${run_cmd}"
  printf "${C_BOLD}======================================================${C_RESET}\n"
  echo ""
}

######################################################################################################
##  Function Name : run_mirror
##  Description : oc-mirror 를 실행한다. 이때 해당 실행 환경에만 다음을 적용한다(전역 환경 미변경).
##                - REGISTRY_AUTH_FILE 은 unset (설정 시 oc-mirror 오류 유발 가능)
##                - --authfile 미지정 시: XDG_RUNTIME_DIR 을 실행 user 기준으로 세팅하여
##                  ${XDG_RUNTIME_DIR}/containers/auth.json 인증을 인식하게 한다.
##                  (--authfile 지정 시에는 oc-mirror 가 해당 파일로 인증하므로 세팅 불필요)
##  information : input $1=실행할 명령 문자열 / output oc-mirror 실행 결과, 종료코드 반환
######################################################################################################
run_mirror()
{
  local run_cmd="$1"

  if command -v env >/dev/null 2>&1; then
    if [ -n "${AUTHFILE}" ]; then
      # --authfile 지정: REGISTRY_AUTH_FILE 만 제거하여 실행
      env -u REGISTRY_AUTH_FILE bash -c "${run_cmd}"
    else
      # 미지정: XDG_RUNTIME_DIR 세팅 + REGISTRY_AUTH_FILE 제거
      env -u REGISTRY_AUTH_FILE "XDG_RUNTIME_DIR=${XDG_RUNTIME_DIR_FIXED}" bash -c "${run_cmd}"
    fi
  else
    # env 가 없으면 서브셸에서 처리 (동일 효과, 부모 환경 미변경)
    if [ -n "${AUTHFILE}" ]; then
      ( unset REGISTRY_AUTH_FILE; eval "${run_cmd}" )
    else
      ( unset REGISTRY_AUTH_FILE; export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR_FIXED}"; eval "${run_cmd}" )
    fi
  fi
  return $?
}

# ======<<<< Function Registration Area (End) >>>>=================================================

# ======<<<< Main Logic Coding Area (Start) >>>>===================================================
# 1) 인자 파싱 (인자 없으면 usage 출력 후 종료)
parse_args "$@"

# 2) 실행 전 환경 점검
if ! validate_env; then
  exit 1
fi

# 3) 실행 명령 조립
RUN_CMD=""
build_command RUN_CMD

# 4) Information 출력 (oc-mirror 다운로드/실행 전)
print_information "${RUN_CMD}"

# 5) oc-mirror 실행 (REGISTRY_AUTH_FILE unset, --authfile 미지정 시 XDG_RUNTIME_DIR 세팅)
print_info "oc-mirror mirror-to-disk 를 시작합니다..."
run_mirror "${RUN_CMD}"
RC=$?

echo ""
if [ ${RC} -eq 0 ]; then
  print_ok "완료되었습니다. (disk: ${DISK_PATH})"
else
  print_error "oc-mirror 실행이 실패했습니다. (종료코드: ${RC})"
fi
exit ${RC}
# ======<<<< Main Logic Coding Area (End) >>>>=====================================================
