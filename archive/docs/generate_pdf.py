#!/usr/bin/env python3
"""
OCP 관리도구 (octools) - PDF 생성 스크립트 (Python)
Markdown 문서를 PDF로 변환한다.

사전 요구사항:
    pip install markdown weasyprint
    또는
    pip install md2pdf

사용법:
    python3 docs/generate_pdf.py
"""

import os
import sys
import subprocess


SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
OUTPUT_DIR = os.path.join(SCRIPT_DIR, "pdf")

# 변환할 파일 목록
MD_FILES = [
    "requirements.md",
    "architecture.md",
    "server_setup_guide.md",
]

# CSS 스타일 (PDF 내 적용)
CSS_STYLE = """
<style>
body {
    font-family: 'Nanum Gothic', 'Malgun Gothic', sans-serif;
    font-size: 11pt;
    line-height: 1.6;
    margin: 40px;
    color: #333;
}
h1 { color: #1a5276; border-bottom: 2px solid #1a5276; padding-bottom: 10px; }
h2 { color: #2c3e50; margin-top: 30px; }
h3 { color: #34495e; }
table { border-collapse: collapse; width: 100%; margin: 15px 0; }
th, td { border: 1px solid #bdc3c7; padding: 8px 12px; text-align: left; }
th { background-color: #2c3e50; color: white; }
tr:nth-child(even) { background-color: #f8f9fa; }
pre { background-color: #f4f4f4; padding: 15px; border-radius: 5px; overflow-x: auto; font-size: 10pt; }
code { font-family: 'Nanum Gothic Coding', 'Consolas', monospace; background-color: #f0f0f0; padding: 2px 5px; border-radius: 3px; }
pre code { background-color: transparent; padding: 0; }
blockquote { border-left: 4px solid #3498db; padding-left: 15px; color: #555; }
</style>
"""


def convert_with_weasyprint(md_path, pdf_path):
    """weasyprint을 사용한 변환"""
    try:
        import markdown
        from weasyprint import HTML
    except ImportError:
        return False, "weasyprint 또는 markdown 패키지가 설치되지 않았습니다."

    with open(md_path, "r", encoding="utf-8") as f:
        md_content = f.read()

    # Markdown → HTML 변환
    html_content = markdown.markdown(
        md_content,
        extensions=["tables", "fenced_code", "toc", "codehilite"],
    )

    # 전체 HTML 문서 생성
    full_html = f"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
{CSS_STYLE}
</head>
<body>
{html_content}
</body>
</html>"""

    # PDF 생성
    HTML(string=full_html).write_pdf(pdf_path)
    return True, ""


def convert_with_pandoc(md_path, pdf_path):
    """pandoc을 사용한 변환"""
    try:
        result = subprocess.run(
            [
                "pandoc", md_path,
                "-o", pdf_path,
                "--pdf-engine=xelatex",
                "-V", "mainfont=NanumGothic",
                "-V", "monofont=NanumGothicCoding",
                "-V", "geometry:margin=2.5cm",
                "-V", "fontsize=10pt",
                "--highlight-style=tango",
                "--toc",
                "-V", "toc-title=목차",
            ],
            capture_output=True,
            text=True,
            timeout=60,
        )
        if result.returncode == 0:
            return True, ""
        else:
            return False, result.stderr
    except FileNotFoundError:
        return False, "pandoc이 설치되지 않았습니다."
    except Exception as e:
        return False, str(e)


def convert_with_md2pdf(md_path, pdf_path):
    """md2pdf를 사용한 변환"""
    try:
        from md2pdf.core import md2pdf as _md2pdf
    except ImportError:
        return False, "md2pdf 패키지가 설치되지 않았습니다."

    try:
        _md2pdf(
            pdf_path,
            md_file_path=md_path,
            css_file_path=None,
            base_url=SCRIPT_DIR,
        )
        return True, ""
    except Exception as e:
        return False, str(e)


def main():
    """메인 함수"""
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    print("=" * 50)
    print("  OCP 관리도구 - PDF 문서 생성")
    print("=" * 50)
    print()

    # 사용 가능한 변환기 확인
    converters = [
        ("pandoc", convert_with_pandoc),
        ("weasyprint", convert_with_weasyprint),
        ("md2pdf", convert_with_md2pdf),
    ]

    success_count = 0
    fail_count = 0

    for md_file in MD_FILES:
        input_path = os.path.join(SCRIPT_DIR, md_file)
        output_file = md_file.replace(".md", ".pdf")
        output_path = os.path.join(OUTPUT_DIR, output_file)

        if not os.path.exists(input_path):
            print(f"[SKIP] {md_file} - 파일 없음")
            continue

        print(f"[변환] {md_file} → pdf/{output_file} ... ", end="", flush=True)

        converted = False
        for conv_name, conv_func in converters:
            success, error = conv_func(input_path, output_path)
            if success:
                print(f"완료 ({conv_name})")
                success_count += 1
                converted = True
                break

        if not converted:
            print("실패")
            fail_count += 1

    print()
    print("=" * 50)
    print(f"  결과: 성공 {success_count}, 실패 {fail_count}")
    print(f"  출력: {OUTPUT_DIR}/")
    print("=" * 50)

    if fail_count > 0 and success_count == 0:
        print()
        print("PDF 변환 도구가 설치되지 않았습니다.")
        print("다음 중 하나를 설치하세요:")
        print()
        print("  방법 1) pandoc (권장)")
        print("    sudo dnf install pandoc texlive-xetex texlive-collection-langkorean")
        print()
        print("  방법 2) weasyprint (Python)")
        print("    pip install markdown weasyprint")
        print()
        print("  방법 3) md2pdf (Python, 간단)")
        print("    pip install md2pdf")
        print()
        sys.exit(1)


if __name__ == "__main__":
    main()
