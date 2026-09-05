"""
OCP 관리도구 - API 라우트 정의 (Shell Script 실행 방식)
각 메뉴 요청 시 scripts/menus/*.sh 를 plain 모드로 호출하여 결과를 반환한다.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from fastapi import APIRouter, HTTPException
from pydantic import BaseModel
from typing import Optional

from common.menu_config import get_menu_items, get_menu_by_id, CATEGORIES, reload_menus
from common.oc_commands import execute_menu_script, get_namespaces

router = APIRouter()


# ─── Request/Response Models ─────────────────────────────────────────

class ExecuteRequest(BaseModel):
    menu_id: str
    namespace: Optional[str] = None
    pod_name: Optional[str] = None  # Pod 선택이 필요한 메뉴에서 사용


class ExecuteResponse(BaseModel):
    success: bool
    command: str
    output: str
    lines: list
    error: str


class NamespaceResponse(BaseModel):
    success: bool
    namespaces: list
    error: str


class MenuItemResponse(BaseModel):
    id: str
    name: str
    script: str
    namespace_required: bool
    description: str
    category: str


# ─── Endpoints ────────────────────────────────────────────────────────

@router.get("/health")
def health_check():
    """서버 상태 확인"""
    return {"status": "healthy", "service": "octools-api"}


@router.get("/menus")
def list_menus():
    """메뉴 목록 조회 (menus.conf에서 동적 로드)"""
    items = get_menu_items()
    return [
        {
            "id": item["id"],
            "name": item["name"],
            "script": item["script"],
            "namespace_required": item["namespace_required"],
            "pod_selection_required": item.get("pod_selection_required", False),
            "description": item["description"],
            "category": item["category"],
        }
        for item in items
    ]


@router.get("/categories")
def list_categories():
    """카테고리 목록 조회"""
    return {"categories": CATEGORIES}


@router.post("/reload-menus")
def reload_menu_config():
    """menus.conf 강제 리로드"""
    items = reload_menus()
    return {"reloaded": True, "menu_count": len(items)}


@router.post("/execute", response_model=ExecuteResponse)
def execute_command(request: ExecuteRequest):
    """
    메뉴에 해당하는 shell script 실행

    - menu_id: 메뉴 항목 ID
    - namespace: namespace (선택)
    - pod_name: Pod 이름 (pod_selection_required=Y인 메뉴에서 필요)
    """
    menu_item = get_menu_by_id(request.menu_id)
    if menu_item is None:
        raise HTTPException(status_code=404, detail=f"메뉴 ID '{request.menu_id}'를 찾을 수 없습니다.")

    # namespace 처리
    namespace = request.namespace
    if menu_item["namespace_required"] and namespace is None:
        namespace = "__ALL__"

    # pod_name 처리
    pod_name = request.pod_name
    if menu_item.get("pod_selection_required", False) and not pod_name:
        raise HTTPException(status_code=400, detail="이 메뉴는 pod_name이 필요합니다.")

    # shell script를 plain 모드로 실행 (API 전용)
    result = execute_menu_script(request.menu_id, namespace, output_mode="plain", pod_name=pod_name)
    return ExecuteResponse(**result)


@router.get("/namespaces", response_model=NamespaceResponse)
def list_namespaces():
    """Namespace 목록 조회"""
    result = get_namespaces()
    return NamespaceResponse(**result)
