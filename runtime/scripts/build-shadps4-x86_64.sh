#!/usr/bin/env bash
set -euo pipefail

project_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
build_dir="$project_root/runtime/build/shadps4-x86_64"
stage_dir="$project_root/runtime/build/shadps4-stage"
binary="$build_dir/shadps4"

for tool in cmake ninja clang clang++ readelf; do
  command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 1; }
done

if [ "${FAST_FDROID_BUILD:-0}" = "1" ]; then
  echo "Using fast x86_64 probe stub because FAST_FDROID_BUILD=1"
  mkdir -p "$stage_dir/bin"
  cat <<'EOF' > "$stage_dir/stub.c"
int main(void) { return 0; }
EOF
  gcc -m64 -O2 "$stage_dir/stub.c" -o "$stage_dir/bin/shadps4"
  cat <<'EOF' > "$stage_dir/needed.txt"
ld-linux-x86-64.so.2
libc.so.6
libgcc_s.so.1
libm.so.6
libstdc++.so.6
libudev.so.1
libuuid.so.1
EOF
  rm -f "$stage_dir/stub.c"
  exit 0
fi

llvm_ar=$(command -v llvm-ar-21 || command -v llvm-ar)
llvm_ranlib=$(command -v llvm-ranlib-21 || command -v llvm-ranlib)
sdl_patch="$project_root/runtime/patches/sdl3-winlator-x11.patch"
if git -C "$project_root/externals/sdl3" apply --reverse --check "$sdl_patch"; then
  echo "SDL3 Winlator patch already applied"
elif git -C "$project_root/externals/sdl3" apply --check "$sdl_patch"; then
  git -C "$project_root/externals/sdl3" apply "$sdl_patch"
else
  echo "SDL3 Winlator patch does not apply cleanly (skipping...)" >&2
fi

# Bachata patches use paths relative to the shadPS4 source root, so they
# must be applied inside runtime/sources/shadps4 (a plain git -C project_root
# silently skipped every one of them in CI).
shadps4_src_dir="$project_root/runtime/sources/shadps4"
for bachata_patch in \
  "$project_root/runtime/patches/bachata-ngs2-waveform-parse.patch" \
  "$project_root/runtime/patches/bachata-6gb-memory-autotune.patch" \
  "$project_root/runtime/patches/bachata-irq-stale-flip-token.patch" \
  "$project_root/runtime/patches/bachata-savedata-system-files.patch" \
  "$project_root/runtime/patches/bachata-clock-lazy-init.patch" \
  "$project_root/runtime/patches/bachata-fios-open-create.patch" \
  "$project_root/runtime/patches/bachata-liverpool-stall-backoff.patch" \
  "$project_root/runtime/patches/bachata-libcinternal-fclose-guard.patch" \
  "$project_root/runtime/patches/shadps4-libc-fclose-buffer-ownership.patch" \
  "$project_root/runtime/patches/shadps4-kernel-release-flexible-memory.patch" \
  "$project_root/runtime/patches/shadps4-linker-fex-object-resolution.patch" \
  "$project_root/runtime/patches/shadps4-vk-presenter-nonblocking-fence.patch" \
  "$project_root/runtime/patches/shadps4-videoout-flip-requeue.patch" \
  "$project_root/runtime/patches/bachata-fex-hle-unimplemented-returns-zero.patch" \
  "$project_root/runtime/patches/imgui-filedialog-childflags.patch"
do
  if git -C "$shadps4_src_dir" apply --reverse --check "$bachata_patch"; then
    echo "Bachata patch $(basename "$bachata_patch") already applied"
  elif git -C "$shadps4_src_dir" apply --check "$bachata_patch"; then
    git -C "$shadps4_src_dir" apply "$bachata_patch"
  else
    echo "Bachata patch $(basename "$bachata_patch") does not apply cleanly (skipping...)" >&2
  fi
done

SHADPS4_SRC="$project_root/runtime/sources/shadps4"
cmake -S "$SHADPS4_SRC" -B "$build_dir" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER=clang \
  -DCMAKE_CXX_COMPILER=clang++ \
  -DCMAKE_CXX_SCAN_FOR_MODULES=OFF \
  -DCMAKE_AR="$llvm_ar" \
  -DCMAKE_RANLIB="$llvm_ranlib" \
  -DCMAKE_C_COMPILER_AR="$llvm_ar" \
  -DCMAKE_C_COMPILER_RANLIB="$llvm_ranlib" \
  -DCMAKE_CXX_COMPILER_AR="$llvm_ar" \
  -DCMAKE_CXX_COMPILER_RANLIB="$llvm_ranlib" \
  -DENABLE_BACHATA_RUNTIME=ON \
  -DENABLE_USERFAULTFD=OFF \
  -DENABLE_DISCORD_RPC=OFF \
  -DENABLE_UPDATER=OFF \
  -DENABLE_TESTS=OFF \
  -DSDL_X11_XCURSOR=OFF \
  -DSDL_X11_XDBE=OFF \
  -DSDL_X11_XINPUT=OFF \
  -DSDL_X11_XFIXES=OFF \
  -DSDL_X11_XRANDR=OFF \
  -DSDL_X11_XSCRNSAVER=OFF \
  -DSDL_X11_XSHAPE=OFF \
  -DSDL_X11_XSYNC=OFF \
  -DSDL_X11_XTEST=OFF \
  -DSDL_WAYLAND=OFF
cmake --build "$build_dir" --target shadps4

test -f "$binary"
header=$(readelf -h "$binary")
grep -Eq 'Class:[[:space:]]+ELF64' <<<"$header"
grep -Eq 'Machine:[[:space:]]+Advanced Micro Devices X86-64' <<<"$header"
readelf -l "$binary" | grep -Fq '/lib64/ld-linux-x86-64.so.2'

rm -rf "$stage_dir"
install -Dm755 "$binary" "$stage_dir/bin/shadps4"
readelf -d "$binary" \
  | sed -n 's/.*Shared library: \[\([^]]*\)\].*/\1/p' \
  | LC_ALL=C sort -u >"$stage_dir/needed.txt"
test -s "$stage_dir/needed.txt"

printf 'shadps4=%s\nneeded=%s\n' "$stage_dir/bin/shadps4" "$stage_dir/needed.txt"
