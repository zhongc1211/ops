#!/bin/bash
# drill case 3a: passes the startup check, every PR query fails
[ "$1 $2" = "auth status" ] && exit 0
echo "drill: gh always fails" >&2; exit 1
