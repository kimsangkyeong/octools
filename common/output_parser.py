"""
OCP 관리도구 - 출력 파싱 모듈
oc 명령어 출력을 파싱하고 비정상 상태를 감지한다.
"""

# 비정상 상태 키워드 목록
ABNORMAL_KEYWORDS = [
    "CrashLoopBackOff",
    "ImagePullBackOff",
    "ErrImagePull",
    "Error",
    "OOMKilled",
    "Pending",
    "Terminating",
    "NotReady",
    "Unknown",
    "Failed",
    "Evicted",
    "ContainerStatusUnknown",
    "DEGRADED",
    "SchedulingDisabled",
]

# ClusterOperator 등에서 비정상 패턴 (컬럼 값 기반)
# "False" 가 AVAILABLE 컬럼에 있거나 "True" 가 DEGRADED 컬럼에 있는 경우
ABNORMAL_CO_PATTERNS = [
    # (column_header, abnormal_value)
    ("AVAILABLE", "False"),
    ("DEGRADED", "True"),
    ("PROGRESSING", "True"),
]


def parse_output(output):
    """
    oc 명령어 출력을 라인별로 파싱하여 비정상 여부를 표시한다.

    Args:
        output (str): 명령어 출력 원문

    Returns:
        list: [{"text": str, "abnormal": bool}, ...]
    """
    if not output or not output.strip():
        return []

    lines = output.strip().split("\n")
    result = []

    # 첫 줄이 헤더인지 확인
    header = lines[0] if lines else ""

    for i, line in enumerate(lines):
        if i == 0:
            # 헤더 라인은 비정상 표시 안 함
            result.append({"text": line, "abnormal": False})
        else:
            abnormal = is_abnormal_line(line, header)
            result.append({"text": line, "abnormal": abnormal})

    return result


def is_abnormal_line(line, header=""):
    """
    라인이 비정상 상태인지 확인한다.

    Args:
        line (str): 검사할 라인
        header (str): 헤더 라인 (컬럼 위치 기반 판단 시 사용)

    Returns:
        bool: 비정상이면 True
    """
    if not line.strip():
        return False

    # 1. 키워드 기반 검사
    line_upper = line.upper()
    for keyword in ABNORMAL_KEYWORDS:
        if keyword.upper() in line_upper:
            # "Running" 같은 정상 상태와 구분
            # STATUS 컬럼에 Error가 있는지 등을 확인
            if keyword.upper() == "ERROR" and "NOERROR" in line_upper:
                continue
            return True

    # 2. ClusterOperator 패턴 검사 (컬럼 위치 기반)
    if header:
        for col_name, abnormal_value in ABNORMAL_CO_PATTERNS:
            col_start = header.find(col_name)
            if col_start >= 0:
                # 컬럼 위치에서 값 추출
                col_end = col_start + len(col_name) + 10  # 여유 공간
                line_segment = line[col_start:col_end].strip().split()[0] if len(line) > col_start else ""
                if line_segment == abnormal_value:
                    return True

    # 3. Node NotReady 확인
    parts = line.split()
    if len(parts) >= 2:
        if parts[1] == "NotReady" or "NotReady" in parts[1]:
            return True

    return False
