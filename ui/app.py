#!/usr/bin/env python3
"""
OCP 관리도구 (octools) - Streamlit 웹 UI
Windows 환경에서 원격 Linux 서버의 oc 명령어를 실행하는 웹 인터페이스.

사용법:
    streamlit run ui/app.py
"""

import streamlit as st
import os
import sys

# 프로젝트 루트를 path에 추가
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from ui.api_client import OcToolsApiClient

# ─── 페이지 설정 ──────────────────────────────────────────────────────

st.set_page_config(
    page_title="OCP 관리도구",
    page_icon="🔧",
    layout="wide",
    initial_sidebar_state="expanded",
)

# ─── 세션 상태 초기화 ─────────────────────────────────────────────────

if "api_url" not in st.session_state:
    st.session_state.api_url = "http://localhost:8000"

if "result" not in st.session_state:
    st.session_state.result = None

if "selected_menu" not in st.session_state:
    st.session_state.selected_menu = None

if "namespaces" not in st.session_state:
    st.session_state.namespaces = []

# ─── API 클라이언트 ───────────────────────────────────────────────────


def get_client():
    return OcToolsApiClient(st.session_state.api_url)


# ─── 사이드바 ─────────────────────────────────────────────────────────

with st.sidebar:
    st.title("🔧 OCP 관리도구")
    st.markdown("---")

    # 서버 연결 설정
    st.subheader("⚙️ 서버 설정")
    api_url = st.text_input(
        "API 서버 URL",
        value=st.session_state.api_url,
        help="Linux 서버의 FastAPI URL (예: http://192.168.1.100:8000)",
    )
    st.session_state.api_url = api_url

    # 연결 상태 확인
    client = get_client()
    health = client.health_check()
    if health.get("status") == "healthy":
        st.success("● 서버 연결됨")
    else:
        st.error(f"● 연결 실패: {health.get('error', '알 수 없는 오류')}")

    st.markdown("---")

    # 메뉴 목록
    st.subheader("📋 메뉴")
    menus = client.get_menus()
    categories = client.get_categories()

    if not menus:
        st.warning("메뉴를 불러올 수 없습니다. 서버 연결을 확인하세요.")
    else:
        # 카테고리별 메뉴 표시
        for category in categories:
            category_menus = [m for m in menus if m["category"] == category]
            if category_menus:
                with st.expander(f"📂 {category}", expanded=True):
                    for menu in category_menus:
                        ns_badge = " 🏷️" if menu["namespace_required"] else ""
                        pod_badge = " 🎯" if menu.get("pod_selection_required", False) else ""
                        btn_label = f"{menu['name']}{ns_badge}{pod_badge}"
                        if st.button(btn_label, key=f"btn_{menu['id']}", use_container_width=True):
                            st.session_state.selected_menu = menu
                            st.session_state.result = None
                            # Pod 캐시 초기화
                            st.session_state.pop("pods_in_ns", None)
                            st.session_state.pop("pods_ns", None)
                            st.rerun()

# ─── 메인 영역 ────────────────────────────────────────────────────────

st.header("OCP 관리도구 (octools)")

