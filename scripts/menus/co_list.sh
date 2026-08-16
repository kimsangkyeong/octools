#!/bin/bash
#
# ClusterOperator 조회
# AVAILABLE=False 또는 DEGRADED=True인 항목을 비정상으로 표시
# 사용: ./co_list.sh [namespace] [output_mode]
#
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

check_oc_env

MODE="${2:-color}"

# ClusterOperator 조회 후 비정상 판별
# CO 고유 로직: AVAILABLE=False 또는 DEGRADED=True를 비정상으로 처리
output=$(oc get co 2>&1)
rc=$?

if [ $rc -ne 0 ]; then
    echo "$output" >&2
    exit $rc
fi

if [ "$MODE" = "plain" ]; then
    echo "$output" | awk 'NR==1 {print "[HEADER]"$0; next}
        /False.*True/ || /False/ && !/True.*False/ {
            # AVAILABLE 컬럼(3번째)이 False이거나 DEGRADED(4번째)가 True
            split($0, cols)
            if (cols[3] == "False" || cols[4] == "True") {
                print "[ABNORMAL]"$0
            } else {
                print $0
            }
            next
        }
        {print $0}'
else
    echo "$output" | awk -v RED="'"${RED}"'" -v CYAN="'"${CYAN}"'" -v BOLD="'"${BOLD}"'" -v NC="'"${NC}"'" '
        NR==1 {print BOLD CYAN $0 NC; next}
        {
            if ($3 == "False" || $4 == "True" || $5 == "True") {
                print RED $0 NC
            } else {
                print $0
            }
        }'
fi

exit 0
