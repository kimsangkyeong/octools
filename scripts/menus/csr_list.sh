#!/bin/bash
#
# CertificateSigningRequest 조회
# Pending/Denied 상태를 비정상으로 표시
# 사용: ./csr_list.sh [namespace] [output_mode]
#
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../common.sh"

check_oc_env

MODE="${2:-color}"
FILTER=$(get_output_filter "$MODE")

oc get csr 2>&1 | $FILTER
exit ${PIPESTATUS[0]}
