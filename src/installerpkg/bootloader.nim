import std/[os, osproc, strformat, strutils]
import ./types

proc requireOk(target, shellCmd, context: string) =
  let (output, code) = execCmdEx(&"chroot {target} /bin/sh -c \"{shellCmd}\"")
  if code != 0:
    raise newException(InstallerError, &"{context} nie powiodło się ({code}): {output}")

proc ensureGrubDefaultOption(target, key, value: string) =
  ## Ustawia `key=value` w /etc/default/grub -- podmienia istniejącą linię
  ## (zakomentowaną albo nie) jeśli już tam jest, albo dopisuje nową.
  let path = target / "etc" / "default" / "grub"
  var lines: seq[string] = @[]
  if fileExists(path):
    lines = readFile(path).splitLines()
  var found = false
  for i in 0 ..< lines.len:
    let trimmed = lines[i].strip()
    if trimmed.startsWith(key & "=") or trimmed.startsWith("#" & key & "="):
      lines[i] = key & "=" & value
      found = true
  if not found:
    lines.add key & "=" & value
  writeFile(path, lines.join("\n") & "\n")

proc installGrubUefi*(target, disk, distroName: string) =
  requireOk(target,
    &"grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id='{distroName}' {disk}",
    "Instalacja GRUB (UEFI)")

proc installGrubBiosLegacy*(target, disk, distroName: string) =
  ## `--bootloader-id` nie ma tu znaczenia (nie ma wpisu w NVRAM UEFI do
  ## nazwania) -- GRUB ląduje w MBR dysku i na partycji bios_grub.
  discard distroName
  requireOk(target, &"grub-install --target=i386-pc {disk}", "Instalacja GRUB (BIOS-legacy)")

proc configureGrubExtras(target: string, useLuks, enableOsProber: bool) =
  if useLuks:
    ensureGrubDefaultOption(target, "GRUB_ENABLE_CRYPTODISK", "y")
  if enableOsProber:
    ensureGrubDefaultOption(target, "GRUB_DISABLE_OS_PROBER", "false")

proc generateGrubConfig(target: string) =
  requireOk(target, "grub-mkconfig -o /boot/grub/grub.cfg", "Generowanie grub.cfg")

proc installBootloader*(target: string, mode: BootloaderMode, disk, distroName: string,
                         useLuks = false, enableOsProber = false) =
  configureGrubExtras(target, useLuks, enableOsProber)
  case mode
  of bmUefi: installGrubUefi(target, disk, distroName)
  of bmBiosLegacy: installGrubBiosLegacy(target, disk, distroName)
  generateGrubConfig(target)

proc installGrub*(target, disk, distroName: string) =
  ## Zachowane dla wstecznej zgodności -- domyślna ścieżka UEFI bez LUKS/
  ## os-prober. Nowy kod powinien wołać `installBootloader`, patrz
  ## executor.nim.
  installBootloader(target, bmUefi, disk, distroName)
