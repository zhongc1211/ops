#!/usr/bin/env bash
# 旧入口，保留给习惯直接跑它的人：挡禁用命令的 deny 和 hook 现在只有一套，在 ../claude-deny（PER-89）。
# 旧版的第一个参数（block-disabled-skills.sh 路径）已无用，忽略。
set -euo pipefail
exec bash "$(cd "$(dirname "$0")/../claude-deny" && pwd)/install.sh" --apply
