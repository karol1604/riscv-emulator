#!/bin/sh

set -eu

usage() {
    printf 'Usage: %s <startup.s> <source.c>\n' "$0" >&2
    exit 2
}

[ "$#" -eq 2 ] || usage

startup_file=$1
c_file=$2

case "$startup_file" in
    *.s) ;;
    *)
        printf 'error: startup input must be a .s file: %s\n' "$startup_file" >&2
        exit 2
        ;;
esac

case "$c_file" in
    *.c) ;;
    *)
        printf 'error: C input must be a .c file: %s\n' "$c_file" >&2
        exit 2
        ;;
esac

for source_file in "$startup_file" "$c_file"; do
    if [ ! -f "$source_file" ]; then
        printf 'error: file not found: %s\n' "$source_file" >&2
        exit 2
    fi
done

if ! command -v brew >/dev/null 2>&1; then
    printf 'error: Homebrew is required to locate llvm and lld\n' >&2
    exit 1
fi

llvm_bin=${LLVM_BIN:-"$(brew --prefix llvm)/bin"}
lld_bin=${LLD_BIN:-"$(brew --prefix lld)/bin"}
linker_script=${LINKER_SCRIPT:-rv32i.ld}

if [ ! -f "$linker_script" ]; then
    printf 'error: linker script not found: %s\n' "$linker_script" >&2
    exit 1
fi

base=${startup_file%.s}
binary_file=${base}.bin
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/riscv-emulator.XXXXXX")
startup_object=${temp_dir}/startup.o
c_object=${temp_dir}/program.o
elf_file=${temp_dir}/program.elf

cleanup() {
    rm -f "$startup_object" "$c_object" "$elf_file"
    rmdir "$temp_dir"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

"$llvm_bin/clang" \
    --target=riscv32-unknown-elf \
    -march=rv32im \
    -mabi=ilp32 \
    -c "$startup_file" \
    -o "$startup_object"

"$llvm_bin/clang" \
    --target=riscv32-unknown-elf \
    -march=rv32im \
    -mabi=ilp32 \
    -ffreestanding \
    -fno-builtin \
    -fno-stack-protector \
    -O3 \
    -c "$c_file" \
    -o "$c_object"

"$lld_bin/ld.lld" \
    -m elf32lriscv \
    --image-base=0 \
    --no-relax \
    --entry=_start \
    -T "$linker_script" \
    "$startup_object" \
    "$c_object" \
    -o "$elf_file"

"$llvm_bin/llvm-objcopy" \
    -O binary \
    "$elf_file" \
    "$binary_file"

printf 'Created %s\n' "$binary_file"
