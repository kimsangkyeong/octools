#!/bin/bash
#
# PVC 조회
# STATUS가 Bound가 아닌 경우 비정상으로 표시
# 사용: ./pvc_list.sh [namespace] [output_mode]
#
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

check_oc_env

NS="${1:-__ALL__}"
MODE="${2:-color}"
NS_OPT=$(build_ns_option "$NS")

output=$(oc get pvc $NS_OPT 2>&1)
rc=$?

if [ $rc -ne 0 ]; then
    echo "$output" >&2
    exit $rc
fi

if [ "$MODE" = "plain" ]; then
    echo "$output" | awk 'NR==1 {print "[HEADER]"$0; next}
        /Pending|Lost/ {print "[ABNORMAL]"$0; next}
        {print $0}'
else
    echo "$output" | awk -v RED="'"${RED}"'" -v CYAN="'"${CYAN}"'" -v BOLD="'"${BOLD}"'" -v NC="'"${NC}"'" '
        NR==1 {print BOLD CYAN $0 NC; next}
        /Pending|Lost/ {print RED $0 NC; next}
        {print $0}'
fi

exit 0
