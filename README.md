# Boot artifact test images

From this directory, run:

```sh
just aboot                # Real Android aboot disk for automotive-image-builder's abootkvmqemu
just aboot-update-test    # The aboot disk plus a v2 OCI update archive
just ukiboot              # ukiboot disk
just ukiboot-update-test  # The ukiboot disk plus a v2 OCI update archive
just uki                  # Conventional UKI disk
just --list               # Container-only and disk-only recipes
```

From the repository root, use `just -f aboot-support/Justfile aboot`.
The `tools` recipe builds bootc and image-builder from the local checkouts.
All container build contexts are the repository root so the Dockerfiles can copy
`target/release/bootc`.

The raw disks, manifests, and build logs are under `output/aboot/`,
`output/ukiboot/`, and `output/uki/`. Temporary files use `/var/tmp`.

The real aboot image uses the `alexl/aboot-deploy` COPR for `aboot-deploy`,
`aboot-update`, and `autosig-qemu-dtb`. Its `/etc/aboot.cfg` selects
`aboot-gptctl` and `/usr/share/qemu/qemu-kvm.dtb`; its disk has Android
`boot_a`/`boot_b`, `vbmeta_a`/`vbmeta_b`, and `system_a` partitions. The
kernel arguments include `acpi=off`, and the install configuration selects
bootloader `none`. There is no ESP. The ukiboot image keeps its separate
configuration.

The image uses Fedora's kernel and userspace. The aarch64 kernel is extracted
from its EFI wrapper before `aboot-update` builds the Android image. This needs
the QEMU U-Boot build with a 128 MiB `CONFIG_SYS_BOOTM_LEN`; the stock 64 MiB
limit is smaller than the uncompressed Fedora kernel. The boot slots are
192 MiB each.

To boot the real aboot disk on an aarch64 KVM host, use the
automotive-image-builder checkout:

```sh
/vcs/tyt/automotive-image-builder/bin/air --aboot --nographics output/aboot/bootc-fedora-44-raw-aarch64.raw
```

The test login is `root` / `password`, and the image version is in
`/usr/share/bootc-aboot-test-version`. For an update test, copy
`output/bootc-aboot-test-v2.oci-archive` into the guest and run:

```sh
bootc switch --transport oci-archive /path/to/bootc-aboot-test-v2.oci-archive
bootc status
systemctl reboot
cat /usr/share/bootc-aboot-test-version
bootc status
```

`switch` is used because the current `update` CLI has no `--transport` option;
both use the same composefs update implementation. The ukiboot archive is
`output/bootc-ukiboot-test-v2.oci-archive`.

`bin/osbuild` runs the installed osbuild with `--libdir /vcs/other/osbuild`,
using the checkout's stages and schemas directly.
