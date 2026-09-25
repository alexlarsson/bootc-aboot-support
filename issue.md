Support aboot in composefs backend

This is an initial proposal, intended to start a high-level discussion about adding support
for Android boot (and related technologies) in the bootc composefs backend. This is what
we are using in the CentOS Automotive project (currently with the ostree+composefs bootc
backend), and we would like to move to the composefs backend.

This is a companion high-level discussion to the current draft PR proposed in
https://github.com/bootc-dev/bootc/pull/2490.

## Background

First some background on Android boot. We use the Android boot v2 image format which is in
many ways very similar to UKIs: the image bundles a kernel, initrd, DTB, and kernel
command line, and it can be signed and validated at boot. The main difference is
that the images are stored in a raw partition, not in a filesystem. It also has a slot
system where there are two partitions (slot a & b), which we ping-pong between on
updates. When verified boot is used, signature metadata is external in two `vbmeta`
partitions matching the boot partitions. This means the partitioning layout for an aboot
system is very different from a UKI one. There is no ESP, but there are `boot_a` and
`boot_b` partitions, optionally `vbmeta_a` and `vbmeta_b`, and some board-specific
location for slot metadata, which is sometimes in a partition and sometimes elsewhere.

In terms of the API surface that bootc will interact with, the firmware injects the
`androidboot.slot_suffix` kernel commandline option with the value `_a` or `_b`, depending
on what slot was booted. Additionally we have developed userspace tooling to interact with
this. There are two tools, first `aboot-update`, which picks up the kernel and some
additional board configuration from `/etc/aboot.cfg` to produce the aboot image file. This
is intended to be used at image build time. Then there is `aboot-deploy` that reads the
configuration and writes the aboot images to the correct partitions, doing whatever
specific dance is required for the hardware in use to make the new slot active for next
boot. This is intended to be called when a staged update is finalized.

In addition to the traditional android boot, we have created a new EFI bootloader called
ukiboot, which is basically a copy of aboot, except the payload in the partition is a
uki. This allows using the same interface, workflow and code in both systems. The only
difference is that for this to work we also need an ESP partition, and we need to inject
the ukiboot EFI binaries to it during the initial install. (However, it is not needed or
used at OS runtime.)

## Image layout and building

An aboot bootc image is a regular bootc image with boot artifacts `/boot/aboot-$kver.img`
and (optionally) `/boot/vbmeta-$kver.img`. The format of the first file is either an Android
boot v2 image, or an EFI UKI (if ukiboot is used). These are in `/boot`, in order for them
to be able to be signed without modifying the boot-transformed image digest. Additionally,
it contains an `/etc/aboot.cfg` which tells the aboot tools what to do.

Additionally, a ukiboot image will contain the ukiboot EFI files in their normal
package location (under `/usr/libexec/ukiboot/efi`), and/or optionally in
`/boot/efi/EFI/$VENDOR`. The latter will be preferred by bootc, allowing them to be signed
post-image-build without affecting the boot-transformed image digest.

Image building is very similar to how you would build a UKI image: first you would call
`bootc container split-kernel-and-rootfs`, and then you would call the new `bootc
container aboot`, which behaves similar to `bootc container ukify`, except it calls
`aboot-update` instead of `ukify`.

The existence and type of the `/boot/aboot*.img` file in the image should automatically
select the required boot layout in bootc [NOTE: This is not currently done in the draft PR].

## Initial install

When using `bootc install to-filesystem`, bootc is not responsible for disk partitioning,
nor can it write to devices. This means that whatever tool is used to call bootc must both
setup the correct aboot partitioning, as well as write the aboot image to the boot
partition. If `image-builder` is used, this can be done by supplying a `disk.yaml` file
that contains a `payload` option for the `boot_a` partition.

When using `bootc install to-disk` however, bootc should be able to automatically detect
what type of aboot is needed and create the correct partitions. [NOTE: This is not
currently done in the draft PR].

If bootc install detects that ukiboot is needed, then it will deploy the ukiboot EFI
binaries to the ESP partition. It will however not call bootupd.

## Tracking boot state

Aboot state is tracked in `/sysroot/state/boot/aboot`. In particular, `$state/slots/[ab]`
contains the current digest that was seen booted in a particular slot, and acts as a GC
root to ensure these slots keep booting. This state is updated by the
`bootc-aboot-reconcile.service` as soon as the state directory is available. We never
write a digest to these slot files before booting them, so once we see a digest there we
know it is reliable (has booted). We do however remove the non-active slot during an
update before calling aboot-deploy to write to the slot.

During an update/switch after a new image has been pulled we create in the deploy dir an
aboot directory (`/sysroot/state/deploy/<deployment-id>/aboot/`) where we (temporary)
store the `aboot.img` and `vbmeta.img`. These will be written to the final partition when
the update is finalized at reboot. To ensure nothing goes wrong until finalization, we
persist the pending info at `/sysroot/state/boot/aboot/pending` (also a GC root), like
this:

```
{
  "boot_image_sha256": "d5d8f2e0e73fb59d30f53c0391974f1b38e6b3344eff67a40006f40a36e065c2",
  "depl_id": "ba8661bea5922fae0b163388500ae9120bfa96e1cdf0a7b074ce6a007b9cf5dbe5b9ceb46c50895257e6cefe008df36fd54b6abc992bb25b1acc72709dbe9ee6",
  "finalization_locked": false,
  "vbmeta_image_sha256": null
}
```

At finalization time we validate the pending update, then create a
`/sysroot/state/boot/aboot/attempted` file (recording deploy id and boot id) before
removing the non-active boot slot state file and calling `aboot-deploy` to write to the
partition. Normally we would then record the new digest at the next boot when reconciling
the new slot state. In that case we'd remove the pending and attempt file after having
updated the slot info. Note, that reaching `bootc-aboot-reconcile.service` doesn't mean
that the complete boot was successful, that is handled separately by the aboot "mark
successful" machinery. All it does is mark that this particular deployment id is now at
this slot (broken or not).

However, if something went wrong, and we booted some other digest (typically the old one
due to a firmware fallback). Then we notice this and keep the pending and attempt file for
observation, but don't try it again. At this point is it really up to the sysadmin, or the
overall system designer to decide what to do. For example, there are systems like
greenboot and others to handle this. We don't at the moment integrate with this, but
perhaps we should mark a failed update in some way that such tools could easily
read. Maybe by having the reconcile service fail?

In the (weird) case that we boot and there is a pending update, but no attempt file that
means we haven't tried to do the update yet, perhaps due to a power-failure. In this case
we currently restore the persistend update as a transient state which will be applie at
shutdown. (Not actually sure this is the correct approach though.)

We also support `bootc rollback`, but that behaves differently. It just asks
`aboot-deploy` to change the active slot, and we will boot the old slot/deployment on the
next boot. There is a rollback state file to mark this, just to keep track of this state
for `bootc status` display info, but this isn't really a GC root or anything.

Overall slot selection is owned by `aboot-deploy`, all bootc does is ask it to "deploy to
the other slot". This way bootc doesn't have to be involved with the complexities and
differences in that (for example, in some weird cases we only have one slot,
etc). aboot-deploy itself does a multi-step update where it first marks the new slot
unbootable, then writes to it, and then at the end marks it potentially active (with some
boot count before it falls back). Only at a successful boot (reach boot-complete.target),
will it be marked as successfully booted (by e.g. `ukiboot-set-success.service`).
