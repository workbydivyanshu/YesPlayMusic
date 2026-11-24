#!/usr/bin/env bash
# ==============================================================================
# YesPlayMusic Upstream Sync Checker
# Fetches upstream/main, compares against the recorded baseline marker,
# and outputs an automated commit triage matrix.
# ==============================================================================

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_DIR"

# Ensure upstream remote exists
if ! git remote get-url upstream >/dev/null 2>&1; then
  echo "Adding upstream remote: https://github.com/qier222/YesPlayMusic.git"
  git remote add upstream https://github.com/qier222/YesPlayMusic.git
fi

echo "Fetching upstream/main..."
git fetch upstream main --quiet

# Extract marker from AGENTS.md (e.g. `bb8912f`)
MARKER=$(grep -E 'The current reviewed upstream baseline marker is \*\*`[0-9a-f]+`\*\*' AGENTS.md | sed -E 's/.*`([0-9a-f]+)`.*/\1/' || true)
if [ -z "$MARKER" ]; then
  MARKER="bb8912f"
fi

UPSTREAM_TIP=$(git rev-parse upstream/main)
UPSTREAM_SHORT=$(git rev-parse --short upstream/main)

echo "=================================================================="
echo "YesPlayMusic Upstream Sync Status"
echo "Baseline Marker : $MARKER"
echo "Upstream Tip    : $UPSTREAM_SHORT ($UPSTREAM_TIP)"
echo "=================================================================="

NEW_COUNT=$(git rev-list --count "$MARKER..upstream/main")

if [ "$NEW_COUNT" -eq 0 ]; then
  echo "✓ Upstream is completely in sync with baseline marker ($MARKER)."
  exit 0
fi

echo "Found $NEW_COUNT new upstream commit(s) since marker $MARKER:"
echo ""
echo "| Action | Upstream SHA | Subject |"
echo "|---|---|---|"

git log --reverse --oneline "$MARKER..upstream/main" | while read -r sha subject; do
  action="PORT"
  lower_subject=$(echo "$subject" | tr '[:upper:]' '[:lower:]')

  # Unconditional SKIP rules
  if [[ "$lower_subject" =~ analytics|telemetry|ga4|landing|deploy|cloudflare|pull\ request ]]; then
    action="**SKIP**"
  elif [[ "$lower_subject" =~ player|now\ playing|lyrics|repeat|state ]]; then
    action="**ADAPT**"
  else
    action="**PORT**"
  fi

  echo "| $action | \`$sha\` | $subject |"
done

echo ""
echo "Triage Summary: Inspect commits above before adapting to 'mainline'."
