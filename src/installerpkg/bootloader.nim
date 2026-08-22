import std/[osproc, strformat]
import ./types

proc requireOk(target, shellCmd, context: string) =
  let (output, code) = execCmdEx(&"chroot {target} /bin/sh -c \"{shellCmd}\"")
  if code != 0:
    raise newException(InstallerError, &"{context} nie powiodło się ({code}): {output}")

proc installGrub*(target, disk, distroName: string) =
  requireOk(target,
    &"grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id='{distroName}' {disk}",
    "Instalacja GRUB (UEFI)")
  requireOk(target, "grub-mkconfig -o /boot/grub/grub.cfg", "Generowanie grub.cfg")
