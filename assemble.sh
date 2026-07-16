#!/bin/sh

set -eu

usage() {
    printf 'Usage: %s <program.s>\n' "$0" >&2
    exit 2
}

[ "$#" -eq 1 ] || usage

source_file=$1
case "$source_file" in
    *.s) ;;
    *)
        printf 'error: input must be a .s file: %s\n' "$source_file" >&2
        exit 2
        ;;
esac

if [ ! -f "$source_file" ]; then
    printf 'error: file not found: %s\n' "$source_file" >&2
    exit 2
fi

if ! command -v brew >/dev/null 2>&1; then
    printf 'error: Homebrew is required to locate llvm and lld\n' >&2
    exit 1
fi

llvm_bin=${LLVM_BIN:-"$(brew --prefix llvm)/bin"}
lld_bin=${LLD_BIN:-"$(brew --prefix lld)/bin"}

base=${source_file%.s}
object_file=${base}.o
elf_file=${base}.elf
binary_file=${base}.bin

cleanup() {
    rm -f "$object_file" "$elf_file"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

"$llvm_bin/llvm-mc" \
    -triple=riscv32 \
    -mattr=+m \
    -filetype=obj \
    "$source_file" \
    -o "$object_file"

"$lld_bin/ld.lld" \
    -m elf32lriscv \
    --image-base=0 \
    -Ttext=0x0 \
    --entry=_start \
    "$object_file" \
    -o "$elf_file"

"$llvm_bin/llvm-objcopy" \
    -O binary \
    --only-section=.text \
    "$elf_file" \
    "$binary_file"

printf 'Created %s\n' "$binary_file"
