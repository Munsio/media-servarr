#!/usr/bin/env bash

# Render a chart at two different git refs and diff the rendered Kubernetes
# manifests. Useful for confirming a chart conversion (e.g.
# media-servarr-base -> bjw-s/app-template) doesn't change resource identity
# (names, namespaces, PVC specs, etc.).
#
# Old and new refs get separate values files by default, since the whole
# point of a schema conversion is that the values shape *changes* across
# that boundary — a value meaningful under the old schema (e.g.
# `persistentVolumeClaims.<chart>-config.storageClassName`) is silently
# ignored by Helm if handed to the new schema's chart (which expects
# `app-template.persistence.config.storageClass` instead), and vice versa.
# Passing the same file for both is fine when both refs share a schema (e.g.
# diffing two already-converted commits) — that's why a single shared file
# is still accepted as shorthand.
#
# Besides printing a plain unified diff to stdout, this also leaves the two
# renders behind as an old-commit + uncommitted-new-version in a small git
# repo, so any git-aware diff tool (lazygit, an editor's git panel, `git
# diff`, `delta`, etc.) can show a rich diff view instead of the raw text
# dump. The path to that repo is printed at the end.
#
# Usage: ./scripts/diff-chart-render.sh <chart> <old-ref> <new-ref> [old-values-file] [new-values-file]
#        (omit both values files, or pass just one to use it for both refs)
#
# Requires: helm, git (run inside `nix develop` if you're using this repo's
# flake devShell for helm).
#
# Examples:
#   ./scripts/diff-chart-render.sh radarr HEAD~5 HEAD
#   ./scripts/diff-chart-render.sh radarr HEAD~5 HEAD my-values.yaml
#   ./scripts/diff-chart-render.sh radarr HEAD~5 HEAD old-schema-values.yaml new-schema-values.yaml
#
# For a rich diff view, point lazygit or an editor's git panel at the repo
# path this script prints at the end, e.g.:
#   lazygit -p /tmp/media-servarr-chart-diff/radarr
#   zeditor /tmp/media-servarr-chart-diff/radarr

set -euo pipefail

if [[ $# -lt 3 || $# -gt 5 ]]; then
  echo "Usage: $0 <chart> <old-ref> <new-ref> [old-values-file] [new-values-file]" >&2
  exit 2
fi

if ! command -v helm &> /dev/null; then
  echo "helm could not be found. Run this inside 'nix develop' or otherwise put helm on PATH." >&2
  exit 1
fi

CHART=$1
OLD_REF=$2
NEW_REF=$3
OLD_VALUES_FILE=${4:-}
NEW_VALUES_FILE=${5:-$OLD_VALUES_FILE}

for f in "$OLD_VALUES_FILE" "$NEW_VALUES_FILE"; do
  if [[ -n "$f" && ! -f "$f" ]]; then
    echo "Values file not found: $f" >&2
    exit 2
  fi
done
[[ -n "$OLD_VALUES_FILE" ]] && OLD_VALUES_FILE=$(realpath "$OLD_VALUES_FILE")
[[ -n "$NEW_VALUES_FILE" ]] && NEW_VALUES_FILE=$(realpath "$NEW_VALUES_FILE")

REPO_ROOT=$(git rev-parse --show-toplevel)
WORKDIR=$(mktemp -d)

cleanup() {
  git -C "$REPO_ROOT" worktree remove --force "$WORKDIR/old" 2>/dev/null || true
  git -C "$REPO_ROOT" worktree remove --force "$WORKDIR/new" 2>/dev/null || true
  rm -rf "$WORKDIR"
}
trap cleanup EXIT

render() {
  local ref=$1 dir=$2 out=$3 values_file=$4

  git -C "$REPO_ROOT" worktree add -q --detach "$dir" "$ref"
  helm dependency update "$dir/charts/$CHART" > /dev/null

  if [[ -n "$values_file" ]]; then
    helm template "$CHART" "$dir/charts/$CHART" -f "$values_file" > "$out"
  else
    helm template "$CHART" "$dir/charts/$CHART" > "$out"
  fi
}

echo "Rendering '$CHART' at $OLD_REF..." >&2
render "$OLD_REF" "$WORKDIR/old" "$WORKDIR/old.yaml" "$OLD_VALUES_FILE"

echo "Rendering '$CHART' at $NEW_REF..." >&2
render "$NEW_REF" "$WORKDIR/new" "$WORKDIR/new.yaml" "$NEW_VALUES_FILE"

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
