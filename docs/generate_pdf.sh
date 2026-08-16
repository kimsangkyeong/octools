#!/bin/bash
#
# OCP 관리도구 (octools) - PDF 생성 스크립트
# Markdown 문서를 PDF로 변환한다.
#
# 사전 요구사항:
#   pandoc 설치: sudo dnf install pandoc -y (또는 apt install pandoc)
#   LaTeX 설치: sudo dnf install texlive-xetex texlive-collection-langkorean -y
#   또는 wkhtmltopdf 사용: sudo dnf install wkhtmltopdf -y
#
# 사용법:
#   chmod +x docs/generate_pdf.sh
#   ./docs/generate_pdf.sh
#

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_DIR="${SCRIPT_DIR}/pdf"

# 출력 디렉토리 생성
mkdir -p "$OUTPUT_DIR"

echo "==========================================="
echo "  OCP 관리도구 - PDF 문서 생성"
echo "==========================================="
echo ""

# 변환 방법 선택
if command -v pandoc &> /dev/null; then
    echo "[INFO] pandoc을 사용하여 PDF를 생성합니다."
    CONVERTER="pandoc"
elif command -v wkhtmltopdf &> /dev/null; then
    echo "[INFO] wkhtmltopdf를 사용하여 PDF를 생성합니다."
    CONVERTER="wkhtmltopdf"
else
    echo "[ERROR] PDF 변환 도구가 설치되어 있지 않습니다."
    echo ""
    echo "다음 중 하나를 설치하세요:"
    echo ""
    echo "  방법 1) pandoc + xelatex (한글 지원 우수)"
    echo "    RHEL/CentOS: sudo dnf install pandoc texlive-xetex texlive-collection-langkorean"
    echo "    Ubuntu/Debian: sudo apt install pandoc texlive-xetex fonts-nanum"
    echo ""
    echo "  방법 2) wkhtmltopdf (간단 설치)"
    echo "    RHEL/CentOS: sudo dnf install wkhtmltopdf"
    echo "    Ubuntu/Debian: sudo apt install wkhtmltopdf"
    echo ""
    echo "  방법 3) Python markdown-pdf (pip)"
    echo "    pip install md2pdf"
    echo ""
    exit 1
fi

# 변환할 파일 목록
MD_FILES=(
    "requirements.md"
    "architecture.md"
    "server_setup_guide.md"
)

# 파일별 변환
for md_file in "${MD_FILES[@]}"; do
    input_path="${SCRIPT_DIR}/${md_file}"
    output_file="${md_file%.md}.pdf"
    output_path="${OUTPUT_DIR}/${output_file}"

    if [ ! -f "$input_path" ]; then
        echo "[SKIP] ${md_file} - 파일 없음"
        continue
    fi

    echo -n "[변환] ${md_file} → pdf/${output_file} ... "

    if [ "$CONVERTER" = "pandoc" ]; then
        # pandoc으로 변환 (한글 폰트 지정)
        pandoc "$input_path" \
            -o "$output_path" \
            --pdf-engine=xelatex \
            -V mainfont="NanumGothic" \
            -V monofont="NanumGothicCoding" \
            -V geometry:margin=2.5cm \
            -V fontsize=10pt \
            --highlight-style=tango \
            --toc \
            -V toc-title="목차" \
            2>/dev/null

        if [ $? -eq 0 ]; then
            echo "완료"
        else
            # xelatex 실패 시 기본 폰트로 재시도
            pandoc "$input_path" \
                -o "$output_path" \
                --pdf-engine=xelatex \
                -V mainfont="DejaVu Sans" \
                -V monofont="DejaVu Sans Mono" \
                -V geometry:margin=2.5cm \
                2>/dev/null
            if [ $? -eq 0 ]; then
                echo "완료 (기본 폰트 사용)"
            else
                echo "실패"
            fi
        fi

    elif [ "$CONVERTER" = "wkhtmltopdf" ]; then
        # markdown → html → pdf
        # 먼저 pandoc이 없으면 간이 변환
        if command -v pandoc &> /dev/null; then
            pandoc "$input_path" -o "/tmp/${md_file%.md}.html" 2>/dev/null
        else
            # 간이 HTML 생성 (Python 사용)
            python3 -c "
import sys
try:
    import markdown
    with open('$input_path', 'r') as f:
        content = f.read()
    html = markdown.markdown(content, extensions=['tables', 'fenced_code'])
    with open('/tmp/${md_file%.md}.html', 'w') as f:
        f.write('<html><head><meta charset=\"utf-8\"><style>body{font-family:sans-serif;margin:40px;}table{border-collapse:collapse;width:100%;}th,td{border:1px solid #ddd;padding:8px;text-align:left;}pre{background:#f4f4f4;padding:15px;border-radius:5px;overflow-x:auto;}code{font-family:monospace;}</style></head><body>')
        f.write(html)
        f.write('</body></html>')
except ImportError:
    print('markdown 패키지가 필요합니다: pip install markdown')
    sys.exit(1)
" 2>/dev/null
        fi

        wkhtmltopdf --encoding utf-8 "/tmp/${md_file%.md}.html" "$output_path" 2>/dev/null
        if [ $? -eq 0 ]; then
            echo "완료"
        else
            echo "실패"
        fi
        rm -f "/tmp/${md_file%.md}.html"
    fi
done

echo ""
echo "==========================================="
echo "  생성된 PDF 파일:"
echo "==========================================="
ls -la "$OUTPUT_DIR"/*.pdf 2>/dev/null || echo "  (생성된 파일 없음)"
echo ""
