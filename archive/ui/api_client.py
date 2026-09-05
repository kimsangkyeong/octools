"""
OCP 관리도구 - API 클라이언트 모듈
Streamlit UI에서 Linux 서버의 REST API를 호출하는 클라이언트.
"""

import requests
from typing import Optional


class OcToolsApiClient:
    """REST API 클라이언트"""

    def __init__(self, base_url="http://localhost:8000"):
        """
        Args:
            base_url (str): API 서버 기본 URL (예: http://192.168.1.100:8000)
        """
        self.base_url = base_url.rstrip("/")
        self.timeout = 30

    def health_check(self):
        """
        서버 상태 확인

        Returns:
            dict: {"status": "healthy"} 또는 에러 정보
        """
        try:
            resp = requests.get(f"{self.base_url}/api/health", timeout=5)
            resp.raise_for_status()
            return resp.json()
        except requests.ConnectionError:
            return {"status": "error", "error": "서버에 연결할 수 없습니다."}
        except requests.Timeout:
            return {"status": "error", "error": "서버 응답 시간 초과"}
        except Exception as e:
            return {"status": "error", "error": str(e)}

    def get_menus(self):
        """
        메뉴 목록 조회

        Returns:
            list: 메뉴 항목 리스트
        """
        try:
            resp = requests.get(f"{self.base_url}/api/menus", timeout=self.timeout)
            resp.raise_for_status()
            return resp.json()
        except Exception as e:
            return []

    def get_categories(self):
        """
        카테고리 목록 조회

        Returns:
            list: 카테고리 문자열 리스트
        """
        try:
            resp = requests.get(f"{self.base_url}/api/categories", timeout=self.timeout)
            resp.raise_for_status()
            return resp.json().get("categories", [])
        except Exception as e:
            return []

    def execute_command(self, menu_id: str, namespace: Optional[str] = None, pod_name: Optional[str] = None):
        """
        oc 명령어 실행

        Args:
            menu_id (str): 메뉴 ID
            namespace (str, optional): namespace
            pod_name (str, optional): Pod 이름 (pod_selection_required 메뉴)

        Returns:
            dict: 실행 결과 {success, command, output, lines, error}
        """
        try:
            payload = {"menu_id": menu_id}
            if namespace is not None:
                payload["namespace"] = namespace
            if pod_name is not None:
                payload["pod_name"] = pod_name

            resp = requests.post(
                f"{self.base_url}/api/execute",
                json=payload,
                timeout=self.timeout,
            )
            resp.raise_for_status()
            return resp.json()
        except requests.ConnectionError:
            return {
                "success": False,
                "command": "",
                "output": "",
                "lines": [],
                "error": "API 서버에 연결할 수 없습니다.",
            }
        except requests.Timeout:
            return {
                "success": False,
                "command": "",
                "output": "",
                "lines": [],
                "error": "명령어 실행 시간 초과",
            }
        except Exception as e:
            return {
                "success": False,
                "command": "",
                "output": "",
                "lines": [],
                "error": f"API 호출 오류: {str(e)}",
            }

    def get_namespaces(self):
        """
        Namespace 목록 조회

        Returns:
            dict: {success, namespaces, error}
        """
        try:
            resp = requests.get(f"{self.base_url}/api/namespaces", timeout=self.timeout)
            resp.raise_for_status()
            return resp.json()
        except requests.ConnectionError:
            return {
                "success": False,
                "namespaces": [],
                "error": "API 서버에 연결할 수 없습니다.",
            }
        except Exception as e:
            return {
                "success": False,
                "namespaces": [],
                "error": f"Namespace 조회 오류: {str(e)}",
            }
