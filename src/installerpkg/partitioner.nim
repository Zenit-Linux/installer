import std/[os, osproc, strformat, strutils]
import ./types

const LuksMapperName = "zenit-root"
const LuksSwapMapperName = "zenit-swap"

proc run(cmd: string): tuple[output: string, exitCode: int] =
  execCmdEx(cmd)

proc requireOk(cmd: string, context: string) =
  let (output, code) = run(cmd)
  if code != 0:
    raise newException(InstallerError, &"{context} nie powiodło się ({code}): {cmd}\n{output}")

proc partitionPath*(disk: string, index: int): string =
  ## /dev/sda + 1 -> /dev/sda1 ; /dev/nvme0n1 + 1 -> /dev/nvme0n1p1
  if disk.len > 0 and disk[^1].isDigit:
    disk & "p" & $index
  else:
    disk & $index

proc mkfsFor(fsType, partition: string) =
  case fsType
  of "ext4": requireOk(&"mkfs.ext4 -F -L zenit-root {partition}", "Tworzenie ext4")
  of "btrfs": requireOk(&"mkfs.btrfs -f -L zenit-root {partition}", "Tworzenie btrfs")
  of "xfs": requireOk(&"mkfs.xfs -f -L zenit-root {partition}", "Tworzenie xfs")
  else: raise newException(InstallerError, "Nieznany system plików: " & fsType)

proc luksFormatAndOpen(partition, passphrase: string): string =
  ## Formatuje partycję jako LUKS2 i otwiera ją pod /dev/mapper/{LuksMapperName}.
  ## Zwraca ścieżkę do zmapowanego urządzenia -- mkfs trzeba wywołać na NIM,
  ## nigdy na surowej partycji. Hasło idzie przez stdin (--key-file=-), nigdy
  ## jako argument w linii poleceń, żeby nie lądowało w `ps aux` -- ten sam
  ## powód, dla którego hasła kont użytkowników idą przez `chpasswd` w
  ## useraccount.nim.
  let escaped = passphrase.replace("'", "'\\''")
  requireOk(&"echo -n '{escaped}' | cryptsetup luksFormat --type luks2 --batch-mode --key-file=- {partition}",
    "Formatowanie LUKS")
  requireOk(&"echo -n '{escaped}' | cryptsetup open --key-file=- {partition} {LuksMapperName}",
    "Otwieranie kontenera LUKS")
  "/dev/mapper/" & LuksMapperName

proc setupEncryptedSwap(rawPartition: string): MountedPartition =
  ## Losowy klucz z /dev/urandom przy KAŻDYM rozruchu (przez crypttab, patrz
  ## writeSwapCrypttab) -- swap nigdy nie musi przetrwać do następnego
  ## rozruchu, więc nie ma sensu pytać o osobne hasło ani używać tego
  ## samego, co dla roota (inny klucz każdego boota to nawet mocniejsze
  ## zabezpieczenie niż stałe hasło). To standardowe podejście (patrz Arch
  ## Wiki, "Encrypted swap"), nie coś specyficznego dla tego instalatora.
  ## Nic tu się nie formatuje/aktywuje w trakcie instalacji -- pierwsza
  ## aktywacja i tak nadpisze zawartość losowymi danymi przy najbliższym
  ## boocie, więc mkswap/swapon teraz i tak poszłyby na marne.
  MountedPartition(devicePath: rawPartition,
    fstabDevice: "/dev/mapper/" & LuksSwapMapperName,
    mountpoint: "none", fsType: "swap", isEncrypted: true)

proc writeCrypttab*(target, rawPartition: string) =
  ## Wpis w /etc/crypttab docelowego systemu, żeby kontener LUKS roota
  ## otwierał się automatycznie (z promptem o hasło) przy każdym rozruchu --
  ## bez tego system zbudowany przez ten instalator nie wystartowałby drugi raz.
  let (uuidOut, code) = run(&"blkid -s UUID -o value {rawPartition}")
  let uuid = uuidOut.strip()
  if code != 0 or uuid.len == 0:
    echo "[partitioner] Nie udało się odczytać UUID partycji LUKS -- pomijam wpis " &
         "w /etc/crypttab (trzeba będzie dodać go ręcznie po instalacji)."
    return
  let line = &"{LuksMapperName}\tUUID={uuid}\tnone\tluks\n"
  let path = target / "etc" / "crypttab"
  let existing = if fileExists(path): readFile(path) else: ""
  writeFile(path, existing & line)

