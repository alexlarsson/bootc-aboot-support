#!/bin/sh
set -eu

kver=$(ls /usr/lib/modules)
disk_yaml=/usr/lib/bootc-image-builder/disk.yaml
sed -i "s|@ABOOT_IMAGE@|/boot/aboot-${kver}.img|" "$disk_yaml"
grep -F "source_path: \"/boot/aboot-${kver}.img\"" "$disk_yaml"
