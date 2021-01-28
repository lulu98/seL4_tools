#!/bin/bash -e

#
# Copyright 2017, Data61
# Commonwealth Scientific and Industrial Research Organisation (CSIRO)
# ABN 41 687 119 230.
#
# This software may be distributed and modified according to the terms of
# the BSD 2-Clause license. Note that NO WARRANTY is provided.
# See "LICENSE_BSD2.txt" for details.
#
# @TAG(DATA61_BSD)
#

# Echo all commands if V=3; maximum verbosity.
if [ 0${V} -ge 3 ]; then
    set -x
fi

# Check usage.
if [ $# -lt 2 ]; then
    echo "Usage: $0 <output file> <symbol name> [input files]"
    echo
    echo "Generate an '.o' file that contains the symbol 'symbol name'"
    echo "that contains binary data of a CPIO file containing the input"
    echo "files."
    echo
    exit 1
fi

# Get the absolute path of $1. Unfortunately realpath, which seems the
# cleanest, most portable option here, doesn't yet ship with all
# systems.
OUTPUT_FILE="$(cd "$(dirname "$1")"; pwd -P)/$(basename "$1")"

SYMBOL=$2
shift 2

# RISC-V doesn't seem to support relocatable linking
# so we disable this flag if `spike` is the target platform
RELOCATABLE=-r
# Determine ".o" file to generate.
case "$PLAT" in
    "imx31"|"imx6"|"imx7"|"omap3"|"am335x"|\
    "exynos4"|"exynos5"|"realview"|"apq8064"|\
    "zynq7000"|"tk1"|"bcm2837")
        FORMAT=elf32-littlearm
        ;;
    "hikey"|"zynqmp")
        if [ "$SEL4_ARCH" == "aarch64" ]
        then
            FORMAT=elf64-littleaarch64
        else
            FORMAT=elf32-littlearm
        fi
        ;;
    "tx1"|"bcm2711")
            FORMAT=elf64-littleaarch64
        ;;
    "pc99")
        if [ "$SEL4_ARCH" == "x86_64" ]
        then
            FORMAT=elf64-x86-64
        else
            FORMAT=elf32-i386
        fi
        ;;
    "spike")
        if [ "$KERNEL_64" == "y" ]
        then
            FORMAT=elf64-littleriscv
        else
            FORMAT=elf32-littleriscv
        fi
        RELOCATABLE=
        ;;
    *)
        echo "$0: Unknown platform \"$PLAT\""
        exit 1
        ;;
esac

# Create working directory.
# Warning: mktemp functions differently on Linux and OSX.
TEMP_DIR=`mktemp -d -t seL4XXXX`
cleanup() {
    rm -rf ${TEMP_DIR}
}
trap cleanup EXIT

# Generate an archive of the input images.
mkdir -p "${TEMP_DIR}/cpio"
for i in $@; do
    cp -f $i "${TEMP_DIR}/cpio"
done
pushd "${TEMP_DIR}/cpio" >/dev/null
ARCHIVE="${TEMP_DIR}/archive.cpio"
APPEND=
for i in $@; do
    echo $(basename "${i}") | cpio ${APPEND} -o -H newc --file ${ARCHIVE} --quiet
    APPEND="--append"
done

# Strip CPIO metadata if possible.
set +e
which cpio-strip >/dev/null 2>/dev/null
result=$?
set -e
if [ $result -eq 0 ]; then
    cpio-strip ${ARCHIVE}
fi

popd > /dev/null

# Generate a linker script.
LINK_SCRIPT="${TEMP_DIR}/linkscript.ld"
echo "SECTIONS { ._archive_cpio : ALIGN(4) { ${SYMBOL} = . ; *(.*) ; ${SYMBOL}_end = . ; } }" \
        > ${LINK_SCRIPT}

# Generate an output object file. We switch to the same directory as ${ARCHIVE}
# in order to avoid symbols containing ${TEMP_DIR} polluting the namespace.
pushd "$(dirname ${ARCHIVE})" >/dev/null
${TOOLPREFIX}ld -T ${LINK_SCRIPT} \
	--oformat ${FORMAT} ${RELOCATABLE} -b binary $(basename ${ARCHIVE}) \
        -o ${OUTPUT_FILE}
popd >/dev/null

# Done
exit 0