proc writeSwapCrypttab*(target, rawPartition: string) =
  let (uuidOut, code) = run(&"blkid -s UUID -o value {rawPartition}")
  let uuid = uuidOut.strip()
  if code != 0 or uuid.len == 0:
    echo "[partitioner] Nie udało się odczytać UUID partycji swap -- pomijam wpis " &
         "w /etc/crypttab dla szyfrowanego swapu (trzeba dodać ręcznie po instalacji)."
    return
  let line = &"{LuksSwapMapperName}\tUUID={uuid}\t/dev/urandom\tswap,cipher=aes-xts-plain64,size=256\n"
  let path = target / "etc" / "crypttab"
  let existing = if fileExists(path): readFile(path) else: ""
  writeFile(path, existing & line)

proc bestEffortUndo(targetMount: string, built: seq[MountedPartition], hadLuks: bool) =
  ## Sprzątanie best-effort używane, gdy partycjonowanie przerywa się w
  ## połowie (np. root zdążył się zamontować, ale ESP już nie) -- odmontowuje
  ## to, co zdążyło się zamontować, w odwrotnej kolejności, wyłącza swap i
  ## zamyka kontener LUKS, jeśli mógł zostać otwarty. Każdy krok jest
  ## best-effort (błędy są ignorowane) -- to sprzątanie, nie kolejny krok,
  ## który miałby prawo przerwać instalację drugi raz.
  for i in countdown(built.high, 0):
    let m = built[i]
    if m.fsType == "swap":
      if m.devicePath.len > 0:
        discard run(&"swapoff {m.devicePath}")
    elif m.mountpoint == "/":
      discard run(&"umount {targetMount}")
    elif m.mountpoint.len > 0:
      discard run(&"umount {targetMount & m.mountpoint}")
  if hadLuks:
    discard run(&"cryptsetup close {LuksMapperName}")

proc createBtrfsSubvolumes(partition, targetMount: string): tuple[rootOpts, homeOpts: string] =
  ## Tworzy subwoluminy @ (root) i @home w standardowej konwencji btrfs
  ## (Fedora/openSUSE/Arch-community itd.) -- montuje surowy wolumin
  ## tymczasowo, tworzy subwoluminy, odmontowuje. Właściwe montowanie (z
  ## opcją `subvol=...`) robi wywołujący.
  createDir(targetMount)
  requireOk(&"mount {partition} {targetMount}", "Tymczasowe montowanie btrfs")
  requireOk(&"btrfs subvolume create {targetMount}/@", "Tworzenie subwoluminu @")
  requireOk(&"btrfs subvolume create {targetMount}/@home", "Tworzenie subwoluminu @home")
  requireOk(&"btrfs subvolume create {targetMount}/@snapshots", "Tworzenie subwoluminu @snapshots")
  discard run(&"umount {targetMount}")
  ("subvol=@", "subvol=@home")

proc createSwapfile(targetMount: string, sizeMiB: int, fsType: string): string =
  ## Tworzy /swapfile w już zamontowanym systemie docelowym. Na btrfs
  ## używa dedykowanego `btrfs filesystem mkswapfile` (poprawnie omija
  ## copy-on-write i kompresję dla tego jednego pliku) -- na ext4/xfs
  ## klasyczne dd+chmod+mkswap. Jeśli root jest zaszyfrowany LUKS-em, plik
  ## wymiany automatycznie dziedziczy to szyfrowanie (leży wewnątrz już
  ## odszyfrowanego systemu plików) -- bez dodatkowej konfiguracji.
  let path = targetMount / "swapfile"
  case fsType
  of "btrfs":
    requireOk(&"btrfs filesystem mkswapfile --size {sizeMiB}M {path}", "Tworzenie swapfile (btrfs)")
  else:
    requireOk(&"dd if=/dev/zero of={path} bs=1M count={sizeMiB} status=none", "Alokacja swapfile")
    requireOk(&"chmod 600 {path}", "Ustawianie uprawnień swapfile")
    requireOk(&"mkswap {path}", "Formatowanie swapfile")
  "/swapfile"

