#!/bin/bash
#
# OCP 관리도구 (octools) - 공통 함수 라이브러리
# 각 메뉴 스크립트에서 source 하여 사용한다.
#
# 사용법 (각 스크립트 상단에):
#   SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
#   source "${SCRIPT_DIR}/../common.sh"
#

# ─── 컬러 코드 ──────────────────────────────────────────────────────────
RED='\033[0;91m'
GREEN='\033[0;92m'
YELLOW='\033[0;93m'
BLUE='\033[0;94m'
CYAN='\033[0;96m'
BOLD='\033[1m'
NC='\033[0m'  # No Color

# ─── 출력 함수 ──────────────────────────────────────────────────────────

print_header() {
    echo -e "${BOLD}${CYAN}$1${NC}"
}

print_error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
}

print_warn() {
    echo -e "${YELLOW}[WARN] $1${NC}" >&2
}

print_info() {
    echo -e "${CYAN}[INFO] $1${NC}" >&2
}

# ─── oc 환경 확인 ─────────────────────────────────────────────────────────

# oc 명령어 존재 확인
check_oc() {
    if ! command -v oc &> /dev/null; then
        print_error "oc 명령어를 찾을 수 없습니다. PATH를 확인하세요."
        exit 1
    fi
}

# oc 로그인 상태 확인
check_oc_login() {
    if ! oc whoami &> /dev/null; then
        print_error "oc 로그인이 되어 있지 않습니다. 'oc login'을 실행하세요."
        exit 1
    fi
}

# oc 환경 전체 확인 (oc 존재 + 로그인)
check_oc_env() {
    check_oc
    check_oc_login
}

# ─── Namespace 처리 ───────────────────────────────────────────────────────

# namespace 옵션 생성
# 사용: NS_OPT=$(build_ns_option "$1")
#       oc get pod $NS_OPT
#
# $1 값에 따른 동작:
#   빈값/"__ALL__" → "-A" (전체)
#   namespace명    → "-n <namespace>"
#   없음(unset)    → "" (옵션 없음, namespace 불필요 메뉴용)
build_ns_option() {
    local ns="$1"
    if [ -z "$ns" ] || [ "$ns" = "__ALL__" ]; then
        echo "-A"
    elif [ "$ns" = "__NONE__" ]; then
        echo ""
    else
        echo "-n $ns"
    fi
}

# Namespace 목록 조회 (서브메뉴용)
get_namespace_list() {
    oc get ns -o custom-columns=NAME:.metadata.name --no-headers 2>/dev/null | sort
}

# ─── 출력 파이프라인 ──────────────────────────────────────────────────────

# 비정상 라인을 빨간색으로 강조하는 필터
# stdin으로 oc 명령어 출력을 받아서 비정상 라인을 빨간색으로 출력
# 사용: oc get pod -A | highlight_abnormal
#
# 비정상 키워드: CrashLoopBackOff, Error, ImagePullBackOff, Pending,
#               Terminating, NotReady, Unknown, Failed, Evicted, OOMKilled,
#               DEGRADED, SchedulingDisabled
highlight_abnormal() {
    local first_line=1
    while IFS= read -r line; do
        if [ $first_line -eq 1 ]; then
            # 헤더 라인 - 볼드 시안
            echo -e "${BOLD}${CYAN}${line}${NC}"
            first_line=0
        elif echo "$line" | grep -qiE "(CrashLoopBackOff|ImagePullBackOff|ErrImagePull|Error|OOMKilled|Pending|Terminating|NotReady|Unknown|Failed|Evicted|DEGRADED|SchedulingDisabled|ContainerStatusUnknown)"; then
            # 비정상 라인 - 빨강
            echo -e "${RED}${line}${NC}"
        else
            # 정상 라인
            echo "$line"
        fi
    done
}

