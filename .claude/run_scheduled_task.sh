#!/bin/bash
cd /home/user497/securechat
/usr/local/bin/claude -p --dangerously-skip-permissions "$(cat /home/user497/securechat/.claude/scheduled_task_1930.md)" > /home/user497/securechat/.claude/scheduled_task_1930.log 2>&1
# Crontab'dan kendini kaldir
crontab -l | grep -v 'run_scheduled_task.sh' | crontab -
