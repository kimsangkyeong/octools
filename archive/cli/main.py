#!/usr/bin/env python3
"""
OCP 관리도구 (octools) - Linux CLI 메인 프로그램
터미널에서 인터랙티브 메뉴를 통해 shell script를 실행한다.

각 메뉴의 실제 명령어는 scripts/menus/*.sh 파일에 정의되어 있으며,
운영자는 해당 스크립트를 직접 수정하여 출력 커스터마이징이 가능하다.

사용법:
    python3 -m cli.main
    또는
    ./run_cli.sh
"""

import os
import sys
import subprocess

# 프로젝트 루트를 path에 추가
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from common.menu_config import get_menu_items, get_menu_by_id, MENUS_DIR
from common.oc_commands import get_namespaces
from cli.menu_renderer import (
    render_main_menu,
    render_namespace_menu,
    render_result_header,
    clear_screen,
)
from cli.color_output import print_error, print_info, Colors


def main():
    """CLI 메인 루프"""
    current_page = 0

    while True:
        # 메인 메뉴 렌더링
        page_items, total_pages, current_page = render_main_menu(current_page)

        # 사용자 입력 받기
        try:
            print()
            user_input = input(f"  {Colors.WHITE}메뉴 번호를 입력하세요: {Colors.RESET}").strip()
        except (KeyboardInterrupt, EOFError):
            print("\n")
            print_info("프로그램을 종료합니다.")
            sys.exit(0)

        # 입력 처리
        if user_input.lower() == 'q':
            clear_screen()
            print_info("프로그램을 종료합니다. 감사합니다.")
            break
        elif user_input.lower() == 'n':
            if current_page < total_pages - 1:
                current_page += 1
            continue
        elif user_input.lower() == 'p':
            if current_page > 0:
                current_page -= 1
            continue
        elif user_input == '':
            continue

        # 번호 입력 처리
        try:
            menu_num = int(user_input)
            menu_items = get_menu_items()

            if menu_num < 1 or menu_num > len(menu_items):
                print_error(f"유효하지 않은 번호입니다. (1~{len(menu_items)})")
                _wait_for_enter()
                continue

            selected_item = menu_items[menu_num - 1]

        except ValueError:
            print_error("숫자 또는 명령어(n/p/q)를 입력하세요.")
            _wait_for_enter()
            continue

        # 메뉴 실행
        _execute_menu(selected_item)


def _execute_menu(menu_item):
    """
    선택된 메뉴의 shell script를 실행한다.
    namespace_required인 경우 NS 서브메뉴를 먼저 표시한다.
    pod_selection_required인 경우 NS 선택 후 Pod 서브메뉴를 추가로 표시한다.
    """
    namespace = None
    pod_name = None

    # 1단계: Namespace 선택 (필요한 경우)
    if menu_item["namespace_required"]:
        namespace = _select_namespace()
        if namespace is None:
            return  # 뒤로가기

    # 2단계: Pod 선택 (필요한 경우)
    if menu_item.get("pod_selection_required", False):
        # Pod 선택은 특정 namespace가 필요 (__ALL__이면 NS 재선택 안내)
        if namespace == "__ALL__":
            print_info("Pod 선택을 위해 특정 Namespace를 지정해야 합니다.")
            namespace = _select_namespace(allow_all=False)
            if namespace is None:
                return

        pod_name = _select_pod(namespace)
        if pod_name is None:
            return  # 뒤로가기

    # shell script 직접 실행 (color 모드 → 터미널에 바로 출력)
    script_path = menu_item["script_path"]

    clear_screen()
    render_result_header(menu_item["name"], namespace)

    if not os.path.exists(script_path):
        print_error(f"스크립트 파일이 없습니다: {script_path}")
        print_info(f"scripts/menus/{menu_item['script']} 파일을 생성해주세요.")
        _wait_for_enter()
        return

    # 스크립트 인수 구성: $1=namespace, $2=output_mode, $3=pod_name(선택)
    args = ["bash", script_path]
    if namespace is None:
        args.append("__NONE__")
    else:
        args.append(namespace)
    args.append("color")  # CLI에서는 color 모드

    if pod_name:
        args.append(pod_name)

    # 실행 정보 표시
    info_parts = [f"스크립트: {menu_item['script']}"]
    if namespace and namespace != "__NONE__":
        info_parts.append(f"NS: {namespace}")
    if pod_name:
        info_parts.append(f"Pod: {pod_name}")
    print_info(" | ".join(info_parts))
    print()

    try:
        result = subprocess.run(
            args,
            timeout=60,  # NS 리소스 종합조회 등은 시간이 더 걸릴 수 있음
            cwd=os.path.dirname(script_path),
        )

        if result.returncode != 0:
            print()
            print_error("명령어 실행에 실패했습니다.")

    except subprocess.TimeoutExpired:
        print_error("실행 시간 초과 (60초)")
    except Exception as e:
        print_error(f"실행 오류: {str(e)}")

    print()
    _wait_for_enter()


