#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
hooks_src_dir="$repo_root/.githooks"

if [[ ! -d "$repo_root/.git" ]]; then
  echo "Not a git repository: $repo_root" >&2
  exit 1
fi

if [[ ! -d "$hooks_src_dir" ]]; then
  echo "Hooks source directory missing: $hooks_src_dir" >&2
  exit 1
fi

chmod +x "$hooks_src_dir/commit-msg"
git -C "$repo_root" config core.hooksPath .githooks

echo "Installed repo hook path: .githooks"
echo "Active commit-msg hook: $hooks_src_dir/commit-msg"
