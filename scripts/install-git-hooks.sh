#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
hooks_src_dir="$repo_root/.githooks"
hooks_target_dir="$repo_root/.git/hooks"

if [[ ! -d "$repo_root/.git" ]]; then
  echo "Not a git repository: $repo_root" >&2
  exit 1
fi

if [[ ! -d "$hooks_src_dir" ]]; then
  echo "Hooks source directory missing: $hooks_src_dir" >&2
  exit 1
fi

mkdir -p "$hooks_target_dir"
cp "$hooks_src_dir/commit-msg" "$hooks_target_dir/commit-msg"
chmod +x "$hooks_target_dir/commit-msg"

echo "Installed commit-msg hook at $hooks_target_dir/commit-msg"
