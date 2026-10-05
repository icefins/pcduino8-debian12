# pcDuino8 Debian 12 (bookworm)

面向 **pcDuino8 / pcDuino8 Uno**（全志 A83T，八核 Cortex-A7，1GB RAM）的 **Debian 12 rootfs + 原厂引导** 打包。开箱即用，无需自己编译或适配——所有 BSP 内核兼容性问题已在本仓库修复并文档化。

> 底层内核仍是 pcDuino 官方 3.4.39 BSP 内核（[内核源码](https://github.com/pcduino/pcduino8-uno-kernel)），rootfs 为 Debian 12 bookworm armhf + systemd 252。

## 特性

- **Debian 12 bookworm**（受支持至 2028 LTS），官方 apt 源，`apt upgrade` 可用
- **SSH 开箱即用**：dropbear（`linaro@<ip>`，密码 `linaro`，sudo 免密）
- **串口控制台**：115200 8N1，同样 linaro/linaro 登录
- 已针对 3.4.39 老内核修复全部已知兼容问题（见 [docs/kernel-3.4-quirks.md](docs/kernel-3.4-quirks.md)）：
  - systemd-journald 可正常运行（NoNewPrivileges 兼容补丁）
  - 串口 getty 正常（绕过 BSP 缺失的 sysfs 节点）
  - `/dev/null`、`/dev/urandom` 等权限正确
  - IO 调度器 deadline、CPU performance governor、zram 256M swap 开机自动生效
- 网络默认 **DHCP**（`/etc/network/interfaces.d/eth0` 可改静态）；保留 USB gadget `usb0`(192.168.100.1) 配置
- 含 pcDuino 原厂 `/usr/local` 工具集（mjpg_streamer、ffmpeg、opencv 工具等）

## 文件

| 文件 | 说明 |
|---|---|
| `pcduino8-debian12-rootfs.tar.xz` | 纯净 rootfs（Release 附件下载） |
| `boot/uImage` | 内核（BSP 3.4.39，GPL，源码见上） |
| `boot/uEnv.txt` | u-boot 环境（`init=/init`，root=/dev/mmcblk0p3） |
| `boot/script.bin` | 全志 syscfg |
| `boot/bootlogo.bmp` | 开机 logo（可选） |
| `scripts/install.sh` | 一键写卡脚本（Linux PC 上运行） |

## 下载与校验

`pcduino8-debian12-rootfs.tar.xz`（约 295 MB）在本仓库 **Release 附件**中下载。

```text
SHA256 (pcduino8-debian12-rootfs.tar.xz)
= 73d7aec6d3690fe9fa51e6e42c03269ebddaa776fb0ecd22912b33d4741d6024
```

校验：`sha256sum pcduino8-debian12-rootfs.tar.xz`（Linux）或 `certutil -hashfile ... SHA256`（Windows）。

## 安装（全新 SD 卡）

准备：一张 ≥8GB 的 SD 卡、Linux 电脑（或 WSL）、本仓库 Release 里的 `pcduino8-debian12-rootfs.tar.xz`。

```bash
chmod +x scripts/install.sh
sudo ./scripts/install.sh /dev/sdX ./pcduino8-debian12-rootfs.tar.xz
```

把 `/dev/sdX` 换成你的读卡器设备名（**脚本会二次校验设备指纹，写错会中止**）。完成后插卡上电即可，网线接入后路由器会通过 DHCP 分配 IP。

### 手动安装（等价步骤）

1. 分区：`p1 FAT32 1MB 偏移/35MB`、`p2 FAT32 36MB 偏移/32MB`、`p3 ext4 其余全部`
2. 把 `boot/` 下 4 个文件拷进 p2
3. `mkfs.ext4` p3 后把 rootfs 包解开到挂载点
4. `e2fsck -fy` 后插卡开机

## 首次启动

1. 网线接入，路由器里找 `pcduino8` 的 IP（或串口里 `ip a` 查看）
2. `ssh linaro@<ip>` 密码 `linaro`，`sudo` 免密
3. 改密码：`passwd`；改静态 IP：编辑 `/etc/network/interfaces.d/eth0` 后 `sudo ifdown eth0 && sudo ifup eth0`
4. 国内用户建议换 apt 源（阿里云）：

```bash
sudo sed -i 's|deb.debian.org|mirrors.aliyun.com|g' /etc/apt/sources.list
sudo apt update
```

## 目录

- `docs/kernel-3.4-quirks.md` — 3.4 内核兼容性问题全记录（移植到其他发行版时必读）
- `scripts/` — 安装与维护脚本

## 许可

- rootfs：Debian 自由软件协议（GPL/各包原协议）
- uImage 内核：GPLv2，源码见 [pcduino/pcduino8-uno-kernel](https://github.com/pcduino/pcduino8-uno-kernel)
- script.bin/uEnv.txt：pcDuino 官方引导配置

## 致谢

pcDuino 社区；本移植基于官方 Ubuntu 14.04 镜像的引导层与 BSP 内核。
