import std/[json, osproc, strutils, strformat, os]
import ./types

proc parentDiskOf*(partition: string): string =
  ## /dev/sda1 -> /dev/sda ; /dev/nvme0n1p1 -> /dev/nvme0n1 ;
  ## /dev/mmcblk0p2 -> /dev/mmcblk0 ; już-dysk (bez cyfry na końcu, albo
  ## nvme-owy dysk postaci nvme<N>n<M> bez partycyjnego 'p') zostaje bez zmian.
  if partition.len == 0 or not partition[^1].isDigit:
    return partition
  var i = partition.len - 1
  while i >= 0 and partition[i].isDigit:
    dec i
  if i >= 1 and partition[i] == 'p' and partition[i - 1].isDigit:
    return partition[0 ..< i]
  if i >= 1 and partition[i] == 'n' and partition[i - 1].isDigit:
    # np. "/dev/nvme0n1" bez partycyjnego 'p' -- to już CAŁY dysk (numer po
    # 'n' to numer namespace'u NVMe, nie partycji), nie ma czego ucinać.
    return partition
  partition[0 .. i]

proc detectLiveMediumDisks*(): seq[string] =
  ## Best-effort: dyski, na których leży aktualnie zamontowany nośnik/root
  ## sesji live -- NIGDY nie powinny być bezrefleksyjnie proponowane jako
  ## cel instalacji. Sprawdza kilka konwencji montowania używanych przez
  ## różne narzędzia live (casper/live-boot/archiso) plus samo "/", bo w
  ## wielu konfiguracjach root sesji live jest na tym samym nośniku.
  result = @[]
  var content: string
  try:
    content = readFile("/proc/mounts")
  except IOError:
    return
  const liveMountpoints = ["/", "/run/live/medium", "/run/live/rootfs",
                            "/lib/live/mount/medium", "/cdrom", "/run/archiso/bootmnt",
                            "/run/casper", "/media/root-ro", "/run/rootfsbase",
                            "/isodevice"]
  for line in content.splitLines():
    let fields = line.splitWhitespace()
    if fields.len < 2: continue
    let source = fields[0]
    let mountpoint = fields[1]
    if mountpoint notin liveMountpoints: continue
    if not source.startsWith("/dev/"): continue
    let disk = parentDiskOf(source)
    if disk.len > 0 and disk notin result:
      result.add disk

proc listDisks*(): seq[DiskInfo] =
  ## Używa `lsblk --json` (dostępny na każdym rozsądnym live-CD) zamiast
  ## ręcznego parsowania /sys/block, bo daje już model/rozmiar/removable
  ## w ustrukturyzowanej formie.
  result = @[]
  if findExe("lsblk").len == 0:
    return
  let (output, code) = execCmdEx("lsblk --json --bytes -o NAME,MODEL,SIZE,RM,ROTA,TYPE")
  if code != 0 or output.len == 0:
    return
  var data: JsonNode
  try:
    data = parseJson(output)
  except JsonParsingError:
    return
  if not data.hasKey("blockdevices"): return
  let liveDisks = detectLiveMediumDisks()
  for dev in data["blockdevices"]:
    if dev{"type"}.getStr("") != "disk": continue
    let name = dev{"name"}.getStr("")
    if name.len == 0: continue
    let path = "/dev/" & name
    result.add DiskInfo(
      path: path,
      model: dev{"model"}.getStr("nieznany model").strip(),
      sizeBytes: dev{"size"}.getBiggestInt(0),
      isRemovable: dev{"rm"}.getBool(false),
      isSsd: not dev{"rota"}.getBool(true),
      isLiveMedium: path in liveDisks
    )

proc listPartitions*(diskPath: string): seq[PartitionInfo] =
  ## Istniejące partycje na WYBRANYM dysku -- używane wyłącznie w trybie
  ## ręcznym (pmManual), żeby użytkownik mógł przypisać role (ESP/root/
  ## swap/home) do partycji, które już istnieją i nie mają być tworzone
  ## ani zmieniane rozmiarowo przez instalator.
  result = @[]
  if findExe("lsblk").len == 0:
    return
  let (output, code) = execCmdEx(&"lsblk --json --bytes -o NAME,SIZE,FSTYPE,TYPE,PATH {diskPath}")
  if code != 0 or output.len == 0:
    return
  var data: JsonNode
  try:
    data = parseJson(output)
  except JsonParsingError:
    return
  if not data.hasKey("blockdevices"): return
  for dev in data["blockdevices"]:
    if not dev.hasKey("children"): continue
    for child in dev["children"]:
      if child{"type"}.getStr("") != "part": continue
      var path = child{"path"}.getStr("")
      if path.len == 0:
        let name = child{"name"}.getStr("")
        if name.len == 0: continue
        path = "/dev/" & name
      result.add PartitionInfo(
        path: path,
        sizeBytes: child{"size"}.getBiggestInt(0),
        fsType: child{"fstype"}.getStr("")
      )

proc humanSize*(bytes: BiggestInt): string =
  const units = ["B", "KiB", "MiB", "GiB", "TiB"]
  var val = bytes.float
  var i = 0
  while val >= 1024.0 and i < units.high:
    val /= 1024.0
    inc i
  result = val.formatFloat(format = ffDecimal, precision = 1) & " " & units[i]

proc detectFirmwareMode*(): BootloaderMode =
  ## Autodetekcja: jeśli /sys/firmware/efi istnieje, sesja live wystartowała
  ## przez UEFI i domyślnie proponujemy instalację w trybie UEFI. Użytkownik
  ## może to nadpisać ręcznie na ekranie partycjonowania (np. żeby zachować
  ## kompatybilność z CSM/legacy mimo dostępności UEFI).
  if dirExists("/sys/firmware/efi"):
    bmUefi
  else:
    bmBiosLegacy

proc filterOsesOnDisk*(oses: seq[string], disk: string): seq[string] =
  ## Filtruje wynik `detectOtherOperatingSystems` do wpisów leżących
  ## fizycznie na `disk` -- używane do dodatkowego ostrzeżenia przy trybie
  ## "wymaż cały dysk" (patrz app.nim/cliapp.nim). Format os-probera to
  ## `<partycja>:<opis>:<system>:<typ>` -- bierzemy partycję sprzed
  ## pierwszego dwukropka i sprawdzamy jej dysk nadrzędny. Czysta funkcja
  ## (bez I/O) -- działa na już pobranej liście, nie woła os-probera ponownie.
  result = @[]
  for line in oses:
    let colonIdx = line.find(':')
    if colonIdx <= 0: continue
    let partPath = line[0 ..< colonIdx]
    if parentDiskOf(partPath) == disk:
      result.add line

proc detectOtherOperatingSystems*(): seq[string] =
  ## Best-effort wykrywanie innych systemów (dual-boot) przez `os-prober` --
  ## jeśli narzędzie nie jest dostępne w środowisku live, po prostu nic nie
  ## zwraca. To tylko informacja dla użytkownika w kreatorze (patrz
  ## app.nim::drawNetwork/drawSummary) -- GRUB i tak uruchomi os-prober
  ## ponownie samodzielnie w chrocie przy grub-mkconfig, o ile
  ## GRUB_DISABLE_OS_PROBER=false (patrz bootloader.nim::configureGrubExtras).
  result = @[]
  if findExe("os-prober").len == 0:
    return
  let (output, code) = execCmdEx("os-prober")
  if code != 0:
    return
  for line in output.splitLines():
    let trimmed = line.strip()
    if trimmed.len > 0:
      result.add trimmed
