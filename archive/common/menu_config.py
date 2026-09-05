"""
OCP 관리도구 메뉴 설정 모듈
menus.conf 텍스트 파일에서 메뉴를 로드하여 CLI/UI에서 공통 사용.
새 메뉴 추가 시 menus.conf에 한 줄 추가 + scripts/menus/ 에 .sh 파일 추가만 하면 됨.
"""

import os

# 프로젝트 루트 경로
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCRIPTS_DIR = os.path.join(PROJECT_ROOT, "scripts")
MENUS_DIR = os.path.join(SCRIPTS_DIR, "menus")
MENUS_CONF = os.path.join(SCRIPTS_DIR, "menus.conf")

# 메뉴 카테고리 (menus.conf에서 자동 추출도 가능)
CATEGORIES = [
    "워크로드",
    "클러스터",
    "오퍼레이터",
    "네트워크",
    "스토리지",
    "종합조회",
    "기타",
]

# 캐시
_menu_items_cache = None
_conf_mtime = 0


def _load_menus_conf():
    """
    menus.conf 파일을 파싱하여 메뉴 리스트를 반환한다.
    형식: ID|메뉴명|스크립트파일|NS필요(Y/N)|카테고리|설명|POD필요(Y/N)
    7번째 필드(POD필요)는 선택 사항이며, 생략 시 N으로 처리한다.
    """
    global _menu_items_cache, _conf_mtime

    # 파일 변경 시 자동 리로드
    try:
        current_mtime = os.path.getmtime(MENUS_CONF)
    except OSError:
        current_mtime = 0

    if _menu_items_cache is not None and current_mtime == _conf_mtime:
        return _menu_items_cache

    items = []

    if not os.path.exists(MENUS_CONF):
        # menus.conf가 없으면 기본 하드코딩 메뉴 반환 (fallback)
        return _get_fallback_menus()

    with open(MENUS_CONF, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            # 빈 줄, 주석 무시
            if not line or line.startswith("#"):
                continue

            parts = line.split("|")
            if len(parts) < 6:
                continue

            # 7번째 필드: POD 선택 필요 여부 (생략 시 N)
            pod_required = False
            if len(parts) >= 7:
                pod_required = parts[6].strip().upper() == "Y"

            item = {
                "id": parts[0].strip(),
                "name": parts[1].strip(),
                "script": parts[2].strip(),
                "namespace_required": parts[3].strip().upper() == "Y",
                "category": parts[4].strip(),
                "description": parts[5].strip(),
                "pod_selection_required": pod_required,
                # shell script 전체 경로
                "script_path": os.path.join(MENUS_DIR, parts[2].strip()),
                # 하위 호환: 기존 command 필드 (API용)
                "command": f"scripts/menus/{parts[2].strip()}",
            }
            items.append(item)

    _menu_items_cache = items
    _conf_mtime = current_mtime
    return items


def get_menu_items():
    """전체 메뉴 목록 반환 (menus.conf에서 로드)"""
    return _load_menus_conf()


def get_menu_by_id(menu_id):
    """ID로 메뉴 항목 조회"""
    for item in get_menu_items():
        if item["id"] == menu_id:
            return item
    return None


def get_menus_by_category(category):
    """카테고리별 메뉴 목록 반환"""
    return [item for item in get_menu_items() if item["category"] == category]


def reload_menus():
    """메뉴 캐시 강제 리로드"""
    global _menu_items_cache, _conf_mtime
    _menu_items_cache = None
    _conf_mtime = 0
    return get_menu_items()


def _get_fallback_menus():
    """menus.conf 없을 때 기본 메뉴 (하위 호환)"""
    return [
        {"id": "pod_list", "name": "Pod 조회", "script": "pod_list.sh",
         "namespace_required": True, "pod_selection_required": False,
         "category": "워크로드",
         "description": "Pod 목록 조회", "script_path": os.path.join(MENUS_DIR, "pod_list.sh"),
         "command": "oc get pod"},
        {"id": "node_list", "name": "Node 상태 조회", "script": "node_list.sh",
         "namespace_required": False, "pod_selection_required": False,
         "category": "클러스터",
         "description": "Node 상태 조회", "script_path": os.path.join(MENUS_DIR, "node_list.sh"),
         "command": "oc get nodes"},
    ]
