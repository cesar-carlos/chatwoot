#!/usr/bin/env bash
# Diff índice oficial Evolution vs entradas em documentation-links.md
set -euo pipefail

LLMS_URL="${LLMS_URL:-https://docs.evolutionfoundation.com.br/llms.txt}"
DOC_LINKS="$(dirname "$0")/documentation-links.md"

echo "=== Evolution API pages in llms.txt (not in documentation-links.md) ==="
curl -fsSL "$LLMS_URL" \
  | rg -o 'https://docs\.evolutionfoundation\.com\.br/evolution-api/[^)]+\.md' \
  | sed 's|\.md$||' \
  | sort -u \
  | while read -r url; do
      slug="${url##*/}"
      if ! rg -q "$slug" "$DOC_LINKS" 2>/dev/null; then
        echo "  MISSING: $url"
      fi
    done

echo ""
echo "=== Slugs in documentation-links.md (sample check) ==="
rg -o 'evolution-api/[a-z0-9./-]+' "$DOC_LINKS" | sort -u | head -20
echo "  ... (truncated)"

echo ""
echo "Done. Update documentation-links.md for any MISSING URLs."
