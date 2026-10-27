#!/bin/bash
# drill case 4: change the workspace after its backup
echo after-backup > "$1/after-backup.txt"
git -c user.name=drill -c user.email=drill@localhost -C "$1" add after-backup.txt && git -c user.name=drill -c user.email=drill@localhost -C "$1" commit -qm after-backup
