#!/bin/sh
# ============================================================
#  MineRoulette 一键同步脚本（Mac / Linux / Git Bash）
#  成员改完代码后运行： sh sync.sh "本次改动说明"
#  脚本自动 add / commit / push 到 GitHub
#  首次 push 会要求输入凭据：
#     用户名 = 你的 GitHub 账号
#     密码   = Personal Access Token（不是登录密码）
# ============================================================
cd "$(dirname "$0")" || exit 1

MSG="${1:-auto sync: $(date '+%Y-%m-%d %H:%M')}"

echo "[sync] 暂存所有改动..."
git add -A

echo "[sync] 检查是否有改动..."
if git diff --cached --quiet; then
  echo "[sync] 没有改动，无需提交。"
  exit 0
fi

echo "[sync] 提交：$MSG"
git commit -m "$MSG" || { echo "[sync] 提交失败。"; exit 1; }

echo "[sync] 推送到 GitHub..."
if git push; then
  echo "[sync] 已推送，远程仓库已更新。维护者本机会自动拉取。"
else
  echo "[sync] 推送失败：请确认凭据（用户名=GitHub账号，密码=PAT），或检查网络。"
  exit 1
fi
