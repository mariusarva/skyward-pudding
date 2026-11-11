#!/bin/sh
# 上游 kirklin/skyward 出了新 tag 时，把本仓库的补丁带过去，重新编一份 pudding 镜像。
#
# 用法（在仓库根目录跑）：
#   RAMDISK=/path/to/ramdisk scripts/update-upstream.sh v0.3.0
#
# RAMDISK 是一份已解开的 recovery ramdisk 目录（含 system/bin/recovery、
# skyward/device.toml 等）。没有的话先从原厂 recovery 镜像里解开：
#   lz4 -d ramdisk.lz4 ramdisk.cpio && mkdir ramdisk && cd ramdisk && cpio -idm < ../ramdisk.cpio
#
# 环境变量（交叉编译用，按自己的机器改）：
#   CC_aarch64_linux_android / CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER  指向 aarch64 clang 包装脚本
#   AR_aarch64_linux_android=ar
set -eu

# 时间戳对齐：本机是 Asia/Shanghai，而 Linux 环境默认 UTC。若不设这个，从这里
# 往 /storage 拷文件，FUSE 会把 mtime 写早 8 小时（2026-11-11 踩过：镜像显示 02:44，
# 实际是 10:44）。设上 TZ 后 copy 出来的 mtime 就是对的。
export TZ=Asia/Shanghai


TAG="${1:-}"
if [ -z "$TAG" ]; then
  echo "用法：RAMDISK=/path/to/ramdisk $0 <上游 tag，如 v0.3.0>" >&2
  exit 2
fi
[ -n "${RAMDISK:-}" ] || { echo "没给 RAMDISK" >&2; exit 2; }
[ -d "$RAMDISK" ] || { echo "RAMDISK 不存在：$RAMDISK" >&2; exit 2; }

ROOT=$(cd "$(dirname "$0")/.." && pwd)
PATCH=$(ls -1 "$ROOT"/patches/skyward-pudding-*.patch 2>/dev/null | sort -V | tail -1)
[ -n "$PATCH" ] || { echo "找不到补丁：$ROOT/patches/" >&2; exit 1; }

echo "== 1/5 下载上游 $TAG =="
mkdir -p "$ROOT/build/upstream"
TARBALL="$ROOT/build/upstream/skyward-$TAG.tar.gz"
[ -f "$TARBALL" ] || curl -fL --retry 3 -o "$TARBALL" "https://codeload.github.com/kirklin/skyward/tar.gz/refs/tags/$TAG"
SRC="$ROOT/build/skyward-${TAG#v}"
rm -rf "$SRC"; mkdir -p "$SRC"
tar xzf "$TARBALL" -C "$SRC" --strip-components=1

echo "== 2/5 打补丁 $(basename "$PATCH") =="
cd "$SRC"
if ! patch -p1 --dry-run < "$PATCH" > /tmp/patch-dry.log 2>&1; then
  echo "!! 补丁与 $TAG 冲突，需要手工合："
  grep -E "FAILED|Hunk" /tmp/patch-dry.log | head -40
  echo
  echo "   合完继续："
  echo "     cd $SRC && patch -p1 < $PATCH"
  echo "     RAMDISK=$RAMDISK $0 --build-only $TAG"
  exit 1
fi
patch -p1 < "$PATCH"

echo "== 3/5 交叉编译 =="
cargo build --release -p skyward --target aarch64-linux-android
BINARY="$SRC/target/aarch64-linux-android/release/skyward"
[ -x "$BINARY" ] || { echo "没有产出二进制" >&2; exit 1; }

echo "== 4/5 换进 ramdisk =="
cp "$BINARY" "$RAMDISK/system/bin/recovery"
chmod 755 "$RAMDISK/system/bin/recovery"

echo "== 5/5 重打包 + 补 AVB =="
mkdir -p "$ROOT/build/out"
(cd "$RAMDISK" && find . -print0 | cpio --null -o -H newc --owner=0:0 --reproducible > "$ROOT/build/out/ramdisk.cpio" 2>/dev/null)
lz4 -l -12 -f "$ROOT/build/out/ramdisk.cpio" "$ROOT/build/out/ramdisk.lz4" > /dev/null
OUT="$ROOT/build/out/skyward-pudding-$TAG.img"
python3 "$ROOT/scripts/avbwrap.py" "$ROOT/build/out/ramdisk.lz4" "$OUT"
echo
echo "产物：$OUT"
sha256sum "$OUT"

echo
echo "刷之前先在真机上确认：解锁页能进、data 能解、重启页槽位能读。"
echo "合过冲突的话，记得把补丁重出一份："
echo "  diff -ruN --exclude=target --exclude=.git build/upstream/skyward-$TAG $SRC > patches/skyward-pudding-$TAG.patch"
