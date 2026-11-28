#!/bin/bash
# install-cursor-pluglins.sh [plugin ...] — install agent plugins from cursor/plugins upstream.
#
# Fetches the latest upstream main, syncs each plugin into .agents/plugins/<name>,
# and re-applies the portability fixes documented in AGENTS.md:
#   - drop .cursor-plugin/ (single-tool metadata)
#   - rename the icon asset to the Agent Plugins spec convention (assets/icon.png)
#   - strip Cursor-only `model:` / `is_background:` frontmatter lines from agents/*.md
#   - regenerate cursor-team-kit's root plugin.json (upstream ships none)
# Then registers the installed plugins in .devin/config.json's requiredPlugins
# (merging into the existing file with jq, creating it if missing).
# With no arguments, installs all plugins. Re-running updates them.
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

SYNCED=()
for plugin in "${PLUGINS[@]}"; do
  src="$WORK/upstream/$plugin"
  dst="$PLUGINS_DIR/$plugin"
  [ -d "$src" ] || { echo "!! upstream has no $plugin, skipping" >&2; continue; }
  echo "==> syncing $plugin"
  SYNCED+=("$plugin")

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

  # cursor-team-kit ships no portable manifest; transform the upstream
  # .cursor-plugin/plugin.json into one (inherits upstream metadata as-is,
  # drops Cursor-specific keys, prepends the 1.0.0 $schema)
  if [ "$plugin" = cursor-team-kit ]; then
    jq '
      del(.displayName, .logo, .category, .tags, .skills, .agents, .rules)
      | .version //= "0.0.0"
      | {"$schema": "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json"} + .
    ' "$src/.cursor-plugin/plugin.json" > "$dst/plugin.json"
    echo "    plugin.json transformed from upstream at version $(jq -r .version "$dst/plugin.json")"
  fi
done

# Register the installed plugins in .devin/config.json's requiredPlugins.
# Merge with jq so unrelated keys already in the file are preserved;
# create the file if it does not exist.
REPO_ROOT="$(cd "$PLUGINS_DIR/../.." && pwd)"
CONFIG="$REPO_ROOT/.devin/config.json"
if [ "${#SYNCED[@]}" -gt 0 ]; then
  echo "==> registering plugins in .devin/config.json"
  mkdir -p "$REPO_ROOT/.devin"
  paths_json="$(printf '%s\n' "${SYNCED[@]}" | jq -R '"./.agents/plugins/\(.)"' | jq -s .)"
  if [ -f "$CONFIG" ]; then
    jq --argjson paths "$paths_json" \
      '.requiredPlugins = (((.requiredPlugins // []) + $paths) | unique)' \
      "$CONFIG" > "$CONFIG.tmp"
    mv "$CONFIG.tmp" "$CONFIG"
  else
    jq -n --argjson paths "$paths_json" '{requiredPlugins: $paths}' > "$CONFIG"
  fi
fi

echo "==> done. verify with: devin skills list | grep -c '^  /'"