# 선택된 메뉴가 있는 경우
if st.session_state.selected_menu:
    menu = st.session_state.selected_menu

    st.subheader(f"▶ {menu['name']}")
    st.caption(menu["description"])

    # Namespace 선택 (필요한 경우)
    namespace = None
    if menu["namespace_required"]:
        col1, col2 = st.columns([3, 1])
        with col1:
            # Pod 선택 필요 메뉴는 특정 NS만 선택 가능
            if menu.get("pod_selection_required", False):
                ns_option = "특정 Namespace 선택"
                st.info("이 메뉴는 특정 Namespace와 Pod를 선택해야 합니다.")
            else:
                ns_option = st.radio(
                    "Namespace 선택",
                    ["전체 (All Namespaces)", "특정 Namespace 선택"],
                    horizontal=True,
                    key="ns_option",
                )
        with col2:
            if ns_option == "특정 Namespace 선택":
                # Namespace 목록 로드
                if not st.session_state.namespaces:
                    with st.spinner("Namespace 목록 조회 중..."):
                        ns_result = client.get_namespaces()
                        if ns_result["success"]:
                            st.session_state.namespaces = ns_result["namespaces"]
                        else:
                            st.error(ns_result["error"])

                if st.session_state.namespaces:
                    namespace = st.selectbox(
                        "Namespace",
                        st.session_state.namespaces,
                        key="ns_select",
                    )
                else:
                    namespace = None
            else:
                namespace = "__ALL__"

    # Pod 선택 (필요한 경우)
    pod_name = None
    if menu.get("pod_selection_required", False) and namespace and namespace != "__ALL__":
        # Pod 목록 조회
        if "pods_in_ns" not in st.session_state or st.session_state.get("pods_ns") != namespace:
            with st.spinner(f"Pod 목록 조회 중... (ns: {namespace})"):
                pod_result = client.execute_command("pod_list", namespace)
                if pod_result["success"] and pod_result["lines"]:
                    pod_names = []
                    for line in pod_result["lines"]:
                        parts = line["text"].split()
                        if parts:
                            pod_names.append(parts[0])
                    st.session_state.pods_in_ns = pod_names
                    st.session_state.pods_ns = namespace
                else:
                    st.session_state.pods_in_ns = []

        if st.session_state.get("pods_in_ns"):
            pod_name = st.selectbox(
                "Pod 선택",
                st.session_state.pods_in_ns,
                key="pod_select",
            )
        else:
            st.warning("선택 가능한 Pod이 없습니다.")

    # 실행 버튼
    if st.button("🚀 실행", type="primary", use_container_width=True):
        with st.spinner("명령어 실행 중..."):
            # namespace 결정
            exec_ns = namespace
            if menu["namespace_required"] and exec_ns is None:
                exec_ns = "__ALL__"

            result = client.execute_command(menu["id"], exec_ns, pod_name=pod_name)
            st.session_state.result = result

    # 결과 출력
    if st.session_state.result:
        result = st.session_state.result
        st.markdown("---")

        if result["success"]:
            st.success(f"✓ 실행 완료: `{result['command']}`")

            # 결과 테이블 표시
            if result["lines"]:
                _render_result_table(result["lines"])
            else:
                st.info("결과가 없습니다.")
        else:
            st.error(f"✗ 실행 실패: {result['error']}")
            if result["output"]:
                st.code(result["output"])

else:
    # 초기 화면
    st.info("👈 왼쪽 사이드바에서 메뉴를 선택하세요.")

    st.markdown("""
    ### 사용 방법
    1. **서버 설정**: 사이드바 상단에서 API 서버 URL을 입력합니다.
    2. **메뉴 선택**: 카테고리별로 정리된 메뉴에서 원하는 항목을 클릭합니다.
    3. **Namespace 선택**: 🏷️ 표시가 있는 메뉴는 Namespace를 선택할 수 있습니다.
    4. **실행**: [실행] 버튼을 클릭하면 결과가 표시됩니다.

    ### 범례
    - 🏷️ : Namespace 선택 가능
    - 🔴 빨간색 라인 : 비정상 상태 리소스
    """)


# ─── 결과 렌더링 함수 ──────────────────────────────────────────────────

def _render_result_table(lines):
    """
    파싱된 결과 라인을 Streamlit에서 렌더링한다.
    비정상 라인은 빨간색으로 강조한다.
    """
    if not lines:
        return

    # HTML 테이블로 렌더링 (비정상 라인 빨간색 강조)
    html_parts = ['<div style="font-family: monospace; font-size: 13px; overflow-x: auto;">']
    html_parts.append('<pre style="background-color: #1e1e1e; color: #d4d4d4; padding: 15px; border-radius: 5px; overflow-x: auto;">')

    for i, line_info in enumerate(lines):
        text = line_info["text"].replace("<", "&lt;").replace(">", "&gt;")
        if i == 0:
            # 헤더 - 볼드 + 시안
            html_parts.append(f'<span style="color: #4ec9b0; font-weight: bold;">{text}</span>')
        elif line_info.get("abnormal", False):
            # 비정상 - 빨강
            html_parts.append(f'<span style="color: #f44747; font-weight: bold;">{text}</span>')
        else:
            # 정상
            html_parts.append(f'<span>{text}</span>')

    html_parts.append("</pre></div>")
    st.markdown("\n".join(html_parts), unsafe_allow_html=True)