proc enableSsdMaintenance*(target: string, disk: DiskInfo) =
  ## Dla SSD (DiskInfo.isSsd) włącza fstrim.timer w docelowym systemie --
  ## okresowy TRIM zamiast opcji montowania `discard`. Best-effort: brak
  ## systemd-owego fstrim.timer (np. inny init) nie jest błędem instalacji.
  if not disk.isSsd: return
  discard run(&"chroot {target} /bin/sh -c \"systemctl enable fstrim.timer\"")

proc eraseDiskGpt(disk: string, plan: PartitionPlan): tuple[order, paths: seq[string]] =
  ## Prosty, "guided" layout GPT: [ESP albo bios_grub, zależnie od
  ## bootloaderMode] + [swap, opcjonalnie -- tylko smPartition] + partycja
  ## roota zajmująca resztę dysku. Swap jako plik (smFile) nie dostaje tu
  ## osobnej partycji -- powstaje później, wewnątrz już zamontowanego roota.
  requireOk(&"sgdisk --zap-all {disk}", "Czyszczenie tablicy partycji")
  requireOk(&"parted -s {disk} mklabel gpt", "Tworzenie tablicy GPT")

  var cursor = 1  # MiB
  var partIdx = 1
  var order: seq[string] = @[]

  case plan.bootloaderMode
  of bmUefi:
    let espEnd = cursor + 512
    requireOk(&"parted -s {disk} mkpart ESP fat32 {cursor}MiB {espEnd}MiB", "Tworzenie partycji EFI")
    requireOk(&"parted -s {disk} set {partIdx} esp on", "Ustawianie flagi esp")
    order.add "esp"
    cursor = espEnd
    inc partIdx
  of bmBiosLegacy:
    let biosEnd = cursor + 1
    requireOk(&"parted -s {disk} mkpart bios_grub {cursor}MiB {biosEnd}MiB", "Tworzenie partycji bios_grub")
    requireOk(&"parted -s {disk} set {partIdx} bios_grub on", "Ustawianie flagi bios_grub")
    order.add "biosgrub"
    cursor = biosEnd
    inc partIdx

  if plan.swapMode == smPartition and plan.swapSizeMiB > 0:
    let swapEnd = cursor + plan.swapSizeMiB
    requireOk(&"parted -s {disk} mkpart swap linux-swap {cursor}MiB {swapEnd}MiB", "Tworzenie partycji swap")
    order.add "swap"
    cursor = swapEnd
    inc partIdx

  requireOk(&"parted -s {disk} mkpart root {plan.filesystem} {cursor}MiB 100%", "Tworzenie partycji roota")
  order.add "root"

  var paths: seq[string] = @[]
  for i in 1 .. partIdx:
    paths.add partitionPath(disk, i)

  (order, paths)

proc applyErasePlan(plan: PartitionPlan, targetMount: string): seq[MountedPartition] =
  let disk = plan.targetDisk.path
  let (order, paths) = eraseDiskGpt(disk, plan)

  var espPath, swapPath, rootRaw: string
  for i, kind in order:
    case kind
    of "esp": espPath = paths[i]
    of "biosgrub": discard # surowa, GRUB pisze na niej bezpośrednio -- nic do zrobienia tutaj
    of "swap": swapPath = paths[i]
    of "root": rootRaw = paths[i]
    else: discard

  result = @[]
  try:
    if espPath.len > 0:
      requireOk(&"mkfs.fat -F32 {espPath}", "Formatowanie ESP")

    var rootDevice = rootRaw
    if plan.useLuksEncryption:
      rootDevice = luksFormatAndOpen(rootRaw, plan.luksPassphrase)

    mkfsFor(plan.filesystem, rootDevice)

    var rootOpts, homeOpts = ""
    let useBtrfsSubvolumes = plan.filesystem == "btrfs"
    if useBtrfsSubvolumes:
      let subvolOpts = createBtrfsSubvolumes(rootDevice, targetMount)
      rootOpts = subvolOpts.rootOpts
      homeOpts = subvolOpts.homeOpts

    createDir(targetMount)
    if useBtrfsSubvolumes:
      requireOk(&"mount -o {rootOpts} {rootDevice} {targetMount}", "Montowanie roota (subvol=@)")
    else:
      requireOk(&"mount {rootDevice} {targetMount}", "Montowanie roota")
    result.add MountedPartition(devicePath: rootRaw,
      fstabDevice: (if plan.useLuksEncryption: rootDevice else: rootRaw),
      mountpoint: "/", fsType: plan.filesystem,
      isEncrypted: plan.useLuksEncryption, extraMountOptions: rootOpts)

    if useBtrfsSubvolumes:
      createDir(targetMount / "home")
      requireOk(&"mount -o {homeOpts} {rootDevice} {targetMount / \"home\"}", "Montowanie @home")
      result.add MountedPartition(devicePath: rootRaw,
        fstabDevice: (if plan.useLuksEncryption: rootDevice else: rootRaw),
        mountpoint: "/home", fsType: plan.filesystem,
        isEncrypted: plan.useLuksEncryption, extraMountOptions: homeOpts)

    if espPath.len > 0:
      createDir(targetMount / "boot" / "efi")
      requireOk(&"mount {espPath} {targetMount / \"boot\" / \"efi\"}", "Montowanie ESP")
      result.add MountedPartition(devicePath: espPath, fstabDevice: espPath,
        mountpoint: "/boot/efi", fsType: "vfat")

    if swapPath.len > 0:
      if plan.useLuksEncryption:
        result.add setupEncryptedSwap(swapPath)
      else:
        requireOk(&"mkswap {swapPath}", "Formatowanie swap")
        requireOk(&"swapon {swapPath}", "Włączanie swap")
        result.add MountedPartition(devicePath: swapPath, fstabDevice: swapPath,
          mountpoint: "none", fsType: "swap")
    elif plan.swapMode == smFile and plan.swapSizeMiB > 0:
      let swapfilePath = createSwapfile(targetMount, plan.swapSizeMiB, plan.filesystem)
      requireOk(&"swapon {targetMount}{swapfilePath}", "Włączanie swapfile")
      result.add MountedPartition(devicePath: "", fstabDevice: swapfilePath,
        mountpoint: "none", fsType: "swap")
  except InstallerError:
    bestEffortUndo(targetMount, result, plan.useLuksEncryption)
    raise

