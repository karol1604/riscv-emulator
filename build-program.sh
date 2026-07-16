#!/bin/sh

set -eu

usage() {
    printf 'Usage: %s <startup.s> [source.c]\n' "$0" >&2
    exit 2
}

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    usage
fi

startup_file=$1
c_file=${2-}

case "$startup_file" in
    *.s) ;;
    *)
        printf 'error: startup input must be a .s file: %s\n' "$startup_file" >&2
        exit 2
        ;;
esac

if [ ! -f "$startup_file" ]; then
    printf 'error: file not found: %s\n' "$startup_file" >&2
    exit 2
fi

if [ -n "$c_file" ]; then
    case "$c_file" in
        *.c) ;;
        *)
            printf 'error: optional source input must be a .c file: %s\n' "$c_file" >&2
            exit 2
            ;;
    esac

    if [ ! -f "$c_file" ]; then
        printf 'error: file not found: %s\n' "$c_file" >&2
        exit 2
    fi
fi

if ! command -v brew >/dev/null 2>&1; then
    printf 'error: Homebrew is required to locate llvm and lld\n' >&2
    exit 1
fi

llvm_bin=${LLVM_BIN:-"$(brew --prefix llvm)/bin"}
lld_bin=${LLD_BIN:-"$(brew --prefix lld)/bin"}
script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
linker_script=${LINKER_SCRIPT:-"${script_dir}/rv32i.ld"}

if [ ! -f "$linker_script" ]; then
    printf 'error: linker script not found: %s\n' "$linker_script" >&2
    exit 1
fi

base=${startup_file%.s}
elf_file=${base}.elf
binary_file=${base}.bin
temp_dir=$(mktemp -d "${TMPDIR:-/tmp}/riscv-emulator.XXXXXX")
startup_object=${temp_dir}/startup.o
c_object=${temp_dir}/program.o
temporary_elf=${temp_dir}/program.elf
temporary_binary=${temp_dir}/program.bin

cleanup() {
    rm -f "$startup_object" "$c_object" "$temporary_elf" "$temporary_binary"
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

if [ -n "$c_file" ]; then
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
        -o "$temporary_elf"
else
    "$lld_bin/ld.lld" \
        -m elf32lriscv \
        --image-base=0 \
        --no-relax \
        --entry=_start \
        -T "$linker_script" \
        "$startup_object" \
        -o "$temporary_elf"
fi

"$llvm_bin/llvm-objcopy" \
    -O binary \
    "$temporary_elf" \
    "$temporary_binary"

mv "$temporary_elf" "$elf_file"
mv "$temporary_binary" "$binary_file"

printf 'Created %s\n' "$elf_file"
printf 'Created %s\n' "$binary_file"
