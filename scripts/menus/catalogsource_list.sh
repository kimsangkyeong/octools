#!/bin/bash
#
# CatalogSource 조회
# Operator Hub의 CatalogSource 상태를 조회한다.
# STATUS가 READY가 아닌 경우 비정상으로 표시.
#
# 사용: ./catalogsource_list.sh [namespace] [output_mode]
#
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

check_oc_env

NS="${1:-__ALL__}"
MODE="${2:-color}"
NS_OPT=$(build_ns_option "$NS")

output=$(oc get catalogsource $NS_OPT 2>&1)
rc=$?

if [ $rc -ne 0 ]; then
    echo "$output" >&2
    exit $rc
fi

if [ "$MODE" = "plain" ]; then
    echo "$output" | awk 'NR==1 {print "[HEADER]"$0; next}
        /READY/ && !/READY.*True/ {print "[ABNORMAL]"$0; next}
        {print $0}'
else
    echo "$output" | awk -v RED="'"${RED}"'" -v CYAN="'"${CYAN}"'" -v BOLD="'"${BOLD}"'" -v NC="'"${NC}"'" '
        NR==1 {print BOLD CYAN $0 NC; next}
        {
            # LASTOBSERVED가 비어있거나 STATUS 문제 확인
            if ($0 ~ /Error/ || $0 ~ /Unknown/ || $0 ~ /Failed/) {
                print RED $0 NC
            } else {
                print $0
            }
        }'
fi

exit 0
