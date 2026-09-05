"""
OCP 관리도구 - oc 명령어 실행 모듈 (Shell Script 방식)
각 메뉴의 실행은 scripts/menus/ 디렉토리의 shell script를 호출하여 수행한다.
운영자는 .sh 파일을 직접 수정하여 awk/grep/sed 등으로 출력을 커스터마이징할 수 있다.
"""

import subprocess
import os
from .menu_config import get_menu_by_id, MENUS_DIR, SCRIPTS_DIR


def execute_menu_script(menu_id, namespace=None, output_mode="plain", pod_name=None):
    """
    메뉴 ID에 해당하는 shell script를 실행한다.

    Args:
        menu_id (str): 메뉴 ID
        namespace (str, optional): namespace. None이면 스크립트 기본 동작.
            "__ALL__" → 전체, 문자열 → 특정 NS
        output_mode (str): "color" (CLI 직접) 또는 "plain" (API 서버)
        pod_name (str, optional): Pod 이름 (pod_selection_required 메뉴에서 사용)

    Returns:
        dict: {
            "success": bool,
            "command": str,       # 실행된 스크립트 경로
            "output": str,        # 원본 출력
            "lines": list,        # 파싱된 라인 [{text, abnormal}]
            "error": str          # 에러 메시지
        }
    """
    menu_item = get_menu_by_id(menu_id)
    if menu_item is None:
        return {
            "success": False,
            "command": "",
            "output": "",
            "lines": [],
            "error": f"메뉴 ID '{menu_id}'를 찾을 수 없습니다."
        }

    script_path = menu_item["script_path"]

    if not os.path.exists(script_path):
        return {
            "success": False,
            "command": script_path,
            "output": "",
            "lines": [],
            "error": f"스크립트 파일이 없습니다: {script_path}"
        }

    return _run_script(script_path, namespace, output_mode, pod_name)


def execute_script_direct(script_path, namespace=None, output_mode="plain", pod_name=None):
    """
    스크립트 경로를 직접 지정하여 실행한다.

    Args:
        script_path (str): shell script 절대 경로
        namespace (str): namespace
        output_mode (str): "color" 또는 "plain"
        pod_name (str, optional): Pod 이름

    Returns:
        dict: 실행 결과
    """
    if not os.path.exists(script_path):
        return {
            "success": False,
            "command": script_path,
            "output": "",
            "lines": [],
            "error": f"스크립트 파일이 없습니다: {script_path}"
        }

    return _run_script(script_path, namespace, output_mode, pod_name)


def _run_script(script_path, namespace=None, output_mode="plain", pod_name=None):
    """
    shell script를 실행하고 결과를 파싱한다.

    인터페이스 규약:
      $1 = namespace ("__ALL__", "__NONE__", 또는 namespace명)
      $2 = output_mode ("color" 또는 "plain")
      $3 = pod_name (선택, Pod 선택이 필요한 메뉴에서 전달)
    """
    # 인수 구성
    args = ["bash", script_path]

    if namespace is None:
        args.append("__NONE__")
    else:
        args.append(namespace)

    args.append(output_mode)

    if pod_name:
        args.append(pod_name)

    try:
        result = subprocess.run(
            args,
            capture_output=True,
            text=True,
            timeout=30,
            cwd=SCRIPTS_DIR,
        )

        output = result.stdout
        error = result.stderr.strip()

        if result.returncode == 0:
            lines = _parse_script_output(output, output_mode)
            return {
                "success": True,
                "command": os.path.basename(script_path),
                "output": output,
                "lines": lines,
                "error": ""
            }
        else:
            return {
                "success": False,
                "command": os.path.basename(script_path),
                "output": output,
                "lines": [],
                "error": error if error else "명령어 실행 실패"
            }

    except subprocess.TimeoutExpired:
        return {
            "success": False,
            "command": os.path.basename(script_path),
            "output": "",
            "lines": [],
            "error": "스크립트 실행 시간 초과 (30초)"
        }
    except Exception as e:
        return {
            "success": False,
            "command": os.path.basename(script_path),
            "output": "",
            "lines": [],
            "error": f"실행 오류: {str(e)}"
        }


def _parse_script_output(output, output_mode):
    """
    스크립트 출력을 파싱하여 라인 리스트로 변환한다.

    plain 모드: [HEADER], [ABNORMAL] 태그 기반 파싱
    color 모드: ANSI 코드 제거 후 키워드 기반 파싱
    """
    if not output or not output.strip():
        return []

    lines = output.strip().split("\n")
    result = []

    if output_mode == "plain":
        # plain 모드: 태그 기반 파싱
        for line in lines:
            if line.startswith("[HEADER]"):
                result.append({"text": line[8:], "abnormal": False})
            elif line.startswith("[ABNORMAL]"):
                result.append({"text": line[10:], "abnormal": True})
            else:
                result.append({"text": line, "abnormal": False})
    else:
        # color 모드: ANSI 코드 제거 후 반환 (CLI에서는 직접 출력하므로 파싱 불필요)
        import re
        ansi_escape = re.compile(r'\x1b\[[0-9;]*m')
        for i, line in enumerate(lines):
            clean_line = ansi_escape.sub('', line)
            # 헤더는 첫 줄
            abnormal = False
            if i > 0:
                abnormal = _is_abnormal_keyword(clean_line)
            result.append({"text": clean_line, "abnormal": abnormal})

    return result


def _is_abnormal_keyword(line):
    """키워드 기반 비정상 판단 (fallback)"""
    keywords = [
        "CrashLoopBackOff", "ImagePullBackOff", "ErrImagePull",
        "Error", "OOMKilled", "Pending", "Terminating",
        "NotReady", "Unknown", "Failed", "Evicted", "DEGRADED",
        "SchedulingDisabled", "ContainerStatusUnknown",
    ]
    line_upper = line.upper()
    for kw in keywords:
        if kw.upper() in line_upper:
            return True
    return False


def get_namespaces():
    """
    클러스터의 namespace 목록을 조회한다.

    Returns:
        dict: {
            "success": bool,
            "namespaces": list of str,
            "error": str
        }
    """
    try:
        result = subprocess.run(
            ["oc", "get", "ns", "-o", "custom-columns=NAME:.metadata.name", "--no-headers"],
            capture_output=True,
            text=True,
            timeout=15
        )

        if result.returncode == 0:
            namespaces = [ns.strip() for ns in result.stdout.strip().split("\n") if ns.strip()]
            return {
                "success": True,
                "namespaces": sorted(namespaces),
                "error": ""
            }
        else:
            return {
                "success": False,
                "namespaces": [],
                "error": result.stderr.strip()
            }

    except Exception as e:
        return {
            "success": False,
            "namespaces": [],
            "error": f"Namespace 조회 오류: {str(e)}"
        }
