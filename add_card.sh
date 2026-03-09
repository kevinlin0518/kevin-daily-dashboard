#!/bin/bash

# ============================================
# Add Business Card — 新增名片
# Usage: add_card.sh <image_path> [category]
# Categories: supplier | cooling | export
# ============================================

DASH_DIR="$HOME/Desktop/XYZ/xyz_daily_dashboard"
CARDS_DIR="$DASH_DIR/cards"
IMAGES_DIR="$CARDS_DIR/images"
JSON_FILE="$CARDS_DIR/cards.json"
SWIFT_SCRIPT="$DASH_DIR/process_card.swift"

if [ -z "$1" ]; then
    echo "Usage: add_card.sh <image_path> [category]"
    echo "Categories: supplier | cooling | export"
    exit 1
fi

INPUT_IMAGE="$1"
CATEGORY="${2:-}"

if [ ! -f "$INPUT_IMAGE" ]; then
    echo "Error: File not found: $INPUT_IMAGE"
    exit 1
fi

mkdir -p "$IMAGES_DIR"
[ ! -f "$JSON_FILE" ] && echo "[]" > "$JSON_FILE"

# ============================================
# Calculate next card number
# ============================================
NEXT_NUM=1
if ls "$IMAGES_DIR"/*.jpg 1>/dev/null 2>&1; then
    MAX_NUM=$(ls "$IMAGES_DIR"/*.jpg | sed 's/.*\///' | sed 's/\.jpg//' | sort -n | tail -1)
    NEXT_NUM=$((10#$MAX_NUM + 1))
fi
CARD_ID=$(printf "%02d" $NEXT_NUM)
echo "Card #$CARD_ID"

# ============================================
# Convert HEIC to JPG if needed
# ============================================
TMP_DIR=$(mktemp -d)
WORK_IMAGE="$TMP_DIR/input.jpg"

EXT=$(echo "${INPUT_IMAGE##*.}" | tr '[:upper:]' '[:lower:]')
if [ "$EXT" = "heic" ] || [ "$EXT" = "heif" ]; then
    echo "Converting HEIC → JPG..."
    sips -s format jpeg "$INPUT_IMAGE" --out "$WORK_IMAGE" 2>/dev/null
else
    cp "$INPUT_IMAGE" "$WORK_IMAGE"
fi

# ============================================
# Process image + OCR via Swift
# ============================================
OUTPUT_IMAGE="$IMAGES_DIR/${CARD_ID}.jpg"
echo "Processing image..."

OCR_TEXT=$(swift "$SWIFT_SCRIPT" "$WORK_IMAGE" "$OUTPUT_IMAGE" 2>/dev/null)

if [ ! -f "$OUTPUT_IMAGE" ]; then
    echo "Error: Image processing failed"
    rm -rf "$TMP_DIR"
    exit 1
fi

echo "--- OCR Result ---"
echo "$OCR_TEXT"
echo "------------------"

# ============================================
# Auto-extract fields via Python
# ============================================
EXTRACTED=$(python3 << PYEOF
import re, json

ocr = """$OCR_TEXT"""
lines = [l.strip() for l in ocr.strip().split('\n') if l.strip()]

# Email
email = ''
for line in lines:
    m = re.search(r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}', line)
    if m:
        email = m.group(0)
        break

# Phone — match various formats
phone = ''
phone_patterns = [
    r'[\+]?[\d][\d\s\-().]{6,}[\d]',
    r'(?:TEL|Tel|tel|T|Phone|phone|電話|手機|行動)[:\s]*([+\d\s\-().]{7,})',
]
for line in lines:
    for pat in phone_patterns:
        m = re.search(pat, line)
        if m:
            phone = m.group(1) if m.lastindex else m.group(0)
            phone = phone.strip()
            break
    if phone:
        break

# Company — look for keywords
company = ''
company_kw = ['公司', '有限', '股份', '企業', '集團', '工業', '實業',
              'Corp', 'Inc', 'Ltd', 'LLC', 'Co.', 'Group', 'GmbH',
              'International', 'Industries', 'Manufacturing', 'Technology']
for line in lines:
    if any(kw.lower() in line.lower() for kw in company_kw):
        company = line
        break

# Title — look for job title keywords
title = ''
title_kw = ['經理', '總監', '主管', '總經理', '副總', '董事', '處長', '課長',
            '組長', '專員', '業務', '工程師', '設計師', '顧問', '協理', '襄理',
            'Manager', 'Director', 'VP', 'President', 'CEO', 'CTO', 'CFO',
            'Engineer', 'Supervisor', 'Officer', 'Representative', 'Sales',
            'General Manager', 'Chairman', 'Consultant', 'Specialist', 'Lead']
for line in lines:
    if any(kw.lower() in line.lower() for kw in title_kw):
        # Don't use company line as title
        if line != company:
            title = line
            break

# Name — heuristic: short line (2-4 CJK chars) not matching other fields,
# or line with CJK name pattern
name = ''
used = {company, title, email, phone}
for line in lines:
    if line in used or not line:
        continue
    # Check if line looks like email/phone/address/url
    if '@' in line or re.search(r'[\d]{5,}', line) or 'www' in line.lower() or 'http' in line.lower():
        continue
    if re.search(r'[路街巷號弄樓F]', line):
        continue
    # CJK name: 2-4 characters, mostly CJK
    cjk = len(re.findall(r'[\u4e00-\u9fff]', line))
    if 2 <= cjk <= 4 and len(line) <= 8:
        name = line
        break
    # English name pattern: First Last or First M. Last
    if re.match(r'^[A-Z][a-z]+ [A-Z]', line) and len(line) < 30:
        name = line
        break

result = {
    'company': company,
    'title': title,
    'name': name,
    'email': email,
    'phone': phone
}
print(json.dumps(result, ensure_ascii=False))
PYEOF
)

COMPANY=$(echo "$EXTRACTED" | python3 -c "import sys,json; print(json.load(sys.stdin)['company'])")
TITLE=$(echo "$EXTRACTED" | python3 -c "import sys,json; print(json.load(sys.stdin)['title'])")
NAME=$(echo "$EXTRACTED" | python3 -c "import sys,json; print(json.load(sys.stdin)['name'])")
EMAIL=$(echo "$EXTRACTED" | python3 -c "import sys,json; print(json.load(sys.stdin)['email'])")
PHONE=$(echo "$EXTRACTED" | python3 -c "import sys,json; print(json.load(sys.stdin)['phone'])")

echo "Extracted: company=$COMPANY | name=$NAME | title=$TITLE | email=$EMAIL | phone=$PHONE | category=$CATEGORY"

# ============================================
# Update cards.json
# ============================================
python3 << PYEOF
import json

with open("${JSON_FILE}", "r") as f:
    cards = json.load(f)

cards.append({
    "id": "${CARD_ID}",
    "company": $(python3 -c "import json; print(json.dumps('$COMPANY'))"),
    "title": $(python3 -c "import json; print(json.dumps('$TITLE'))"),
    "name": $(python3 -c "import json; print(json.dumps('$NAME'))"),
    "email": $(python3 -c "import json; print(json.dumps('$EMAIL'))"),
    "phone": $(python3 -c "import json; print(json.dumps('$PHONE'))"),
    "category": "${CATEGORY}",
    "image": "cards/images/${CARD_ID}.jpg"
})

with open("${JSON_FILE}", "w") as f:
    json.dump(cards, f, ensure_ascii=False, indent=2)

print(f"cards.json updated: {len(cards)} cards total")
PYEOF

# ============================================
# Regenerate cards.html
# ============================================
echo "Generating cards.html..."
bash "$DASH_DIR/generate_cards.sh"

# ============================================
# Git push
# ============================================
echo "Pushing to GitHub Pages..."
cd "$DASH_DIR"
git add cards/ cards.html process_card.swift add_card.sh generate_cards.sh 2>/dev/null
git commit -m "Add card #${CARD_ID}" 2>/dev/null
git push origin main 2>/dev/null

rm -rf "$TMP_DIR"

echo "Done! Card #${CARD_ID} added."
osascript -e "display notification \"名片 #${CARD_ID} 已新增\" with title \"名片夾\" sound name \"Glass\""
