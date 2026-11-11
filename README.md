# Skyward for Xiaomi 17 (pudding)

小米 17（`pudding`，OS4.0.4.0.XPCCNXM）可用的 Skyward recovery：**双系统 + data 解密**都能用。

基于 [kirklin/skyward](https://github.com/kirklin/skyward) v0.2.0（GPL-3.0）自编译，改动见 `patches/`。

## 这一版做了什么

上游把 `pudding` 列在“施工中”，明确不解密 data。原因有三层，逐层解决：

| # | 问题 | 解决 |
|---|---|---|
| 1 | 分区末尾缺 AVB 结构 | 按原厂布局补 `AVB0`（4096 对齐处，512 字节）+ `AVBf`（分区末 64 字节），摘要 = SHA256(镜像[0:L]) |
| 2 | 构建里没有任何解密服务 | 配置补 `qseecomd` / `hlosminkdaemon` / `onekeymint` / `gatekeeper-rust`，并加载 `stm_nfc_i2c` |
| 3 | 用户 secret 绑在 Thales weaver 上，recovery 里解不开 | 改 `data.rs`：记录的保护者绑 weaver 时，直接改用同目录带 `.secdis`+`.pwd` 的 gatekeeper 绑定 blob |
| 4 | 重启页的「下次启动」显示“无法读取” | 配置补第六条 `android.hardware.boot-service.qti`：recovery 里原本没起 boot control，读不到也切不了槽 |
| 5 | 启动那几秒提示与实际不符 | `prepare()` 未完成时显示“正在准备分区与服务”，完成后再切到“正在用记住的密码解密” |
| 6 | 共享依赖的内核模块被 insmod 两次 | `skyward-modules` 跨请求名共用一个已加载集合 |

另外加了几项自用改动：

- **开机直接进解锁页**，键盘自动就位
- **记住密码**：勾选后密码存 `/metadata/skyward/credential`（0600），下次开机自动解密；密码变了会自动删除、只试一次
- **解密成功直接回主页**（不再有“已解密/完成”的确认页），失败留在解密页
- **界面优先**：`prepare()` 放到后台线程，首帧不再等 super 映射与服务就绪；准备完成后自动重读一次槽位
- **不解密 999（分身）**：HyperOS 的第二空间凭据由主用户代持，开它是页面没在等的第二次解锁，会卡住；直接跳过，主用户照常解密
- **触摸等待放宽到 10 秒**：面板后到会自动恢复触摸，不再误判成“没有面板”
- **文件管理提到首页**：首页工具区第一行就是文件管理，高级页里的入口也保留
- **WiFi 自动连接**：设置里一个开关，打开后启动时自动开 WiFi 并用记住的密码连上次的网络；关掉即忘记。密码明文存在 `/metadata/skyward/wlan`（0600，root）

## 下载与刷入

到 [Releases](../../releases) 下最新的 `.img` 与 `SHA256SUMS`，校验后：

```sh
fastboot devices
fastboot getvar current-slot                 # 本机是 b
fastboot flash recovery_b skyward-pudding-20261110-v22-OS4.0.4.0.XPCCNXM.img
fastboot reboot
adb reboot recovery                          # 从系统进，别用 fastboot reboot recovery
```

- 需要已解锁 BL
- 只动 recovery 分区，`boot` / `init_boot` 不碰
- 出问题刷回原厂 recovery 即可恢复

## 校验

```
sha256  ff78d97fbab9c1645fd0178a5e995245010c8ca8d77e2c96221f9d0bcaa4701b
md5     8b2f93ddf35f8cf5dd81e36fd3443b0e
大小    104857600
```

## 从源码重建

```sh
# 1) 取上游
curl -L -o skyward.tar.gz https://codeload.github.com/kirklin/skyward/tar.gz/refs/tags/v0.2.0
tar xzf skyward.tar.gz
cd skyward-0.2.0

# 2) 打本仓库的补丁
patch -p1 < ../patches/skyward-pudding-v22.patch

# 3) 交叉编译（宿主 aarch64 也能编，见 docs/开发记录.md 的“两个坑”）
rustup target add aarch64-linux-android
cargo build --release -p skyward --target aarch64-linux-android

# 4) 换进 ramdisk、重打包并补 AVB
python3 scripts/avbwrap.py ramdisk.lz4 out.img
```

`scripts/avbwrap.py` 的用法：把新 ramdisk 打包成 boot v4 镜像，并按原厂布局补 AVB 头与尾（自检能把原包逐字节重建）。

## 已知限制

- 只针对 `pudding` / OS4.0.4.0.XPCCNXM 验证过，其他机型不要刷
- 记住密码（锁屏与 WiFi）都是**明文**存在 `/metadata`（0600，root），恢复出厂会清；锁屏密码在解锁页点一下取消，WiFi 在设置里关开关
- WiFi 自动连接只试一次：网络不在范围或加入失败不会重试，需要手动在 WLAN 页连
- recovery 里没有 OMAPI，Thales weaver 起不来，所以走的是 gatekeeper 那条路（不影响解密）
- 触摸面板驱动要 4.5 秒才起来，前几秒只能按键，之后自动恢复（等待窗口 10 秒）
- 槽位页的事务号（`GET_ACTIVE=1` / `IS_BOOTABLE=6` / `IS_SUCCESSFUL=7` / `SET_ACTIVE_SLOT=9`）来自上游，本机以 `recovery slot` 自证；如果你的机型打印 `the boot control says slot N starts next`，说明事务号要整体后移

## 许可

沿用上游 GPL-3.0。本仓库的补丁与脚本同样以 GPL-3.0 发布；镜像内含 AOSP recovery 组件与 Skyward，来源与修改见 `patches/` 与 `docs/开发记录.md`。
