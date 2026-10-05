# Linux 3.4.39 BSP 内核兼容性问题（pcDuino8）

本 rootfs 针对 pcDuino8 官方 BSP 内核（3.4.39，2015 年 Allwinner/Linksprite 提供）做了以下适配。
如果你在其他发行版/内核组合上复现问题，或自行升级 rootfs，请保留这些补丁。

## 1. OpenSSH 在 3.4 内核上无法完成密钥交换 → 使用 dropbear

**现象**：`sshd` 端口可达、banner 正常，客户端发送 `SSH2_MSG_KEXINIT` 后连接立即被重置。
服务器日志：`Fatal glibc error: cannot get entropy for arc4random`

**根因链**：
1. `getrandom(2)` 系统调用自 Linux 3.17 才存在，3.4 返回 `ENOSYS`
2. glibc 2.36 的 `arc4random()` 回退到打开 `/dev/urandom`
3. OpenSSH 9.2 的特权分离（privsep）子进程在该阶段已将 `RLIMIT_NOFILE` 设为 **1**
   （现代内核 getrandom 永不失败，所以官方设计不会走到 open）
4. 回退 `open("/dev/urandom")` 撞上 fd 上限 → `EMFILE` → glibc 致命错误退出

**本仓库方案**：发行版使用 **dropbear**（`dropbearkey` 首启自动生成主机密钥，rc.local 已内置）。
OpenSSH 仍保留在系统内，未来升级内核后可 `systemctl enable --now ssh` 换回。

## 2. systemd-journald 启动失败 `status=227/NO_NEW_PRIVILEGES`

**根因**：`prctl(PR_SET_NO_NEW_PRIVS)` 自 Linux 3.5 才有；journald 单元默认
`NoNewPrivileges=yes`，自检不过直接退出。

**修复**（已包含在本 rootfs）：

```
# /etc/systemd/system/systemd-journald.service.d/nnpriv.conf
[Service]
NoNewPrivileges=no
```

## 3. 串口 getty 无法启动（BSP 串口驱动缺少 sysfs 节点）

**现象**：`serial-getty@ttyS0` 永远 `inactive`，journal 报
`Bound to unit dev-ttyS0.device, but unit isn't active`；
`udevadm info /dev/ttyS0` 报 `No such device`。

**根因**：BSP 的 uart0 驱动注册了 tty 设备节点（devtmpfs 里有 `/dev/ttyS0`、内核 printk 正常），
但**没有创建 `/sys/class/tty/ttyS0` sysfs 条目** → systemd 设备单元永远无法激活 →
官方模板的 `BindsTo=dev-ttyS0.device` 永远等待。

**修复**（已包含）：自定义单元 `/etc/systemd/system/ttyS0-console.service`，
抄写官方 `serial-getty@.service` 的输入配置（`StandardInput=tty` + `TTYPath`），去掉设备绑定。

## 4. /dev 下设备节点权限为 0660

**现象**：非 root 用户写 `/dev/null` 报 Permission denied；PHP `session_start()` 报
`Cannot open /dev/urandom: Permission denied`。

**根因**：该内核 devtmpfs 默认创建 0660，且 udev 对这些节点的 MODE 规则未生效（同一残缺）。

**修复**（已包含）：
- `/etc/udev/rules.d/01-urandom.rules`：null/zero/full/tty/random/urandom 全部 `MODE="0666"`
- `/etc/rc.local` 开机兜底 `chmod 666 ...`

## 5. IO 调度器 / CPU governor 开机不生效

**现象**：`/sys/block/mmcblk0/queue/scheduler` 回落 cfq；governor 回落 interactive。

**修复**（已包含）：
- rc.local 内 `echo deadline > .../scheduler`（兜底，udev 规则时序不保证）
- `/etc/init.d/governor-perf` + `S99zz-governor-perf`（排序在所有 S99 之后强制 performance）
- udev 规则 `/etc/udev/rules.d/60-scheduler.rules` 保留

## 6. u-boot / initramfs 引导链要点

- u-boot 从 **p2 分区**加载 `uEnv.txt`（`init=/init`、`root=/dev/mmcblk0p3`）
- uImage **内置 initramfs**（busybox），其 `/init` 挂载 rootfs 后检查：
  - `[ -x /mnt/init ]` → `switch_root /mnt /init`
  - 否则 `[ -x /mnt/sbin/init ]` → `switch_root /mnt /sbin/init`
  - 都不满足则进入恢复模式（"No valid rootfs found" 循环）
- **Debian usr-merge 的绝对符号链接（`/sbin/init -> /lib/systemd/systemd`）在
  initramfs 环境下 `-x` 测试会按 ramfs 根解析而判负**。
  本 rootfs 已把 `/sbin/init` 改为**相对链接** `../lib/systemd/systemd`，
  并保留顶层 `/init -> sbin/init`。**升级 systemd 包后若 /sbin/init 被改回绝对链接，需重新改回相对链接。**
- 调试后门：u-boot 里 `setenv bootargs ... ramfs` 可进入 initramfs 的 busybox 串口 shell
  （root 空密码），用于修复 rootfs。

## 7. 其他

- 内核未启用 SysRq（串口救援时无法用 magic SysRq）
- `/var/log` 是 tmpfs（原厂 fstab 保留）：nginx 日志目录需每次开机创建
  → `/etc/init.d/nginx-logdir`（S10）已包含
- zram：内核内置驱动，rc.local 自动建 256M swap
