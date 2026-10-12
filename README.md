# Boot artifact test images

From this directory, run:

```sh
just aboot                # Real Android aboot disk for automotive-image-builder's abootkvmqemu
just aboot-update-test    # The aboot disk plus a v2 OCI update archive
just ukiboot              # ukiboot disk
just ukiboot-update-test  # The ukiboot disk plus a v2 OCI update archive
just ukiboot-bcvk         # ukiboot disk installed with bcvk to-disk
just ukiboot-bcvk-update-test # The bcvk disk plus a v2 OCI update archive
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
`boot_a`/`boot_b`, `vbmeta_a`/`vbmeta_b`, and `root-arm64` partitions. The
kernel arguments include `acpi=off`, and bootc detects bootloader `none` from
the Android boot payload. There is no ESP. The ukiboot image keeps its separate
configuration.

The EFI examples use `root=gpt-auto` to discover the root partition by its DPS
type GUID. The Android example has no ESP and uses `root=PARTLABEL=root-arm64`,
matching repart's default root partition label. Neither depends on a filesystem
label named `root`.

The ukiboot fixture enables `ukiboot-set-success.service` to mark successful
boots and uses a 16 GiB disk layout to leave room for the OCI update archive
and staged deployment. On an x86 KVM host, run it with:

```sh
/vcs/tyt/automotive-image-builder/bin/air --nographics --memory 4G --publish-dir output output/ukiboot/bootc-fedora-44-raw-x86_64.raw
```

The published archive is available in the guest at
`http://10.0.2.100/bootc-ukiboot-test-v2.oci-archive`.

The bcvk recipes use `bcvk` from `PATH` and install the same ukiboot image with
`bootc install to-disk`. bootc selects its built-in ukiboot repart layout from the
image's boot artifact; no custom repart definitions or explicit backend or
bootloader options are supplied. The image-builder `disk.yaml` is not used by
this path. The raw disk and installation logs are under `output/ukiboot-bcvk/`.
To install an existing v1 container without rebuilding, run
`just disk-ukiboot-bcvk`. Boot the resulting disk with:

```sh
/vcs/tyt/automotive-image-builder/bin/air --nographics --memory 4G --publish-dir output output/ukiboot-bcvk/disk.raw
```

In the guest, check that bootc reports a composefs deployment and slot A is
marked successful:

```sh
bootc status
ukibootctl dump
systemctl status ukiboot-set-success.service bootc-aboot-reconcile.service
```

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
