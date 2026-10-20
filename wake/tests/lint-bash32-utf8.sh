#!/bin/bash
# macOS 自带 /bin/bash 3.2 在 UTF-8 locale 下把紧跟在 $name 后面的全角字符（如 （ ， ： ）的字节
# 当成变量名的一部分，set -u 下直接 unbound variable 退出；要写成 ${name}。
# 本脚本扫 wake/ 和 scripts/ 下的 shell 文件（扩展名 .sh/.bash 或 shebang 是 sh/bash），
# 跳过 # 开头的注释行；有命中就打印「文件:行」并 exit 1。只用 find + LC_ALL=C grep -E，
# /bin/bash 3.2 + BSD grep 和 Linux GNU grep 都能跑。
#
#   wake/tests/lint-bash32-utf8.sh            扫仓库里的 wake/ 和 scripts/
#   wake/tests/lint-bash32-utf8.sh <路径...>  只扫给定的文件或目录
set -u
export LC_ALL=C
root=$(cd "$(dirname "$0")/../.." && pwd)
if [ $# -eq 0 ]; then set -- "$root/wake" "$root/scripts"; fi

hi=$(printf '\200-\377')
pat='(^|[^\\])\$[A-Za-z_][A-Za-z0-9_]*['"$hi"']'

is_shell() {
    case "$1" in *.sh|*.bash) return 0 ;; esac
    head -n 1 "$1" 2>/dev/null | grep -Eq '^#!.*[/ ](ba)?sh([[:space:]]|$)'
}

hits=0
while IFS= read -r f; do
    is_shell "$f" || continue
    out=$(grep -nE "$pat" "$f" | grep -vE '^[0-9]+:[[:space:]]*#')
    [ -n "$out" ] || continue
    printf '%s\n' "$out" | while IFS= read -r line; do
        printf '%s:%s\n' "${f#"$root"/}" "$line"
    done
    hits=1
done <<EOF
$(find "$@" -type f | sort)
EOF

if [ "$hits" = 1 ]; then
    echo "lint-bash32-utf8: 上面这些 \$name 后面紧跟非 ASCII 字符，改成 \${name}" >&2
    exit 1
fi
echo "lint-bash32-utf8: ok"