proc applyFreeSpacePlan(plan: PartitionPlan, targetMount: string): seq[MountedPartition] =
  echo "[partitioner] Tryb 'użyj wolnej przestrzeni' -- prototyp zakłada, że " &
       "partycje 1 (ESP) i 2 (root) już istnieją i tylko je formatuje."
  let disk = plan.targetDisk.path
  let espPath = partitionPath(disk, 1)
  let rootRaw = partitionPath(disk, 2)

  result = @[]
  try:
    requireOk(&"mkfs.fat -F32 {espPath}", "Formatowanie ESP")

    var rootDevice = rootRaw
    if plan.useLuksEncryption:
      rootDevice = luksFormatAndOpen(rootRaw, plan.luksPassphrase)
    mkfsFor(plan.filesystem, rootDevice)

    createDir(targetMount)
    requireOk(&"mount {rootDevice} {targetMount}", "Montowanie roota")
    result.add MountedPartition(devicePath: rootRaw,
      fstabDevice: (if plan.useLuksEncryption: rootDevice else: rootRaw),
      mountpoint: "/", fsType: plan.filesystem, isEncrypted: plan.useLuksEncryption)

    createDir(targetMount / "boot" / "efi")
    requireOk(&"mount {espPath} {targetMount / \"boot\" / \"efi\"}", "Montowanie ESP")
    result.add MountedPartition(devicePath: espPath, fstabDevice: espPath,
      mountpoint: "/boot/efi", fsType: "vfat")

    if plan.swapMode != smNone and plan.swapSizeMiB > 0:
      echo &"[partitioner] Pomijam swap w trybie 'wolna przestrzeń' -- brak " &
           &"miejsca na nową partycję w tym prototypie (swapSizeMiB={plan.swapSizeMiB} zignorowane)."
  except InstallerError:
    bestEffortUndo(targetMount, result, plan.useLuksEncryption)
    raise

