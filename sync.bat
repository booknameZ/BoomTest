@echo off
REM ============================================================
REM  MineRoulette 一键同步脚本（Windows）
REM  成员改完代码后双击此文件，即可自动 add / commit / push
REM  用法：sync.bat "本次改动说明"   （说明可省略，省略时用默认信息）
REM  首次 push 会要求输入凭据：
REM     用户名 = 你的 GitHub 账号
REM     密码   = Personal Access Token（不是登录密码）
REM ============================================================
cd /d %~dp0
setlocal
set "MSG=%~1"
if "%MSG%"=="" set "MSG=auto sync: %date% %time%"

echo [sync] 暂存所有改动...
git add -A

echo [sync] 检查是否有改动...
git diff --cached --quiet
if %errorlevel%==0 (
  echo [sync] 没有改动，无需提交。
  goto :eof
)

echo [sync] 提交：%MSG%
git commit -m "%MSG%"
if %errorlevel% neq 0 (
  echo [sync] 提交失败，请查看上面的错误信息。
  goto :eof
)

echo [sync] 推送到 GitHub...
git push
if %errorlevel% neq 0 (
  echo [sync] 推送失败：请确认凭据（用户名=GitHub账号，密码=PAT），或检查网络。
  goto :eof
)

echo [sync] 已推送，远程仓库已更新。维护者本机会自动拉取。
:eof