# 동일 기능이지만 컬러 없이 마킹만 (API 서버용)
# abnormal 라인 앞에 [ABNORMAL] 태그 추가
mark_abnormal() {
    local first_line=1
    while IFS= read -r line; do
        if [ $first_line -eq 1 ]; then
            echo "[HEADER]${line}"
            first_line=0
        elif echo "$line" | grep -qiE "(CrashLoopBackOff|ImagePullBackOff|ErrImagePull|Error|OOMKilled|Pending|Terminating|NotReady|Unknown|Failed|Evicted|DEGRADED|SchedulingDisabled|ContainerStatusUnknown)"; then
            echo "[ABNORMAL]${line}"
        else
            echo "${line}"
        fi
    done
}

# ─── Pod 선택 ─────────────────────────────────────────────────────────────

# Pod 목록 조회 (서브메뉴용)
# 사용: pods=$(get_pod_list "$namespace")
get_pod_list() {
    local ns="$1"
    local ns_opt=$(build_ns_option "$ns")
    oc get pod $ns_opt -o custom-columns=NAME:.metadata.name --no-headers 2>/dev/null
}

# Pod 목록 조회 (이름 + 상태 포함, 선택 화면용)
# 사용: get_pod_list_with_status "$namespace"
get_pod_list_with_status() {
    local ns="$1"
    local ns_opt=$(build_ns_option "$ns")
    oc get pod $ns_opt -o custom-columns="NAME:.metadata.name,STATUS:.status.phase,READY:.status.containerStatuses[*].ready" --no-headers 2>/dev/null
}

# CLI에서 Pod 선택 인터랙티브 메뉴 (직접 호출 시 사용)
# 사용: selected_pod=$(select_pod_interactive "$namespace")
select_pod_interactive() {
    local ns="$1"
    local ns_opt=$(build_ns_option "$ns")
    local pods
    pods=$(oc get pod $ns_opt --no-headers 2>/dev/null | awk '{print $1}')

    if [ -z "$pods" ]; then
        print_error "Pod이 없습니다."
        return 1
    fi

    echo -e "${BOLD}${YELLOW}Pod를 선택하세요:${NC}" >&2
    local i=1
    while IFS= read -r pod; do
        echo -e "  [${i}] ${pod}" >&2
        i=$((i+1))
    done <<< "$pods"

    echo "" >&2
    read -p "  번호 입력: " choice

    local selected
    selected=$(echo "$pods" | sed -n "${choice}p")
    if [ -z "$selected" ]; then
        print_error "유효하지 않은 번호입니다."
        return 1
    fi

    echo "$selected"
}

# ─── 섹션 구분 출력 ───────────────────────────────────────────────────────

# 여러 리소스를 구분하여 출력할 때 사용하는 섹션 헤더
# 사용: print_section "Pods" "$mode"
print_section() {
    local title="$1"
    local mode="${2:-color}"
    if [ "$mode" = "plain" ]; then
        echo ""
        echo "[HEADER]===== ${title} ====="
    else
        echo ""
        echo -e "${BOLD}${BLUE}===== ${title} =====${NC}"
    fi
}

# ─── 스크립트 인터페이스 규약 ──────────────────────────────────────────────
#
# 각 메뉴 스크립트 규약:
#   입력: $1 = namespace ("__ALL__", "__NONE__", 또는 namespace명)
#         $2 = output_mode ("color" 또는 "plain", 기본값: "color")
#         $3 = pod_name (Pod 선택이 필요한 메뉴에서 전달, 선택사항)
#   출력: stdout로 명령어 실행 결과 출력
#   종료: exit 0 = 성공, exit 1 = 실패
#
# output_mode 처리:
#   "color"  → highlight_abnormal 사용 (CLI 직접 사용 시)
#   "plain"  → mark_abnormal 사용 (API 서버 호출 시)

get_output_filter() {
    local mode="${1:-color}"
    if [ "$mode" = "plain" ]; then
        echo "mark_abnormal"
    else
        echo "highlight_abnormal"
    fi
}
