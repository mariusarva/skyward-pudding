# Skyward for Xiaomi 17 (pudding)

小米 17（`pudding`，本机系统 OS4.0.6.0.XPCCNXM）可用的 Skyward recovery：**双系统 + data 解密**都能用。

基于 [kirklin/skyward](https://github.com/kirklin/skyward) v0.2.0（GPL-3.0）自编译，发布公告文案见 `docs/发布公告.md`。

改动见 `patches/`。

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
- **WiFi 两个开关**：「自动连接」启动时开 WiFi 并连记住的网络；「记住密码」连上后保存密码，关掉立即忘记。密码明文存在 `/metadata/skyward/wlan`（0600，root）。两个开关和总开关一起放在 WLAN 页顶部，首页与设置 → WiFi 只留入口
- **WiFi 起不来的两种情形都兜住**：驱动先建 `/sys/class/net/wlan0` 再应答 ioctl，中间撞上 ENODEV 会重试；整条起不来时自动重开，最多 3 次
- **连接提速**：等网络时每 3 秒补一次扫描；DHCP 失败 3 秒重试；WLAN 驱动提前到服务启动阶段加载（实测开 WLAN 到联网从 19.4 秒降到 12.5 秒）

## 下载与刷入

到 [Releases](../../releases) 下最新的 `.img` 与 `SHA256SUMS`，校验后：

```sh
fastboot devices
fastboot getvar current-slot                 # 本机是 b
fastboot flash recovery_b skyward-pudding-20261111-v0.2.33-OS4.0.6.0.XPCCNXM.img
fastboot reboot
adb reboot recovery                          # 从系统进，别用 fastboot reboot recovery
```

- 需要已解锁 BL
- 只动 recovery 分区，`boot` / `init_boot` 不碰
- 出问题刷回原厂 recovery 即可恢复

## 校验

```
sha256  7139ebeb42edef296d6da7ea8893561161eb758c9cd06f85b73c9a9bf1b98d58
zip     skyward-v0.2.33-pudding-OS4.0.6.0.XPCCNXM.zip（更新器用，sha256 efbc8918d53ba7443b28193a2a68eddb5bc643dff47be3756df2703044030356）
大小    104857600
```

## 从源码重建

```sh
# 1) 取上游
curl -L -o skyward.tar.gz https://codeload.github.com/kirklin/skyward/tar.gz/refs/tags/v0.2.0
tar xzf skyward.tar.gz
cd skyward-0.2.0

# 2) 打本仓库的补丁
patch -p1 < ../patches/skyward-pudding-v0.2.33.patch

# 3) 交叉编译（宿主 aarch64 也能编，见 docs/开发记录.md 的“两个坑”）
rustup target add aarch64-linux-android
cargo build --release -p skyward --target aarch64-linux-android

# 4) 换进 ramdisk、重打包并补 AVB
python3 scripts/avbwrap.py ramdisk.lz4 out.img
```

`scripts/avbwrap.py` 的用法：把新 ramdisk 打包成 boot v4 镜像，并按原厂布局补 AVB 头与尾（自检能把原包逐字节重建）。

## recovery 里的「检查更新」

这一版起，REC 里的「设置 → 关于 → 检查更新」问的是**本仓库**，不是上游：

- 地址写在 `device.toml` 的 `[update] skyward`，指向 `docs/update.json`（走 `gh-proxy.com` 镜像）
- 本机实测下载速度：直连 `github.com` 71 KB/s、`ghfast.top` 500 KB/s、`ghproxy.net` 335 KB/s、**`gh-proxy.com` 1.5 MB/s**，取最快的
- Release 里的 `skyward-v0.2.33-pudding-OS4.0.6.0.XPCCNXM.zip`（只含一个 `.img`）就是更新器要的格式；`docs/update.json` 里的 `digest` 与 `size` 必须和它一致
- 发新版时：传 zip → 改 `docs/update.json` 的 `tag_name`/`size`/`digest`/URL → 提交。镜像不行就换 `[update] skyward` 的地址，不用重新编译

## 上游更新了怎么办

**不要用 REC 里的「检查更新」**：它问的是上游 `kirklin/skyward` 的 release，只认 `skyward-<tag>-pudding-*.zip`。上游没有 pudding 包时按了没用；真发了 pudding 包，它会直接覆盖 recovery 分区，把这份的改动全冲掉。

正确做法是重编，`scripts/update-upstream.sh` 把流程固化了：

```sh
RAMDISK=/path/to/ramdisk scripts/update-upstream.sh v0.3.0
```

补丁冲突的文件清单与手工合并办法见 `docs/开发记录.md` 第 11 节。


## 用 GitHub Actions 构建

`.github/workflows/build.yml`：按 tag（`v*`）或手动触发，整份 `.img` 在 GitHub 的机器上编出来。

需要的仓库 secret（Settings → Secrets and variables → Actions）：

| secret | 内容 |
|---|---|
| `DEPOT_URL` | 一个 tar.gz 的直链，里面要有 `ramdisk.lz4`（底座）与 `orig.img`（打包模板，原厂 recovery 镜像） |
| `DEPOT_TOKEN` | 上面那个地址要令牌时才填，没有就留空 |

产出：`skyward-pudding-<日期>-<tag>-OS4.0.6.0.XPCCNXM.img` + `SHA256SUMS`，作为 artifact 留存；tag 触发时自动挂到该 tag 的 Release。

**动手前要准备的两样**（都不进仓库）：

```sh
# 1) 底座的 ramdisk（任意一份打包好的都能用，CI 会换掉里面的 recovery）
lz4 -l -12 ramdisk.cpio ramdisk.lz4

# 2) 打包模板：把原厂 recovery 镜像裁成 avbwrap.py 需要的最小长度
python3 - <<'EOF'
import struct
d = open('orig.img','rb').read()
ks, rs, _, _ = struct.unpack_from('<IIII', d, 8)
L = ((4096 + rs) + 4095) // 4096 * 4096
mini = bytearray(d[:1584]) + bytearray(L - 1584) + bytearray(d[L:L+512]) + bytearray(d[-64:])
open('orig-min.img','wb').write(bytes(mini))
EOF

tar czf depot.tar.gz ramdisk.lz4 orig-min.img   # 上传这个，把直链填进 DEPOT_URL
```

## 版本号的写法

从 `v0.2.27` 起用**三段式**（与上游 `kirklin/skyward` 一致）：semver 要 `主.次.修订`，纯数字 tag 会让更新检查解析失败。早先的 `v25`/`v26`/`v27` 是纯数字，解析器现在也容错，但新版本一律三段式。

## 文件名里的版本

文件名用**本机运行的系统版本**（OS4.0.6.0.XPCCNXM）。recovery 的 ramdisk 底座仍取自 OS4.0.4.0 的原厂 recovery，记在 `device.toml` 的 `[stock]`；两者不冲突——recovery 挂载的是装机系统的分区，版本是运行时从属性读出来的，`[stock]` 只给 `skyward-pack` 用。

## 已知限制

- 只针对 `pudding` / OS4.0.4.0.XPCCNXM 验证过，其他机型不要刷
- 记住密码（锁屏与 WiFi）都是**明文**存在 `/metadata`（0600，root），恢复出厂会清；锁屏密码在解锁页点一下取消，WiFi 在设置里关开关
- WiFi 自动连接只试一次：网络不在范围或加入失败不会重试，需要手动在 WLAN 页连
- recovery 里没有 OMAPI，Thales weaver 起不来，所以走的是 gatekeeper 那条路（不影响解密）
- 触摸面板驱动要 4.5 秒才起来，前几秒只能按键，之后自动恢复（等待窗口 10 秒）
- 槽位页的事务号（`GET_ACTIVE=1` / `IS_BOOTABLE=6` / `IS_SUCCESSFUL=7` / `SET_ACTIVE_SLOT=9`）来自上游，本机以 `recovery slot` 自证；如果你的机型打印 `the boot control says slot N starts next`，说明事务号要整体后移

## 许可

沿用上游 GPL-3.0。本仓库的补丁与脚本同样以 GPL-3.0 发布；镜像内含 AOSP recovery 组件与 Skyward，来源与修改见 `patches/` 与 `docs/开发记录.md`。
