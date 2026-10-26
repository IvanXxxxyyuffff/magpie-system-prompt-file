#!/bin/sh
# Install magpie-system-prompt-file on macOS or Linux.
#
#   sh install.sh
#
# It copies the package into ~/.config/magpie/plugins/magpie-system-prompt-file,
# creates the prompt file if it is missing, and registers the plugin.

set -e

MAGPIE=${MAGPIE:-magpie}
command -v "$MAGPIE" >/dev/null 2>&1 || MAGPIE=/Applications/magpie.app/Contents/MacOS/magpie
[ -x "$MAGPIE" ] || { echo "magpie not found; set MAGPIE=/path/to/magpie" >&2; exit 1; }

SOURCE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
HOME_DIR="$HOME/.config/magpie"
PACKAGE="$HOME_DIR/plugins/magpie-system-prompt-file"
PROMPT_DIR="$HOME_DIR/prompts"
PROMPT_FILE="$PROMPT_DIR/system.md"

mkdir -p "$HOME_DIR/plugins" "$PROMPT_DIR"
mkdir -p "$PACKAGE"
cp "$SOURCE/package.json" "$SOURCE/system-prompt.hooks.mjs" "$PACKAGE/"
[ -f "$SOURCE/README.md" ] && cp "$SOURCE/README.md" "$PACKAGE/"

# The prompt file is created only when the user has none yet, so an existing
# one is never overwritten. It ships empty: the persona is the user's own.
if [ ! -f "$PROMPT_FILE" ]; then
  cat > "$PROMPT_FILE" <<'EOF'
---
title: system
---

<!-- Put your own system prompt (persona) here.
     This file is read on every request, so editing it takes effect at once,
     with no reload and no restart. Markdown and plain text both work. -->
EOF
  echo "created $PROMPT_FILE"
fi

"$MAGPIE" plugin add "$PACKAGE"
"$MAGPIE" plugin options "$PACKAGE" '{
  "prompt_file": "~/.config/magpie/prompts/system.md",
  "override": true,
  "position": "append",
  "strip_frontmatter": true,
  "gatewayTimeoutMs": 3000
}'

echo ""
echo "installed. edit $PROMPT_FILE and it takes effect on the next request."
