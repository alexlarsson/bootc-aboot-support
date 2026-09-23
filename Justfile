set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

root := parent_directory(justfile_directory())
export TMPDIR := "/var/tmp"
export PATH := justfile_directory() / "bin" + ":" + env("PATH")

default:
    @just --list

# Build bootc and image-builder.
tools:
    cargo build --manifest-path "{{root}}/Cargo.toml" --release
    (cd /vcs/other/osbuild-image-builder; make build)
    mkdir -p build
    cp -L bin/image-builder build/image-builder

_build-container variant version="1":
    podman build --layers --ignorefile Dockerfile.{{variant}}.dockerignore -f Dockerfile.{{variant}} --target rootfs {{if version == "" { "" } else { "--build-arg TEST_VERSION=" + version }}} -t localhost/bootc-{{variant}}-build "{{root}}"

_test-container variant version="1":
    podman build --layers --ignorefile Dockerfile.{{variant}}.dockerignore -f Dockerfile.{{variant}} {{if version == "" { "" } else { "--build-arg TEST_VERSION=" + version }}} -t localhost/bootc-{{variant}}-test{{if version == "" { "" } else { ":v" + version }}} {{if version == "1" { "-t localhost/bootc-" + variant + "-test" } else { "" }}} "{{root}}"

_archive-v2 variant:
    mkdir -p output
    podman save --format oci-archive --output output/bootc-{{variant}}-test-v2.oci-archive localhost/bootc-{{variant}}-test:v2

_disk variant:
    image-builder build --verbose --bootc-default-fs ext4 --bootc-ref localhost/bootc-{{variant}}-test --bootc-build-ref localhost/bootc-{{variant}}-build --output-dir output/{{variant}} --with-manifest --with-buildlog --in-vm raw

# Build the v1 ukiboot container.
containers-ukiboot: containers-ukiboot-build containers-ukiboot-v1

containers-ukiboot-build: tools (_build-container "ukiboot")

containers-ukiboot-v1: tools (_test-container "ukiboot")

# Build the v2 ukiboot target container.
containers-ukiboot-v2: tools (_test-container "ukiboot" "2")

# Export v2 for an update test.
archive-ukiboot-v2: containers-ukiboot-v2 (_archive-v2 "ukiboot")

# Build the real Android aboot containers for the abootkvmqemu target.
containers-aboot: containers-aboot-build containers-aboot-v1

containers-aboot-build: tools (_build-container "aboot")

containers-aboot-v1: tools (_test-container "aboot")

containers-aboot-v2: tools (_test-container "aboot" "2")

archive-aboot-v2: containers-aboot-v2 (_archive-v2 "aboot")

# Build the conventional UKI build and target containers.
containers-uki-build: tools (_build-container "uki" "")

containers-uki: tools (_test-container "uki" "")

# Rebuild containers and create the ukiboot raw disk.
ukiboot: containers-ukiboot-build containers-ukiboot disk-ukiboot

# Create a v1 disk and a v2 OCI archive for an update test.
ukiboot-update-test: ukiboot archive-ukiboot-v2

# Rebuild containers and create the real aboot raw disk.
aboot: containers-aboot-build containers-aboot disk-aboot

# Create a v1 disk and a v2 OCI archive for a real aboot update test.
aboot-update-test: aboot archive-aboot-v2

# Rebuild containers and create the conventional UKI raw disk.
uki: containers-uki-build containers-uki disk-uki

# Create the ukiboot disk from existing containers.
disk-ukiboot: (_disk "ukiboot")

# Create the real aboot disk from existing containers.
disk-aboot: (_disk "aboot")

# Create the UKI disk from existing containers.
disk-uki: (_disk "uki")

# Rebuild all test images.
all: aboot ukiboot uki
