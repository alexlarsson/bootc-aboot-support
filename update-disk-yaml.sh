#!/bin/sh
set -eu

kver=$(ls /usr/lib/modules)
disk_yaml=/usr/lib/bootc-image-builder/disk.yaml
case $(uname -m) in
    aarch64)
        sed -i \
            -e 's/root-x86-64/root-arm64/g' \
            -e 's/4f68bce3-e8cd-4db1-96e7-fbcaf984b709/b921b045-1df0-41c3-af44-4c6f280d3fae/g' \
            "$disk_yaml"
        ;;
esac
sed -i "s|@ABOOT_IMAGE@|/boot/aboot-${kver}.img|" "$disk_yaml"
grep -F "source_path: \"/boot/aboot-${kver}.img\"" "$disk_yaml"
