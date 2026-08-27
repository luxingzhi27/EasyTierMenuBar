# EasyTier Menu Bar

一个轻量的 macOS 菜单栏应用，用于监测 EasyTier 系统服务和网络节点，并可通过 macOS 管理员授权重启服务。

应用图标母版位于 `Resources/AppIcon-1024.png`，完整 macOS iconset 和打包用的 `AppIcon.icns` 位于 `Resources/`。

## 功能

- 每 5 秒检测 `system/easytier` LaunchDaemon 状态
- 启动时检查一次状态；之后仅在面板展开时轮询，收起后不持续执行查询
- 使用 `SMAppService` 可选注册为 macOS 登录项，实现登录时自动启动
- 显示服务 PID、本机 EasyTier IP 和远程节点数量
- 显示节点的直连/中继状态、协议、延迟与收发流量
- 通过 `peer-center` 显示真实全局直连拓扑，通过 `route` 高亮本机中继路径
- 节点列表随内容自适应高度，超过约四行后滚动
- 拓扑按跳数分层布局，悬浮节点时显示 IP、下一跳、路径延迟和邻居数
- 服务、RPC 或 CLI 异常时改变菜单栏图标并展示原因
- 通过系统授权弹窗启动、停止或重启 EasyTier LaunchDaemon
- macOS 26+ 使用 Apple 原生 Liquid Glass 面板与按钮，旧系统回退到 Material
- 使用透明无边框 `NSPanel` 承载单层玻璃，避免 `MenuBarExtra` 的双重宿主背景
- 不读取配置文件，不展示或保存 EasyTier 网络密钥

## 系统要求

- macOS 13 或更高版本
- Swift 5.9 或更高版本（Command Line Tools 即可）
- EasyTier 服务名为 `easytier`
- EasyTier RPC 地址为 `127.0.0.1:15888`
- `easytier-cli` 位于以下路径之一：
  - `~/.local/bin/easytier-cli`
  - `/opt/homebrew/bin/easytier-cli`
  - `/usr/local/bin/easytier-cli`
  - `/usr/bin/easytier-cli`

## 构建与运行

```bash
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open dist/EasyTierMenuBar.app
```

开发时也可以直接运行：

```bash
swift run EasyTierMenuBar
```

运行后不会在 Dock 显示图标；请点击菜单栏中的网络状态图标打开面板。

## 测试

```bash
chmod +x scripts/test.sh
./scripts/test.sh
```

测试脚本兼容仅安装 Command Line Tools、未安装完整 Xcode 的环境。

## 安全说明

应用平时以当前用户权限运行。只有点击“重启 EasyTier”后，macOS 才会显示标准管理员授权窗口；应用本身不会接触或保存管理员密码。当前构建使用本地 ad-hoc 签名，适合本机使用。如需分发给其他 Mac，应使用 Apple Developer ID 签名并完成 notarization。
