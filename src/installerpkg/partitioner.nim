import std/[os, osproc, strformat, strutils]
import ./types

proc run(cmd: string): tuple[output: string, exitCode: int] =
  execCmdEx(cmd)

proc requireOk(cmd: string, context: string) =
  let (output, code) = run(cmd)
  if code != 0:
    raise newException(InstallerError, &"{context} nie powiodło się ({code}): {cmd}\n{output}")

proc eraseDiskGpt(disk: string) =
  ## Prosty, "guided" layout: GPT + partycja EFI (512 MiB) + partycja
  ## roota zajmująca resztę dysku. To celowo minimalny, ale bezpieczny
  ## domyślny wybór -- pełne partycjonowanie ręczne to `pmManual`
  ## (zarezerwowane na przyszłość, patrz README).
  requireOk(&"sgdisk --zap-all {disk}", "Czyszczenie tablicy partycji")
  requireOk(&"parted -s {disk} mklabel gpt", "Tworzenie tablicy GPT")
  requireOk(&"parted -s {disk} mkpart ESP fat32 1MiB 513MiB", "Tworzenie partycji EFI")
  requireOk(&"parted -s {disk} set 1 esp on", "Ustawianie flagi esp")
  requireOk(&"parted -s {disk} mkpart root ext4 513MiB 100%", "Tworzenie partycji roota")

proc partitionPath(disk: string, index: int): string =
  ## /dev/sda + 1 -> /dev/sda1 ; /dev/nvme0n1 + 1 -> /dev/nvme0n1p1
  if disk.len > 0 and disk[^1].isDigit:
    disk & "p" & $index
  else:
    disk & $index

proc mkfsFor(fsType, partition: string) =
  case fsType
  of "ext4": requireOk(&"mkfs.ext4 -F -L zenith-root {partition}", "Tworzenie ext4")
  of "btrfs": requireOk(&"mkfs.btrfs -f -L zenith-root {partition}", "Tworzenie btrfs")
  of "xfs": requireOk(&"mkfs.xfs -f -L zenith-root {partition}", "Tworzenie xfs")
  else: raise newException(InstallerError, "Nieznany system plików: " & fsType)

proc applyPartitionPlan*(plan: PartitionPlan, targetMount: string): tuple[espPart, rootPart: string] =
  let disk = plan.targetDisk.path
  case plan.mode
  of pmEraseDisk:
    eraseDiskGpt(disk)
  of pmUseFreeSpace:
    echo "[partitioner] Tryb 'użyj wolnej przestrzeni' -- prototyp zakłada, że " &
         "partycje 1 (ESP) i 2 (root) już istnieją i tylko je formatuje."
  of pmManual:
    raise newException(InstallerError,
      "Partycjonowanie ręczne nie jest jeszcze zaimplementowane w tym prototypie.")

  let espPart = partitionPath(disk, 1)
  let rootPart = partitionPath(disk, 2)

  requireOk(&"mkfs.fat -F32 {espPart}", "Formatowanie ESP")
  mkfsFor(plan.filesystem, rootPart)

  if plan.swapSizeMiB > 0:
    echo &"[partitioner] Pomijam osobną partycję swap w tym prototypie -- " &
         "użyj pliku wymiany po instalacji (swapSizeMiB={plan.swapSizeMiB} zignorowane)."

  createDir(targetMount)
  requireOk(&"mount {rootPart} {targetMount}", "Montowanie roota")
  createDir(targetMount / "boot" / "efi")
  requireOk(&"mount {espPart} {targetMount / \"boot\" / \"efi\"}", "Montowanie ESP")

  (espPart, rootPart)

proc unmountTarget*(targetMount: string) =
  discard run(&"umount -R {targetMount}")
