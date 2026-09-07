#!/bin/bash
# Double-click in Finder. Keep the Terminal window open so errors remain visible.
cd "$(dirname "$0")" || exit 1
./scripts/install_ios.sh "$@"
result=$?
if [[ -t 0 ]]; then
  printf '\n按回车关闭此窗口…'
  read -r unused
fi
exit "$result"
