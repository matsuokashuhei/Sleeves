#!/bin/bash
# update.sh [plugin ...] — re-vendor agent plugins from cursor/plugins upstream.
#
# Fetches the latest upstream main, syncs each plugin into .agents/plugins/<name>,
# and re-applies the portability fixes documented in AGENTS.md:
#   - drop .cursor-plugin/ (single-tool metadata)
#   - rename the icon asset to the Agent Plugins spec convention (assets/icon.png)
#   - strip Cursor-only `model:` / `is_background:` frontmatter lines from agents/*.md
#   - regenerate cursor-team-kit's root plugin.json (upstream ships none)
# With no arguments, updates all vendored plugins.
set -euo pipefail

UPSTREAM_REPO="https://github.com/cursor/plugins.git"
PLUGINS_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ $# -eq 0 ]; then
  PLUGINS=(cursor-team-kit pstack)
else
  PLUGINS=("$@")
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

echo "==> fetching upstream cursor/plugins (sparse)"
git clone --quiet --depth 1 --filter=blob:none --sparse "$UPSTREAM_REPO" "$WORK/upstream"
git -C "$WORK/upstream" sparse-checkout set "${PLUGINS[@]}"
UPSTREAM_SHA="$(git -C "$WORK/upstream" rev-parse --short HEAD)"
echo "    upstream HEAD: $UPSTREAM_SHA"

for plugin in "${PLUGINS[@]}"; do
  src="$WORK/upstream/$plugin"
  dst="$PLUGINS_DIR/$plugin"
  [ -d "$src" ] || { echo "!! upstream has no $plugin, skipping" >&2; continue; }
  echo "==> syncing $plugin"

  rsync -a --delete --exclude='.cursor-plugin' "$src/" "$dst/"

  # Icon: spec convention is assets/icon.<ext>
  for icon in avatar.png logo.png; do
    [ -f "$dst/assets/$icon" ] && mv "$dst/assets/$icon" "$dst/assets/icon.png"
  done

  # Strip Cursor-only frontmatter (invalid model slugs, is_background) from agents
  for agent in "$dst"/agents/*.md; do
    [ -f "$agent" ] || continue
    sed -i '' -e '/^model: /d' -e '/^is_background: /d' "$agent"
  done

  # cursor-team-kit ships no portable manifest; regenerate it with the upstream version
  if [ "$plugin" = cursor-team-kit ]; then
    version="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$src/.cursor-plugin/plugin.json" | head -1)"
    cat > "$dst/plugin.json" <<EOF
{
  "\$schema": "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json",
  "name": "cursor-team-kit",
  "version": "${version:-0.0.0}",
  "description": "Internal engineering team workflows for CI, code review, shipping, control-cli, control-ui, verify-this, test reliability, code cleanup, and work summaries. Designed to work without requiring third-party service integrations.",
  "author": {
    "name": "Eric Zakariasson"
  },
  "homepage": "https://github.com/cursor/plugins",
  "repository": "https://github.com/cursor/plugins",
  "license": "MIT",
  "keywords": [
    "ci",
    "code-review",
    "shipping",
    "testing",
    "verification",
    "local-automation"
  ]
}
EOF
    echo "    plugin.json regenerated at version ${version:-unknown}"
  fi
done

echo "==> done. verify with: devin skills list | grep -c '^  /'"
echo "    then review: git diff .agents/plugins/"
