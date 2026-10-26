#!/bin/sh
# Roll the machine back to the state before magpie-system-prompt-file.
#
#   sh ROLLBACK.sh
#
# It removes this plugin from magpie's plugin list and restores the
# plugins.json that was in place before the change. The upstream
# @magpie-community/middleware-system-prompt package is left as it was:
# its entry was already off before this change, and this script puts the
# list back byte for byte.

set -e

MAGPIE=/Applications/magpie.app/Contents/MacOS/magpie
PLUGINS=/Users/mac/.config/magpie/plugins.json
PKG=/Users/mac/Documents/Codex/2026-10-26/gai/outputs/magpie-system-prompt-file
BACKUP=/Users/mac/.config/magpie/plugins.json.bak.pre-system-prompt-file

# 1. take the plugin out of magpie
if [ -x "$MAGPIE" ]; then
  "$MAGPIE" plugin rm "$PKG" || true
fi

# 2. put the plugin list back
if [ -f "$BACKUP" ]; then
  cp "$BACKUP" "$PLUGINS"
  echo "restored $PLUGINS from $BACKUP"
else
  echo "no backup at $BACKUP; leaving $PLUGINS alone" >&2
fi

# 3. report
echo "--- plugins.json now:"
cat "$PLUGINS"