proc applyManualPlan(plan: PartitionPlan, targetMount: string): seq[MountedPartition] =
  let m = plan.manual
  if m.rootPart.len == 0:
    raise newException(InstallerError, "Partycjonowanie ręczne: nie wybrano partycji roota")

  result = @[]
  try:
    var rootDevice = m.rootPart
    let rootRaw = m.rootPart
    if plan.useLuksEncryption:
      if m.formatRoot:
        rootDevice = luksFormatAndOpen(m.rootPart, plan.luksPassphrase)
      else:
        requireOk(&"cryptsetup status {LuksMapperName}", "Sprawdzanie otwartego kontenera LUKS")
        rootDevice = "/dev/mapper/" & LuksMapperName

    if m.formatRoot:
      mkfsFor(plan.filesystem, rootDevice)

    var rootOpts, homeOpts = ""
    let useBtrfsSubvolumes = plan.filesystem == "btrfs" and m.formatRoot and m.homePart.len == 0
    if useBtrfsSubvolumes:
      let subvolOpts = createBtrfsSubvolumes(rootDevice, targetMount)
      rootOpts = subvolOpts.rootOpts
      homeOpts = subvolOpts.homeOpts

    createDir(targetMount)
    if useBtrfsSubvolumes:
      requireOk(&"mount -o {rootOpts} {rootDevice} {targetMount}", "Montowanie roota (subvol=@)")
    else:
      requireOk(&"mount {rootDevice} {targetMount}", "Montowanie roota")

    result.add MountedPartition(devicePath: rootRaw,
      fstabDevice: (if plan.useLuksEncryption: rootDevice else: rootRaw),
      mountpoint: "/", fsType: plan.filesystem,
      isEncrypted: plan.useLuksEncryption, extraMountOptions: rootOpts)

    if useBtrfsSubvolumes:
      createDir(targetMount / "home")
      requireOk(&"mount -o {homeOpts} {rootDevice} {targetMount / \"home\"}", "Montowanie @home")
      result.add MountedPartition(devicePath: rootRaw,
        fstabDevice: (if plan.useLuksEncryption: rootDevice else: rootRaw),
        mountpoint: "/home", fsType: plan.filesystem,
        isEncrypted: plan.useLuksEncryption, extraMountOptions: homeOpts)

    if m.espPart.len > 0:
      if m.formatEsp:
        requireOk(&"mkfs.fat -F32 {m.espPart}", "Formatowanie ESP")
      createDir(targetMount / "boot" / "efi")
      requireOk(&"mount {m.espPart} {targetMount / \"boot\" / \"efi\"}", "Montowanie ESP")
      result.add MountedPartition(devicePath: m.espPart, fstabDevice: m.espPart,
        mountpoint: "/boot/efi", fsType: "vfat")
    # m.biosGrubPart: celowo pomijane -- to surowa partycja, GRUB pisze na niej
    # bezpośrednio przy grub-install, nigdy nie jest formatowana ani montowana.

    if not useBtrfsSubvolumes and m.homePart.len > 0:
      if m.formatHome:
        mkfsFor(plan.filesystem, m.homePart)
      createDir(targetMount / "home")
      requireOk(&"mount {m.homePart} {targetMount / \"home\"}", "Montowanie /home")
      result.add MountedPartition(devicePath: m.homePart, fstabDevice: m.homePart,
        mountpoint: "/home", fsType: plan.filesystem)

    if m.swapPart.len > 0:
      if plan.useLuksEncryption:
        result.add setupEncryptedSwap(m.swapPart)
      else:
        requireOk(&"mkswap {m.swapPart}", "Formatowanie swap")
        requireOk(&"swapon {m.swapPart}", "Włączanie swap")
        result.add MountedPartition(devicePath: m.swapPart, fstabDevice: m.swapPart,
          mountpoint: "none", fsType: "swap")
    elif m.swapFileSizeMiB > 0:
      let swapfilePath = createSwapfile(targetMount, m.swapFileSizeMiB, plan.filesystem)
      requireOk(&"swapon {targetMount}{swapfilePath}", "Włączanie swapfile")
      result.add MountedPartition(devicePath: "", fstabDevice: swapfilePath,
        mountpoint: "none", fsType: "swap")
  except InstallerError:
    bestEffortUndo(targetMount, result, plan.useLuksEncryption)
    raise

proc applyPartitionPlan*(plan: PartitionPlan, targetMount: string): seq[MountedPartition] =
  case plan.mode
  of pmEraseDisk: applyErasePlan(plan, targetMount)
  of pmUseFreeSpace: applyFreeSpacePlan(plan, targetMount)
  of pmManual: applyManualPlan(plan, targetMount)

proc unmountTarget*(targetMount: string, hadLuks: bool, swapPartitions: seq[string] = @[]) =
  for sw in swapPartitions:
    if sw.len > 0: discard run(&"swapoff {sw}")
  discard run(&"umount -R {targetMount}")
  if hadLuks:
    discard run(&"cryptsetup close {LuksMapperName}")
    discard run(&"cryptsetup close {LuksSwapMapperName}")
