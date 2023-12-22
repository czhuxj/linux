#!/bin/bash
#
# This file is subject to the terms and conditions of the GNU General Public
# License.  See the file "COPYING" in the main directory of this archive
# for more details.
#
# Copyright (C) 2017 by Changbin Du <changbin.du@intel.com>
#
# Adapted from code in arch/x86/boot/Makefile by H. Peter Anvin and others
#
# "make fdimage/fdimage144/fdimage288/hdimage/isoimage"
# script for x86 architecture
#
# Arguments:
#   $1  - fdimage format
#   $2  - target image file
#   $3  - kernel bzImage file
#   $4  - mtools configuration file
#   $5  - kernel cmdline
#   $6+ - initrd image file(s)
#
# This script requires:
#   bash
#   syslinux
#   mtools (for fdimage* and hdimage)
#   edk2/OVMF (for hdimage)
#
# Otherwise try to stick to POSIX shell commands...
#

# Use "make V=1" to debug this script
case "${KBUILD_VERBOSE}" in
*1*)
        set -x
        ;;
esac

# Exit the top-level shell with an error
topshell=$$
trap 'exit 1' USR1
die() {
	echo ""        1>&2
	echo " *** $*" 1>&2
	echo ""        1>&2
	kill -USR1 $topshell
}

# Verify the existence and readability of a file
verify() {
	if [ ! -f "$1" -o ! -r "$1" ]; then
		die "Missing file: $1"
	fi
}

diskfmt="$1"
FIMAGE="$2"
FBZIMAGE="$3"
MTOOLSRC="$4"
KCMDLINE="$5"
shift 5				# Remaining arguments = initrd files

export MTOOLSRC

# common options for dd
dd='dd iflag=fullblock'

# Make sure the files actually exist
verify "$FBZIMAGE"

declare -a FDINITRDS
irdpfx=' initrd='
initrdopts_syslinux=''
for f in "$@"; do
	if [ -f "$f" -a -r "$f" ]; then
	    FDINITRDS=("${FDINITRDS[@]}" "$f")
	    fname="$(basename "$f")"
	    initrdopts_syslinux="${initrdopts_syslinux}${irdpfx}${fname}"
	    irdpfx=,
	fi
done

# Read a $3-byte littleendian unsigned value at offset $2 from file $1
le() {
	local n=0
	local m=1
	for b in $(od -A n -v -j $2 -N $3 -t u1 "$1"); do
		n=$((n + b*m))
		m=$((m * 256))
	done
	echo $n
}

# Get the combined sizes in bytes of the files given, counting sparse
# files as full length, and padding each file to cluster size
cluster=16384
filesizes() {
	local t=0
	local s
	for s in $(ls -lnL "$@" 2>/dev/null | awk '/^-/{ print $5; }'); do
		t=$((t + ((s+cluster-1)/cluster)*cluster))
	done
	echo $t
}

# Expand directory names which should be in /usr/share into a list
# of possible alternatives
sharedirs() {
	local dir file
	for dir in /usr/share /usr/lib64 /usr/lib; do
		for file; do
			echo "$dir/$file"
			echo "$dir/${file^^}"
		done
	done
}

findsyslinux() {
	local f="$(find -L $(sharedirs syslinux isolinux) \
		    -name "$1" -readable -type f -print -quit 2>/dev/null)"
	if [ ! -f "$f" ]; then
		die "Need a $1 file, please install syslinux/isolinux."
	fi
	echo "$f"
	return 0
}

do_mcopy() {
	if [ ${#FDINITRDS[@]} -gt 0 ]; then
		mcopy "${FDINITRDS[@]}" "$1"
	fi
	echo default linux "$KCMDLINE$initrdopts_syslinux" | \
		mcopy - "$1"syslinux.cfg
	mcopy "$FBZIMAGE" "$1"linux
}

genbzdisk() {
	verify "$MTOOLSRC"
	mformat -v 'LINUX_BOOT' a:
	syslinux "$FIMAGE"
	do_mcopy a:
}

genfdimage144() {
	verify "$MTOOLSRC"
	$dd if=/dev/zero of="$FIMAGE" bs=1024 count=1440 2>/dev/null
	mformat -v 'LINUX_BOOT' v:
	syslinux "$FIMAGE"
	do_mcopy v:
}

genfdimage288() {
	verify "$MTOOLSRC"
	$dd if=/dev/zero of="$FIMAGE" bs=1024 count=2880 2>/dev/null
	mformat -v 'LINUX_BOOT' w:
	syslinux "$FIMAGE"
	do_mcopy w:
}

genhdimage() {
	verify "$MTOOLSRC"
	mbr="$(findsyslinux mbr.bin)"
	sizes=$(filesizes "$FBZIMAGE" "${FDINITRDS[@]}")
	# Allow 1% + 2 MiB for filesystem and partition table overhead,
	# syslinux, and config files; this is probably excessive...
	megs=$(((sizes + sizes/100 + 2*1024*1024 - 1)/(1024*1024)))
	$dd if=/dev/zero of="$FIMAGE" bs=$((1024*1024)) count=$megs 2>/dev/null
	mpartition -I -c -s 32 -h 64 $ptype -b 64 -a p:
	$dd if="$mbr" of="$FIMAGE" bs=440 count=1 conv=notrunc 2>/dev/null
	mformat -v 'LINUX_BOOT' -s 32 -h 64 -c $((cluster/512)) -t $megs h:
	syslinux --offset $((64*512)) "$FIMAGE"
	do_mcopy h:
}

geniso() {
	tmp_dir="$(dirname "$FIMAGE")/isoimage"
	rm -rf "$tmp_dir"
	mkdir "$tmp_dir"
	isolinux=$(findsyslinux isolinux.bin)
	ldlinux=$(findsyslinux  ldlinux.c32)
	cp "$isolinux" "$ldlinux" "$tmp_dir"
	cp "$FBZIMAGE" "$tmp_dir"/linux
	echo default linux "$KCMDLINE" > "$tmp_dir"/isolinux.cfg
	cp "${FDINITRDS[@]}" "$tmp_dir"/
	genisoimage -J -r -appid 'LINUX_BOOT' -input-charset=utf-8 \
		    -quiet -o "$FIMAGE" -b isolinux.bin \
		    -c boot.cat -no-emul-boot -boot-load-size 4 \
		    -boot-info-table "$tmp_dir"
	isohybrid "$FIMAGE" 2>/dev/null || true
	rm -rf "$tmp_dir"
}

rm -f "$FIMAGE"

case "$diskfmt" in
	bzdisk)     genbzdisk;;
	fdimage144) genfdimage144;;
	fdimage288) genfdimage288;;
	hdimage)    genhdimage;;
	isoimage)   geniso;;
	*)          die "Unknown image format: $diskfmt";;
esac
