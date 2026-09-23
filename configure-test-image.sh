#!/bin/sh
set -eu

echo 'root:password' | chpasswd
printf '%s\n' "$1" > /usr/share/bootc-aboot-test-version
