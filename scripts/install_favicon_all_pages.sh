#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT_DIR="${1:-$HOME/Downloads/christhebarber-portal}"
LOGO_FILE="$PROJECT_DIR/assets/images/sftwg-logo.png"
FAVICON_DIR="$PROJECT_DIR/assets/favicon"

fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

command -v sips >/dev/null 2>&1 ||
  fail "macOS sips utility is required."

[[ -s "$LOGO_FILE" ]] ||
  fail "SFTWG logo was not found: $LOGO_FILE"

PAGES=(
  index.html
  about.html
  work.html
  booking.html
  contact.html
  policy.html
  reviews.html
)

for PAGE in "${PAGES[@]}"; do
  [[ -s "$PROJECT_DIR/$PAGE" ]] ||
    fail "Required page is missing: $PAGE"
done

TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$PROJECT_DIR/favicon-backup-$TIMESTAMP"

mkdir -p "$BACKUP_DIR"
mkdir -p "$FAVICON_DIR"

for PAGE in "${PAGES[@]}"; do
  cp "$PROJECT_DIR/$PAGE" "$BACKUP_DIR/$PAGE"
done

if [[ -s "$PROJECT_DIR/site.webmanifest" ]]; then
  cp "$PROJECT_DIR/site.webmanifest" \
    "$BACKUP_DIR/site.webmanifest"
fi

echo "Creating favicon assets with macOS sips..."

sips \
  --resampleHeightWidth 16 16 \
  "$LOGO_FILE" \
  --out "$FAVICON_DIR/favicon-16x16.png" \
  >/dev/null

sips \
  --resampleHeightWidth 32 32 \
  "$LOGO_FILE" \
  --out "$FAVICON_DIR/favicon-32x32.png" \
  >/dev/null

sips \
  --resampleHeightWidth 180 180 \
  "$LOGO_FILE" \
  --out "$FAVICON_DIR/apple-touch-icon.png" \
  >/dev/null

sips \
  --resampleHeightWidth 192 192 \
  "$LOGO_FILE" \
  --out "$FAVICON_DIR/android-chrome-192x192.png" \
  >/dev/null

sips \
  --resampleHeightWidth 512 512 \
  "$LOGO_FILE" \
  --out "$FAVICON_DIR/android-chrome-512x512.png" \
  >/dev/null

# Use the standards-compliant PNG favicon as the primary icon.
# A separate ICO file is unnecessary for modern browsers.
cp "$FAVICON_DIR/favicon-32x32.png" \
  "$PROJECT_DIR/favicon.png"

cat > "$PROJECT_DIR/site.webmanifest" <<'JSON'
{
  "name": "Chris Fleming The Barber",
  "short_name": "SFTWG",
  "description": "Professional appointment-based barbering in Roanoke, Virginia.",
  "start_url": "/index.html",
  "display": "standalone",
  "background_color": "#111315",
  "theme_color": "#111315",
  "icons": [
    {
      "src": "/assets/favicon/android-chrome-192x192.png",
      "sizes": "192x192",
      "type": "image/png"
    },
    {
      "src": "/assets/favicon/android-chrome-512x512.png",
      "sizes": "512x512",
      "type": "image/png"
    }
  ]
}
JSON

python3 - "$PROJECT_DIR" "${PAGES[@]}" <<'PY'
from pathlib import Path
import re
import sys

project_dir = Path(sys.argv[1])
pages = sys.argv[2:]

favicon_markup = """<!-- SFTWG_FAVICON_START -->
/assets/favicon/favicon-32x32.png
/assets/favicon/favicon-16x16.png
/favicon.png
/assets/favicon/apple-touch-icon.png
/site.webmanifest
<meta name="theme-color" content="#111315">
<!-- SFTWG_FAVICON_END -->"""

pattern = re.compile(
    r"<!-- SFTWG_FAVICON_START -->.*?"
    r"<!-- SFTWG_FAVICON_END -->",
    flags=re.S,
)

for page_name in pages:
    path = project_dir / page_name
    html = path.read_text(encoding="utf-8")

    if pattern.search(html):
        html = pattern.sub(
            favicon_markup,
            html,
            count=1,
        )
    else:
        if "</head>" not in html:
            raise SystemExit(
                f"ERROR: </head> was not found in {page_name}"
            )

        html = html.replace(
            "</head>",
            favicon_markup + "\n</head>",
            1,
        )

    path.write_text(html, encoding="utf-8")

    saved = path.read_text(encoding="utf-8")

    required = [
        "SFTWG_FAVICON_START",
        "/assets/favicon/favicon-32x32.png",
        "/assets/favicon/favicon-16x16.png",
        "/assets/favicon/apple-touch-icon.png",
        "/site.webmanifest",
    ]

    missing = [
        value
        for value in required
        if value not in saved
    ]

    if missing:
        raise SystemExit(
            f"ERROR: {page_name} is missing: "
            + ", ".join(missing)
        )

    if saved.count("SFTWG_FAVICON_START") != 1:
        raise SystemExit(
            f"ERROR: Duplicate favicon metadata in {page_name}"
        )

    print(f"Updated favicon metadata: {page_name}")
PY

for FILE in \
  favicon-16x16.png \
  favicon-32x32.png \
  apple-touch-icon.png \
  android-chrome-192x192.png \
  android-chrome-512x512.png
do
  [[ -s "$FAVICON_DIR/$FILE" ]] ||
    fail "Favicon asset was not created: $FILE"
done

[[ -s "$PROJECT_DIR/favicon.png" ]] ||
  fail "Root favicon.png was not created."

[[ -s "$PROJECT_DIR/site.webmanifest" ]] ||
  fail "site.webmanifest was not created."

echo
echo "Favicon installed on all seven pages."
echo "Backup: $BACKUP_DIR"
echo "Assets: $FAVICON_DIR"
echo "Git: skipped intentionally"
