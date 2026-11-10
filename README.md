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

另外加了三个自用功能：

- **开机直接进解锁页**，键盘自动就位
- **记住密码**：勾选后密码存 `/metadata/skyward/credential`（0600），下次开机自动解密；密码变了会自动删除、只试一次
- **解密成功直接回主页**（不再有“已解密/完成”的确认页），失败留在解密页
- **界面优先**：`prepare()` 放到后台线程，首帧不再等 super 映射与服务就绪

## 下载与刷入

到 [Releases](../../releases) 下最新的 `.img` 与 `SHA256SUMS`，校验后：

```sh
fastboot devices
fastboot getvar current-slot                 # 本机是 b
fastboot flash recovery_b skyward-pudding-20261110-v15-OS4.0.4.0.XPCCNXM.img
fastboot reboot
adb reboot recovery                          # 从系统进，别用 fastboot reboot recovery
```

- 需要已解锁 BL
- 只动 recovery 分区，`boot` / `init_boot` 不碰
- 出问题刷回原厂 recovery 即可恢复

## 校验

```
sha256  55b798785212dad28285e69a6a12b834d92d1c20ac58294af5c8e760f8d742b4
md5     1bcb5947ceeccd29ef074c2bd6edbf55
大小    104857600
```

## 从源码重建

```sh
# 1) 取上游
curl -L -o skyward.tar.gz https://codeload.github.com/kirklin/skyward/tar.gz/refs/tags/v0.2.0
tar xzf skyward.tar.gz
cd skyward-0.2.0

# 2) 打本仓库的补丁
patch -p1 < ../patches/skyward-pudding-v15.patch

# 3) 交叉编译（宿主 aarch64 也能编，见 docs/开发记录.md 的“两个坑”）
rustup target add aarch64-linux-android
cargo build --release -p skyward --target aarch64-linux-android

# 4) 换进 ramdisk、重打包并补 AVB
python3 scripts/avbwrap.py ramdisk.lz4 out.img
```

`scripts/avbwrap.py` 的用法：把新 ramdisk 打包成 boot v4 镜像，并按原厂布局补 AVB 头与尾（自检能把原包逐字节重建）。

## 已知限制

- 只针对 `pudding` / OS4.0.4.0.XPCCNXM 验证过，其他机型不要刷
- 记住密码是**明文**存在 `/metadata`（0600，root），恢复出厂会清；不想要就在解锁页点一下取消
- recovery 里没有 OMAPI，Thales weaver 起不来，所以走的是 gatekeeper 那条路（不影响解密）
- 触摸面板驱动要 4.5 秒才起来，前几秒只能按键，之后自动恢复

## 许可

沿用上游 GPL-3.0。本仓库的补丁与脚本同样以 GPL-3.0 发布；镜像内含 AOSP recovery 组件与 Skyward，来源与修改见 `patches/` 与 `docs/开发记录.md`。
