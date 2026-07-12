#!/usr/bin/env bash

# Render a chart at two different git refs with the same values and diff the
# rendered Kubernetes manifests. Useful for confirming a chart conversion
# (e.g. media-servarr-base -> bjw-s/app-template) doesn't change resource
# identity (names, namespaces, PVC specs, etc.) for a given values file.
#
# Besides printing a plain unified diff to stdout, this also leaves the two
# renders behind as an old-commit + uncommitted-new-version in a small git
# repo, so any git-aware diff tool (lazygit, an editor's git panel, `git
# diff`, `delta`, etc.) can show a rich diff view instead of the raw text
# dump. The path to that repo is printed at the end.
#
# Usage: ./scripts/diff-chart-render.sh <chart> <old-ref> <new-ref> [values-file]
#
# Requires: helm, git (run inside `nix develop` if you're using this repo's
# flake devShell for helm).
#
# Examples:
#   ./scripts/diff-chart-render.sh radarr HEAD~5 HEAD
#   ./scripts/diff-chart-render.sh radarr HEAD~5 HEAD my-values.yaml
#
# For a rich diff view, point lazygit or an editor's git panel at the repo
# path this script prints at the end, e.g.:
#   lazygit -p /tmp/media-servarr-chart-diff/radarr
#   zeditor /tmp/media-servarr-chart-diff/radarr

set -euo pipefail

if [[ $# -lt 3 || $# -gt 4 ]]; then
  echo "Usage: $0 <chart> <old-ref> <new-ref> [values-file]" >&2
  exit 2
fi

if ! command -v helm &> /dev/null; then
  echo "helm could not be found. Run this inside 'nix develop' or otherwise put helm on PATH." >&2
  exit 1
fi

CHART=$1
OLD_REF=$2
NEW_REF=$3
VALUES_FILE=${4:-}

if [[ -n "$VALUES_FILE" && ! -f "$VALUES_FILE" ]]; then
  echo "Values file not found: $VALUES_FILE" >&2
  exit 2
fi
if [[ -n "$VALUES_FILE" ]]; then
  VALUES_FILE=$(realpath "$VALUES_FILE")
fi

REPO_ROOT=$(git rev-parse --show-toplevel)
WORKDIR=$(mktemp -d)

cleanup() {
  git -C "$REPO_ROOT" worktree remove --force "$WORKDIR/old" 2>/dev/null || true
  git -C "$REPO_ROOT" worktree remove --force "$WORKDIR/new" 2>/dev/null || true
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

render() {
  local ref=$1 dir=$2 out=$3

  git -C "$REPO_ROOT" worktree add -q --detach "$dir" "$ref"
  helm dependency update "$dir/charts/$CHART" > /dev/null

  if [[ -n "$VALUES_FILE" ]]; then
    helm template "$CHART" "$dir/charts/$CHART" -f "$VALUES_FILE" > "$out"
  else
    helm template "$CHART" "$dir/charts/$CHART" > "$out"
  fi
}

echo "Rendering '$CHART' at $OLD_REF..." >&2
render "$OLD_REF" "$WORKDIR/old" "$WORKDIR/old.yaml"

echo "Rendering '$CHART' at $NEW_REF..." >&2
render "$NEW_REF" "$WORKDIR/new" "$WORKDIR/new.yaml"

echo "--- diff ($OLD_REF -> $NEW_REF) ---" >&2
diff -u "$WORKDIR/old.yaml" "$WORKDIR/new.yaml" || true

# Also leave the renders behind as a real git working-tree diff, so any
# git-aware tool (lazygit, an editor's git panel, `git diff`, `delta`, ...)
# can show a rich diff view instead of the raw unified-diff text above.
#
# Deliberately NOT under $TMPDIR: `nix develop --command` (how this script's
# own helm dependency is normally satisfied) runs with TMPDIR pointed at a
# per-invocation sandbox dir that's removed the moment that command exits —
# anything written there would vanish before you could open it afterward.
# Plain /tmp is stable across that.
DIFF_REPO="/tmp/media-servarr-chart-diff/$CHART"
rm -rf "$DIFF_REPO"
mkdir -p "$DIFF_REPO"
git -C "$DIFF_REPO" init -q
cp "$WORKDIR/old.yaml" "$DIFF_REPO/rendered.yaml"
git -C "$DIFF_REPO" add rendered.yaml
git -C "$DIFF_REPO" -c user.name="diff-chart-render" -c user.email="diff-chart-render@localhost" \
  commit -q -m "old: $CHART @ $OLD_REF"
cp "$WORKDIR/new.yaml" "$DIFF_REPO/rendered.yaml"

echo >&2
echo "For a rich diff view of the same comparison:" >&2
echo "  lazygit -p $DIFF_REPO" >&2
echo "  zeditor $DIFF_REPO      # or any git-aware editor pointed at this path" >&2
echo "(shows old:$OLD_REF -> new:$NEW_REF as an uncommitted change to rendered.yaml)" >&2