def _select_namespace(allow_all=True):
    """
    Namespace 선택 서브메뉴를 표시하고 선택 결과를 반환한다.

    Args:
        allow_all (bool): True면 [0] 전체(All) 옵션 표시, False면 특정 NS만 선택 가능

    Returns:
        str: "__ALL__" 또는 namespace명
        None: 뒤로가기
    """
    print_info("Namespace 목록을 조회 중...")
    ns_result = get_namespaces()

    if not ns_result["success"]:
        print_error(f"Namespace 조회 실패: {ns_result['error']}")
        _wait_for_enter()
        return None

    namespaces = ns_result["namespaces"]

    while True:
        render_namespace_menu(namespaces)

        if not allow_all:
            print(f"  {Colors.YELLOW}※ 이 메뉴는 특정 Namespace를 선택해야 합니다.{Colors.RESET}")

        try:
            print()
            user_input = input(f"  {Colors.WHITE}번호를 입력하세요: {Colors.RESET}").strip()
        except (KeyboardInterrupt, EOFError):
            return None

        if user_input.lower() == 'b':
            return None
        elif user_input.lower() == 'q':
            clear_screen()
            print_info("프로그램을 종료합니다.")
            sys.exit(0)
        elif user_input == '0':
            if allow_all:
                return "__ALL__"
            else:
                print_error("이 메뉴는 특정 Namespace를 선택해야 합니다.")
                _wait_for_enter()
                continue

        try:
            ns_num = int(user_input)
            if 1 <= ns_num <= len(namespaces):
                return namespaces[ns_num - 1]
            else:
                print_error(f"유효하지 않은 번호입니다. (0~{len(namespaces)})")
                _wait_for_enter()
        except ValueError:
            print_error("숫자 또는 명령어(b/q)를 입력하세요.")
            _wait_for_enter()


def _select_pod(namespace):
    """
    Pod 선택 서브메뉴를 표시하고 선택 결과를 반환한다.

    Args:
        namespace (str): Pod를 조회할 namespace

    Returns:
        str: 선택된 Pod 이름
        None: 뒤로가기
    """
    print_info(f"Pod 목록을 조회 중... (namespace: {namespace})")

    try:
        result = subprocess.run(
            ["oc", "get", "pod", "-n", namespace,
             "-o", "custom-columns=NAME:.metadata.name,STATUS:.status.phase,RESTARTS:.status.containerStatuses[0].restartCount,AGE:.metadata.creationTimestamp",
             "--no-headers"],
            capture_output=True,
            text=True,
            timeout=15,
        )

        if result.returncode != 0:
            print_error(f"Pod 조회 실패: {result.stderr.strip()}")
            _wait_for_enter()
            return None

        pod_lines = [line.strip() for line in result.stdout.strip().split("\n") if line.strip()]

        if not pod_lines:
            print_error(f"namespace '{namespace}'에 Pod이 없습니다.")
            _wait_for_enter()
            return None

    except subprocess.TimeoutExpired:
        print_error("Pod 목록 조회 시간 초과")
        _wait_for_enter()
        return None
    except Exception as e:
        print_error(f"Pod 조회 오류: {str(e)}")
        _wait_for_enter()
        return None

    # Pod 이름 추출
    pods = []
    for line in pod_lines:
        parts = line.split()
        if parts:
            pods.append(parts[0])

    while True:
        # Pod 선택 화면 렌더링
        _render_pod_menu(pods, pod_lines, namespace)

        try:
            print()
            user_input = input(f"  {Colors.WHITE}Pod 번호를 입력하세요: {Colors.RESET}").strip()
        except (KeyboardInterrupt, EOFError):
            return None

        if user_input.lower() == 'b':
            return None
        elif user_input.lower() == 'q':
            clear_screen()
            print_info("프로그램을 종료합니다.")
            sys.exit(0)

        try:
            pod_num = int(user_input)
            if 1 <= pod_num <= len(pods):
                return pods[pod_num - 1]
            else:
                print_error(f"유효하지 않은 번호입니다. (1~{len(pods)})")
                _wait_for_enter()
        except ValueError:
            print_error("숫자 또는 명령어(b/q)를 입력하세요.")
            _wait_for_enter()


def _render_pod_menu(pods, pod_lines, namespace):
    """Pod 선택 서브메뉴 화면 렌더링"""
    clear_screen()
    term_width = os.get_terminal_size().columns if hasattr(os, 'get_terminal_size') else 80

    print(f"{Colors.BOLD}{Colors.YELLOW}{'=' * term_width}{Colors.RESET}")
    print(f"{Colors.BOLD}{Colors.YELLOW}  Pod 선택 (namespace: {namespace}){Colors.RESET}")
    print(f"{Colors.BOLD}{Colors.YELLOW}{'=' * term_width}{Colors.RESET}")
    print()
    print(f"  {Colors.CYAN}{Colors.BOLD}{'#':<5}{'NAME':<50}{'STATUS':<15}{'RESTARTS':<10}{Colors.RESET}")
    print(f"  {Colors.BLUE}{'-' * (term_width - 4)}{Colors.RESET}")

    for i, line in enumerate(pod_lines):
        parts = line.split()
        name = parts[0] if len(parts) > 0 else ""
        status = parts[1] if len(parts) > 1 else ""
        restarts = parts[2] if len(parts) > 2 else ""

        # 비정상 상태 빨간색
        abnormal_keywords = ["Error", "CrashLoopBackOff", "ImagePullBackOff",
                           "Pending", "Terminating", "Failed", "Unknown"]
        is_abnormal = any(kw.lower() in status.lower() for kw in abnormal_keywords)

        if is_abnormal:
            print(f"  {Colors.RED}[{i+1:3d}] {name:<50}{status:<15}{restarts:<10}{Colors.RESET}")
        else:
            print(f"  [{i+1:3d}] {name:<50}{status:<15}{restarts:<10}")

    print()
    print(f"{Colors.BLUE}{'─' * term_width}{Colors.RESET}")
    print(f"{Colors.CYAN}  [b] 뒤로가기  [q] 종료{Colors.RESET}")
    print(f"{Colors.BLUE}{'─' * term_width}{Colors.RESET}")


def _wait_for_enter():
    """Enter 키 대기"""
    try:
        input(f"\n  {Colors.CYAN}[Enter] 계속...{Colors.RESET}")
    except (KeyboardInterrupt, EOFError):
        pass


if __name__ == "__main__":
    main()
