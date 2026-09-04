#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="${1:-$HOME/Downloads/christhebarber-portal}"
PARTIAL="$PROJECT_DIR/partials/footer.html"
STYLE_FILE="$PROJECT_DIR/assets/common-footer.css"

fail(){ printf 'ERROR: %s\n' "$*" >&2; exit 1; }
[[ -s "$PARTIAL" ]] || fail "Missing footer partial: $PARTIAL"
[[ -s "$STYLE_FILE" ]] || fail "Missing footer stylesheet: $STYLE_FILE"

PAGES=(
  index.html
  about.html
  work.html
  booking.html
  policy.html
  reviews.html
  contact.html
)

BACKUP_DIR="$PROJECT_DIR/footer-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

python3 - "$PROJECT_DIR" "$PARTIAL" "$BACKUP_DIR" "${PAGES[@]}" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])
partial = Path(sys.argv[2]).read_text(encoding="utf-8").strip()
backup = Path(sys.argv[3])
pages = sys.argv[4:]

for page_name in pages:
    page = root / page_name
    if not page.is_file():
        raise SystemExit(f"ERROR: required page not found: {page_name}")

    html = page.read_text(encoding="utf-8")
    (backup / page_name).write_text(html, encoding="utf-8")

    common_pattern = re.compile(
        r'<!-- COMMON_FOOTER_START -->.*?<!-- COMMON_FOOTER_END -->',
        flags=re.S,
    )

    if common_pattern.search(html):
        html = common_pattern.sub(partial, html, count=1)
    else:
        footer_pattern = re.compile(r'<footer\b.*?</footer>', flags=re.S | re.I)
        if footer_pattern.search(html):
            html = footer_pattern.sub(partial, html, count=1)
        elif '</body>' in html:
            html = html.replace('</body>', partial + '\n</body>', 1)
        else:
            raise SystemExit(f"ERROR: no footer or body end found in {page_name}")

    if '/assets/common-footer.css' not in html:
        if '</head>' not in html:
            raise SystemExit(f"ERROR: no head end found in {page_name}")
        html = html.replace(
            '</head>',
            '  <link rel="stylesheet" href="/assets/common-footer.css">\n</head>',
            1,
        )

    body_match = re.search(r'<body\b([^>]*)>', html, flags=re.I)
    if body_match and 'id=' not in body_match.group(1):
        html = html[:body_match.start()] + re.sub(
            r'<body\b', '<body id="top"', body_match.group(0), count=1, flags=re.I
        ) + html[body_match.end():]

    # Add a tiny inline year updater once per page, preserving no-JS fallback year.
    year_script = '<script>document.querySelectorAll("[data-current-year]").forEach(function(e){e.textContent=new Date().getFullYear()})</script>'
    if 'data-current-year' in html and 'querySelectorAll("[data-current-year]")' not in html:
        html = html.replace('</body>', year_script + '\n</body>', 1)

    page.write_text(html, encoding="utf-8")

    saved = page.read_text(encoding="utf-8")
    required = [
        'COMMON_FOOTER_START',
        '/assets/common-footer.css',
        'successfavorsthewellgroomed@gmail.com',
        '/booking.html',
    ]
    missing = [value for value in required if value not in saved]
    if missing:
        raise SystemExit(f"ERROR: {page_name} missing: {', '.join(missing)}")

print("Common footer synchronized to:")
for page in pages:
    print(" -", page)
PY

printf '\nBackup directory: %s\n' "$BACKUP_DIR"
printf 'Common footer synchronization completed.\n'
printf 'Preview: cd "%s" && ./serve-local.sh\n' "$PROJECT_DIR"
