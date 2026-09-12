# MineRoulette

Godot 4.7 工程「MineRoulette」（一颗就炸）的协作源码仓库。

## 目录结构

- `scripts/` `scenes/` `shaders/`：GDScript 逻辑、场景、着色器
- `fonts/` `preview/`：字体与图片资源（原始资产）
- `project.godot` `export_presets.cfg` `export_apk.sh`：工程与导出配置
- `frame.wav` `shot.wav` `icon.svg`：音频 / 图标
- `sync.bat` / `sync.sh`：一键同步脚本（见下）

> 已排除：`.godot/`（缓存，打开自动重建）、`*.apk/*.exe/*.pck/*.idsig`（打包产物）、`*.import`（Godot 4 自动重建）。这些都不进版本控制，clone 后由 Godot 或重新导出生成。

## 协作方式

**共享面** = GitHub 仓库 `booknameZ/BoomTest`（所有成员可 clone / 操作）；
**最终落点** = 维护者本机 `D:\BoomCraft\MineRoulette`（成员 push 后自动落回本机）。

### 成员：改动后「一条指令」自动上传

1. 克隆仓库：
   ```bash
   git clone https://github.com/booknameZ/BoomTest.git
   ```
2. 用 Godot 4.7 打开 `project.godot`（首次打开会自动重建 `.godot/` 缓存，无需手动处理）。
3. 改完代码 / 资源后，在仓库目录运行**一键同步脚本**：
   - **Windows**：双击 `sync.bat`，或在终端运行 `sync.bat "本次改动说明"`
   - **Mac / Linux**：`sh sync.sh "本次改动说明"`
4. 脚本会自动 `git add -A` → `commit` → `push` 到 GitHub。
   - 首次 push 会要求输入凭据：**用户名 = 你的 GitHub 账号，密码 = Personal Access Token（不是登录密码）**。
   - 建议执行一次 `git config --global credential.helper store` 缓存凭据，避免每次输入。

### 维护者（本机）：自动下载

维护者本机已配置**定时自动 pull**（每 30 分钟检查一次远程更新），成员 push 后改动会自动落回 `D:\BoomCraft\MineRoulette`。

如需立即手动同步，在本机仓库目录运行：

```bash
git pull
```

## 安全建议

- 仓库建议设为 **Private**（团队源码不外泄）。若设为 Private，自动 pull 也需要 PAT，请告知维护者一并配置。
- 提交信息尽量写清楚改动内容，便于回溯与合并。
- `export_presets.cfg` 中的 Android debug keystore 已留空，Godot 使用默认调试密钥，不涉及私钥泄露。
