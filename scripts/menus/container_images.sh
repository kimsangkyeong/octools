#!/bin/bash
#
# 컨테이너 이미지 목록 조회
# 지정된 Namespace(또는 전체)에서 사용 중인 컨테이너 이미지 목록을 추출한다.
#
# 사용: ./container_images.sh [namespace] [output_mode]
#
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

check_oc_env

NS="${1:-__ALL__}"
MODE="${2:-color}"
NS_OPT=$(build_ns_option "$NS")

# Pod에서 사용 중인 이미지 목록 추출 (중복 제거, 정렬)
# 출력: NAMESPACE  POD_NAME  CONTAINER  IMAGE
output=$(oc get pod $NS_OPT -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\t"}{range .spec.containers[*]}{.name}{"="}{.image}{"\n"}{end}{end}' 2>&1)

rc=$?
if [ $rc -ne 0 ]; then
    echo "$output" >&2
    exit $rc
fi

if [ "$MODE" = "plain" ]; then
    echo "[HEADER]NAMESPACE                POD                              CONTAINER          IMAGE"
    echo "$output" | awk -F'\t' '
    NF>=2 {
        ns=$1; pod=$2;
        split($3, arr, "=");
        container=arr[1]; image=arr[2];
        if (container != "" && image != "") {
            printf "%-24s %-32s %-18s %s\n", ns, pod, container, image
        }
    }' | sort -k4
else
    echo -e "${BOLD}${CYAN}NAMESPACE                POD                              CONTAINER          IMAGE${NC}"
    echo "$output" | awk -F'\t' '
    NF>=2 {
        ns=$1; pod=$2;
        split($3, arr, "=");
        container=arr[1]; image=arr[2];
        if (container != "" && image != "") {
            printf "%-24s %-32s %-18s %s\n", ns, pod, container, image
        }
    }' | sort -k4
fi

# 이미지 요약 (고유 이미지 수)
echo ""
unique_count=$(echo "$output" | awk -F'=' '{print $NF}' | sort -u | grep -c .)
if [ "$MODE" = "plain" ]; then
    echo "[HEADER]===== 고유 이미지 수: ${unique_count} ====="
    echo "$output" | awk -F'=' '{print $NF}' | sort | uniq -c | sort -rn | head -20
else
    print_section "고유 이미지 수: ${unique_count} (상위 20개)" "$MODE"
    echo "$output" | awk -F'=' '{print $NF}' | sort | uniq -c | sort -rn | head -20
fi

exit 0
