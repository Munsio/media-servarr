#!/usr/bin/env bash

# Render a chart at two different git refs with the same values and diff the
# rendered Kubernetes manifests. Useful for confirming a chart conversion
# (e.g. media-servarr-base -> bjw-s/app-template) doesn't change resource
# identity (names, namespaces, PVC specs, etc.) for a given values file.
#
# Usage: ./scripts/diff-chart-render.sh <chart> <old-ref> <new-ref> [values-file]
#
# Requires: helm, git (run inside `nix develop` if you're using this repo's
# flake devShell for helm).
#
# Examples:
#   ./scripts/diff-chart-render.sh radarr HEAD~5 HEAD
#   ./scripts/diff-chart-render.sh radarr HEAD~5 HEAD my-values.yaml

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
diff -u "$WORKDIR/old.yaml" "$WORKDIR/new.yaml"
