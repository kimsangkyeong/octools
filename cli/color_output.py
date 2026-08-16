"""
OCP 관리도구 - 컬러 출력 모듈
터미널에서 비정상 라인을 빨강색으로, 정상은 기본색으로 출력한다.
"""

# ANSI 색상 코드
class Colors:
    RED = "\033[91m"
    GREEN = "\033[92m"
    YELLOW = "\033[93m"
    BLUE = "\033[94m"
    CYAN = "\033[96m"
    WHITE = "\033[97m"
    BOLD = "\033[1m"
    RESET = "\033[0m"


def print_colored_output(lines, use_color=True):
    """
    파싱된 라인 목록을 컬러로 출력한다.

    Args:
        lines (list): [{"text": str, "abnormal": bool}, ...]
        use_color (bool): 컬러 사용 여부
    """
    if not lines:
        print(f"{Colors.YELLOW}결과가 없습니다.{Colors.RESET}")
        return

    for i, line_info in enumerate(lines):
        text = line_info["text"]
        abnormal = line_info["abnormal"]

        if i == 0:
            # 헤더 라인 - 볼드 + 시안
            if use_color:
                print(f"{Colors.BOLD}{Colors.CYAN}{text}{Colors.RESET}")
            else:
                print(text)
        elif abnormal:
            # 비정상 라인 - 빨강색
            if use_color:
                print(f"{Colors.RED}{text}{Colors.RESET}")
            else:
                print(f"[!] {text}")
        else:
            # 정상 라인
            print(text)


def print_header(title):
    """헤더 배너 출력"""
    width = 60
    print(f"\n{Colors.BOLD}{Colors.BLUE}{'=' * width}{Colors.RESET}")
    print(f"{Colors.BOLD}{Colors.BLUE}  {title}{Colors.RESET}")
    print(f"{Colors.BOLD}{Colors.BLUE}{'=' * width}{Colors.RESET}\n")


def print_success(msg):
    """성공 메시지 출력"""
    print(f"{Colors.GREEN}✓ {msg}{Colors.RESET}")


def print_error(msg):
    """에러 메시지 출력"""
    print(f"{Colors.RED}✗ {msg}{Colors.RESET}")


def print_info(msg):
    """정보 메시지 출력"""
    print(f"{Colors.CYAN}ℹ {msg}{Colors.RESET}")
