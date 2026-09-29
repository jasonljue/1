TR1200 ImmortalWrt 24.10.6 Test1 构建包
======================================

目标：
1. Cudy TR1200 v1
2. ImmortalWrt 24.10.6 / ramips mt76x8
3. Momo v1.2.1
4. Flash 中不放真正 sing-box Go 核心
5. /usr/bin/sing-box 只是极小包装器
6. 真正核心只在 Momo 实际启动/调用核心时下载到 /tmp/sing-box
7. Momo 未启用时，正常开机不会下载 sing-box
8. 同一次开机 /tmp/sing-box 已存在时不重复下载
9. Android USB：RNDIS / CDC Ethernet
10. USB 网络：NCM / MBIM
11. sysupgrade 目标 <= 9.5 MiB

为什么现在给的是“可复现构建包”而不是假装已经编好的 sysupgrade.bin：
当前 ChatGPT 的本地编译容器无法联网下载 ImmortalWrt 官方 ImageBuilder，因此不能在这里真正执行最后一步 ImageBuilder。
本包已经把所有构建逻辑固定；放到 GitHub Actions 或正常联网的 Ubuntu 24.04 执行，会直接产出实际固件。

最简单的 GitHub Actions 用法：
1. 新建一个空 GitHub 仓库。
2. 把本压缩包里的全部内容上传到仓库根目录（注意 .github 文件夹也要上传）。
3. 打开仓库 Actions。
4. 选择 “Build TR1200 Test1”。
5. 点 Run workflow。
6. 完成后下载 Artifact：TR1200-ImmortalWrt-24.10.6-Test1。

产物里应该有：
- *cudy_tr1200-v1*squashfs-sysupgrade.bin
- *cudy_tr1200-v1*initramfs-kernel.bin
- packages-manifest.txt
- build-info.txt
- SHA256SUMS
- sing-box_99.0.0-r1_all.ipk

重要：第一次不要看到 .bin 就直接刷。
先把 build-info.txt、packages-manifest.txt 和固件文件大小发回来检查。
只有以下条件同时满足才进入刷机测试：
- Profile = cudy_tr1200-v1
- Base = ImmortalWrt 24.10.6
- manifest 有 momo / luci-app-momo / luci-i18n-momo-zh-cn
- manifest 的 sing-box 必须是 99.0.0-r1 包装器
- 固件没有超过我们确定的尺寸红线

sing-box 下载逻辑：
- 开机 + Momo 禁用：不下载。
- 你在 LuCI 打开 Momo 并启动：Momo 调用 /usr/bin/sing-box，此时才下载。
- 同次开机重新启动 Momo：直接复用 /tmp/sing-box。
- 重启 TR1200 后 /tmp 清空；如果 Momo 仍为禁用，不下载；如果 Momo 已设置为启用并随系统启动，Momo 真正启动时才下载。

Test1 暂不做：
- sing-box 极限裁剪
- 固定 sing-box 自编译版本
- 自建 VPS 核心镜像
- SHA256 固定核心校验
这些等真机先确认 Momo + RAM 核心链路正常以后再做，避免同时引入太多变量。
