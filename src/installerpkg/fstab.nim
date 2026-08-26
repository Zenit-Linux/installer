import std/[os, osproc, strformat, strutils]

type
  FstabEntry* = object
    partition*: string
    mountpoint*: string
    fsType*: string
    options*: string

proc partitionUuid(partition: string): string =
  let (output, code) = execCmdEx(&"blkid -s UUID -o value {partition}")
  if code == 0: output.strip() else: ""

proc fstabLine(e: FstabEntry): string =
  ## Preferuje UUID (stabilne niezależnie od kolejności wykrywania dysków
  ## przy kolejnych rozruchach) -- ścieżka /dev/sdXN jako fallback tylko
  ## jeśli blkid z jakiegoś powodu nie zwróci UUID (np. surowa partycja
  ## bios_grub, której i tak tu nie wpisujemy).
  let uuid = partitionUuid(e.partition)
  let devSpec = if uuid.len > 0: "UUID=" & uuid else: e.partition
  let dump = 0
  let fsck = if e.mountpoint == "/": 1 elif e.fsType == "swap": 0 else: 2
  &"{devSpec}\t{e.mountpoint}\t{e.fsType}\t{e.options}\t{dump}\t{fsck}\n"

proc writeFstab*(target: string, entries: seq[FstabEntry]) =
  var content = "# /etc/fstab -- wygenerowane automatycznie przez Zenit Installer\n"
  content.add "# <device>\t<mount point>\t<type>\t<options>\t<dump>\t<pass>\n"
  for e in entries:
    content.add fstabLine(e)
  writeFile(target / "etc" / "fstab", content)
