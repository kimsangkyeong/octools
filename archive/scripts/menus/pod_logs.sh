#!/bin/bash
#
# Pod 로그 조회
# 선택된 Pod의 최근 로그를 출력한다.
#
# 사용: ./pod_logs.sh <namespace> [output_mode] [pod_name]
#   $1 = namespace (필수)
#   $2 = output_mode (color|plain, 기본: color)
#   $3 = pod_name (필수, CLI/API에서 전달)
#
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

check_oc_env

NS="${1:-__ALL__}"
MODE="${2:-color}"
POD_NAME="${3}"

# namespace 필수 확인
if [ "$NS" = "__ALL__" ] || [ "$NS" = "__NONE__" ]; then
    print_error "Pod 로그 조회는 특정 Namespace를 선택해야 합니다."
    exit 1
fi

# Pod 이름 필수 확인
if [ -z "$POD_NAME" ]; then
    print_error "Pod 이름이 지정되지 않았습니다."
    exit 1
fi

NS_OPT=$(build_ns_option "$NS")

# 컨테이너가 여러 개인 경우 모든 컨테이너 로그 출력
CONTAINERS=$(oc get pod "$POD_NAME" $NS_OPT -o jsonpath='{.spec.containers[*].name}' 2>/dev/null)

if [ -z "$CONTAINERS" ]; then
    print_error "Pod '$POD_NAME'을 찾을 수 없습니다."
    exit 1
fi

CONTAINER_COUNT=$(echo "$CONTAINERS" | wc -w)

if [ "$CONTAINER_COUNT" -eq 1 ]; then
    # 단일 컨테이너
    if [ "$MODE" = "plain" ]; then
        echo "[HEADER]===== Pod: $POD_NAME | Container: $CONTAINERS ====="
        oc logs "$POD_NAME" $NS_OPT --tail=100 2>&1
    else
        print_section "Pod: $POD_NAME | Container: $CONTAINERS" "$MODE"
        oc logs "$POD_NAME" $NS_OPT --tail=100 2>&1
    fi
else
    # 다중 컨테이너 - 각각 출력
    for container in $CONTAINERS; do
        if [ "$MODE" = "plain" ]; then
            echo "[HEADER]===== Pod: $POD_NAME | Container: $container ====="
            oc logs "$POD_NAME" -c "$container" $NS_OPT --tail=50 2>&1
            echo ""
        else
            print_section "Pod: $POD_NAME | Container: $container" "$MODE"
            oc logs "$POD_NAME" -c "$container" $NS_OPT --tail=50 2>&1
            echo ""
        fi
    done
fi

exit 0
