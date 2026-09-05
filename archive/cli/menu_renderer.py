"""
OCP 관리도구 - 메뉴 렌더링 모듈
터미널 화면에 메뉴를 이분할로 표시하고, 페이지 관리를 수행한다.
curses 대신 간단한 터미널 출력 방식을 사용하여 호환성을 높인다.
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from common.menu_config import get_menu_items
from cli.color_output import Colors


# 레이아웃 설정
ITEMS_PER_COLUMN = 8     # 한 열에 표시할 최대 항목 수
COLUMNS = 2              # 열 개수
ITEMS_PER_PAGE = ITEMS_PER_COLUMN * COLUMNS  # 페이지당 16개


def clear_screen():
    """화면 클리어"""
    os.system('clear' if os.name != 'nt' else 'cls')


def get_terminal_width():
    """터미널 너비 조회"""
    try:
        return os.get_terminal_size().columns
    except (ValueError, OSError):
        return 80


def render_main_menu(page=0):
    """
    메인 메뉴를 이분할 레이아웃으로 표시한다.

    Args:
        page (int): 현재 페이지 번호 (0-based)

    Returns:
        tuple: (표시된 메뉴 항목 리스트, 총 페이지 수, 현재 페이지)
    """
    menu_items = get_menu_items()
    total_pages = max(1, math.ceil(len(menu_items) / ITEMS_PER_PAGE))

    # 페이지 범위 보정
    page = max(0, min(page, total_pages - 1))

    # 현재 페이지 항목
    start_idx = page * ITEMS_PER_PAGE
    end_idx = min(start_idx + ITEMS_PER_PAGE, len(menu_items))
    page_items = menu_items[start_idx:end_idx]

    # 화면 출력
    clear_screen()
    term_width = get_terminal_width()
    col_width = term_width // 2 - 2

    # 타이틀
    print(f"{Colors.BOLD}{Colors.BLUE}{'=' * term_width}{Colors.RESET}")
    title = "OCP 관리도구 (octools)"
    print(f"{Colors.BOLD}{Colors.BLUE}{title:^{term_width}}{Colors.RESET}")
    print(f"{Colors.BOLD}{Colors.BLUE}{'=' * term_width}{Colors.RESET}")
    print()

    # 이분할 메뉴 출력
    left_items = page_items[:ITEMS_PER_COLUMN]
    right_items = page_items[ITEMS_PER_COLUMN:]

    max_rows = max(len(left_items), len(right_items))

    for row in range(max_rows):
        # 왼쪽 열
        if row < len(left_items):
            idx = start_idx + row + 1
            item = left_items[row]
            ns_mark = " [NS]" if item["namespace_required"] else ""
            pod_mark = " [POD]" if item.get("pod_selection_required", False) else ""
            left_text = f"  [{idx:2d}] {item['name']}{ns_mark}{pod_mark}"
        else:
            left_text = ""

        # 오른쪽 열
        if row < len(right_items):
            idx = start_idx + ITEMS_PER_COLUMN + row + 1
            item = right_items[row]
            ns_mark = " [NS]" if item["namespace_required"] else ""
            pod_mark = " [POD]" if item.get("pod_selection_required", False) else ""
            right_text = f"  [{idx:2d}] {item['name']}{ns_mark}{pod_mark}"
        else:
            right_text = ""

        # 컬럼 정렬 출력
        print(f"{Colors.WHITE}{left_text:<{col_width}}{Colors.RESET}│ {Colors.WHITE}{right_text}{Colors.RESET}")

    print()
    print(f"{Colors.BLUE}{'─' * term_width}{Colors.RESET}")

    # 페이지 정보 및 네비게이션
    page_info = f"  페이지 {page + 1}/{total_pages}"
    nav_info = "[NS]: NS선택  [POD]: Pod선택  |  [n] 다음  [p] 이전  [q] 종료"
    print(f"{Colors.CYAN}{page_info}  |  {nav_info}{Colors.RESET}")
    print(f"{Colors.BLUE}{'─' * term_width}{Colors.RESET}")

    return page_items, total_pages, page


def render_namespace_menu(namespaces):
    """
    Namespace 선택 서브메뉴를 표시한다.

    Args:
        namespaces (list): namespace 이름 리스트

    Returns:
        None (화면에 출력만 수행)
    """
    clear_screen()
    term_width = get_terminal_width()

    print(f"{Colors.BOLD}{Colors.YELLOW}{'=' * term_width}{Colors.RESET}")
    print(f"{Colors.BOLD}{Colors.YELLOW}{'  Namespace 선택':^{term_width}}{Colors.RESET}")
    print(f"{Colors.BOLD}{Colors.YELLOW}{'=' * term_width}{Colors.RESET}")
    print()

    # [0] 전체 옵션
    print(f"  {Colors.GREEN}[ 0] 전체 (All Namespaces){Colors.RESET}")
    print()

    # Namespace 목록 이분할 표시
    col_width = term_width // 2 - 2
    half = math.ceil(len(namespaces) / 2)
    left_ns = namespaces[:half]
    right_ns = namespaces[half:]

    max_rows = max(len(left_ns), len(right_ns))

    for row in range(max_rows):
        if row < len(left_ns):
            left_text = f"  [{row + 1:3d}] {left_ns[row]}"
        else:
            left_text = ""

        if row < len(right_ns):
            right_text = f"  [{half + row + 1:3d}] {right_ns[row]}"
        else:
            right_text = ""

        print(f"{left_text:<{col_width}}│ {right_text}")

    print()
    print(f"{Colors.BLUE}{'─' * term_width}{Colors.RESET}")
    print(f"{Colors.CYAN}  번호 입력 후 Enter  |  [b] 뒤로가기  [q] 종료{Colors.RESET}")
    print(f"{Colors.BLUE}{'─' * term_width}{Colors.RESET}")


def render_result_header(command, namespace=None):
    """실행 결과 영역 헤더 출력"""
    term_width = get_terminal_width()
    print()
    print(f"{Colors.BOLD}{Colors.GREEN}{'─' * term_width}{Colors.RESET}")
    ns_info = f"  (namespace: {namespace})" if namespace and namespace != "__ALL__" else "  (All Namespaces)" if namespace == "__ALL__" else ""
    print(f"{Colors.BOLD}{Colors.GREEN}  실행: {command}{ns_info}{Colors.RESET}")
    print(f"{Colors.BOLD}{Colors.GREEN}{'─' * term_width}{Colors.RESET}")
    print()
