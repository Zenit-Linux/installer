import std/[os, strutils, strformat, tables]
import ./types
import ./diskutil
import ./netcheck
import ./executor
import ./validation
import ./liveenv
import ./i18n

const DistroName = "Zenit Linux"

const Languages = [
  ("pl_PL.UTF-8", "Polski"),
  ("en_US.UTF-8", "English (US)"),
  ("de_DE.UTF-8", "Deutsch"),
  ("fr_FR.UTF-8", "Français"),
  ("es_ES.UTF-8", "Español"),
]
const KeyboardLayouts = ["pl", "us", "de", "fr", "es"]
const Timezones = [
  "Europe/Warsaw", "Europe/Berlin", "Europe/London",
  "Europe/Paris", "America/New_York", "UTC",
]
const Filesystems = ["ext4", "btrfs", "xfs"]
const OptionalPackageCatalog = [
  ("firefox -> flatpak", "Firefox (przeglądarka)"),
  ("libreoffice -> flatpak", "LibreOffice (biuro)"),
  ("gimp -> flatpak", "GIMP (grafika)"),
  ("vscode -> own", "Visual Studio Code"),
  ("steam -> flatpak", "Steam (gry)"),
]

const KnownAnswerKeys = [
  "language", "keyboard", "timezone",
  "disk", "partition_mode", "bootloader", "filesystem",
  "swap_mode", "swap_size_mib", "luks", "luks_passphrase",
  "manual_esp", "manual_biosgrub", "manual_root", "manual_home",
  "manual_swap", "manual_swapfile_mib",
  "fullname", "username", "hostname", "password", "root_password", "autologin",
  "extra_packages",
]

var echoCurrentlyDisabled = false

proc restoreEchoAndExit() {.noconv.} =
  ## Hak na Ctrl+C -- gdyby przerwanie trafiło w moment, gdy `askSecret`
  ## właśnie wyłączyło echo terminala (`stty -echo`), przywraca je przed
  ## zakończeniem procesu. Bez tego terminal zostałby "niemy" po Ctrl+C
  ## złapanym w trakcie wpisywania hasła.
  if echoCurrentlyDisabled:
    discard execShellCmd("stty echo 2>/dev/null")
    stdout.write("\n")
  quit(1)

setControlCHook(restoreEchoAndExit)

proc ask(prompt: string): string =
  stdout.write(prompt)
  stdout.flushFile()
  try:
    result = stdin.readLine().strip()
  except IOError:
    result = ""

proc askYesNo(prompt: string, default: bool): bool =
  let suffix = if default: " [T/n] " else: " [t/N] "
  let ans = ask(prompt & suffix).toLowerAscii()
  if ans.len == 0: return default
  ans in ["t", "tak", "y", "yes"]

proc askChoice(prompt: string, options: seq[string]): int =
  echo prompt
  for i, opt in options:
    echo "  " & $(i + 1) & ") " & opt
  while true:
    let ans = ask("Wybór [1-" & $options.len & "]: ")
    var idx = -1
    try:
      idx = parseInt(ans)
    except ValueError:
      idx = -1
    if idx >= 1 and idx <= options.len:
      return idx - 1
    echo "Nieprawidłowy wybór, spróbuj ponownie."

proc askSecret(prompt: string): string =
  ## Odczyt bez echa na terminalu (przez `stty -echo`), z tego samego
  ## powodu co maskowanie/przekazywanie haseł przez stdin gdzie indziej w
  ## tym projekcie (patrz useraccount.nim, partitioner.nim::luksFormatAndOpen)
  ## -- hasło nie powinno zostać wypisane na ekranie. Jeśli `stty` jest
  ## niedostępne albo wejście nie jest terminalem, po prostu wraca do
  ## zwykłego (widocznego) wejścia -- to tylko kosmetyka, nie bezpieczeństwo.
  ## Ctrl+C w trakcie odczytu przywraca echo przez `restoreEchoAndExit`.
  stdout.write(prompt)
  stdout.flushFile()
  let hasStty = findExe("stty").len > 0
  if hasStty:
    discard execShellCmd("stty -echo 2>/dev/null")
    echoCurrentlyDisabled = true
  try:
    result = stdin.readLine().strip()
  except IOError:
    result = ""
  if hasStty:
    discard execShellCmd("stty echo 2>/dev/null")
    echoCurrentlyDisabled = false
    stdout.write("\n")

proc askInt(prompt: string, default, minVal, maxVal: int): int =
  while true:
    let ans = ask(prompt & " [" & $default & "]: ")
    if ans.len == 0: return default
    var val = 0
    try:
      val = parseInt(ans)
    except ValueError:
      echo "?"
      continue
    if val < minVal or val > maxVal:
      echo "(" & $minVal & "-" & $maxVal & ")"
      continue
    return val

proc hasDuplicatePartitions*(paths: openArray[string]): bool =
  ## Ta sama partycja przypisana do więcej niż jednej roli sformatowałaby/
  ## nadpisała dane po drodze -- używane zarówno w trybie interaktywnym,
  ## jak i przy walidacji pliku --autoinstall.
  var chosen: seq[string] = @[]
  for p in paths:
    if p.len > 0: chosen.add p
  for i in 0 ..< chosen.len:
    for j in i + 1 ..< chosen.len:
      if chosen[i] == chosen[j]: return true
  false

proc partitionModeLabel(m: PartitionMode): string =
  case m
  of pmEraseDisk: t("p_mode_erase")
  of pmManual: t("p_mode_manual")
  of pmUseFreeSpace: t("p_mode_freespace")

proc onProgress(p: InstallProgress) {.gcsafe.} =
  case p.status
  of ssRunning:
    if p.logLine.len > 0:
      echo &"[{p.percent:.0f}%] {p.stepName}: {p.logLine}"
    else:
      echo &"[{p.percent:.0f}%] {p.stepName}..."
  of ssDone:
    echo &"[{p.percent:.0f}%] {p.stepName} -- " & t("cli_step_ok")
  of ssFailed:
    echo t("cli_step_error") & ": " & p.logLine
  of ssPending:
    discard

proc diskLabel(d: DiskInfo): string =
  result = d.path & "  " & d.model & "  (" & humanSize(d.sizeBytes) & ")"
  if d.isRemovable: result.add t("tag_removable")
  if d.isLiveMedium: result.add t("tag_live")

proc chooseDisk(disks: seq[DiskInfo]): DiskInfo =
  ## Pętla wyboru dysku z walidacją minimalnego rozmiaru i dodatkowym
  ## potwierdzeniem, jeśli wybrany dysk jest nośnikiem live -- ten sam
  ## powód co w GUI (app.nim::drawDisk), tylko liniowo.
  var diskLabels: seq[string] = @[]
  for d in disks: diskLabels.add diskLabel(d)
  while true:
    let idx = askChoice(t("cli_disk_prompt"), diskLabels)
    let disk = disks[idx]
    if disk.sizeBytes < MinInstallDiskSizeBytes:
      echo t("cli_disk_too_small", humanSize(MinInstallDiskSizeBytes))
      continue
    if disk.isLiveMedium and not askYesNo(t("cli_disk_live_confirm"), false):
      continue
    return disk

proc runInstallerCli*() =
  if detectBootLaunchMode() == blmStandalone:
    echo t("w_standalone_warning")
    echo ""
  echo t("cli_banner", DistroName)
  echo "======================================================"
  echo ""

  var langLabels: seq[string] = @[]
  for l in Languages: langLabels.add l[1]
  let langIdx = askChoice(t("cli_lang_prompt"), langLabels)
  setUiLanguage(Languages[langIdx][0])
  let kbIdx = askChoice(t("cli_kb_prompt"), @KeyboardLayouts)
  let tzIdx = askChoice(t("cli_tz_prompt"), @Timezones)

  echo ""
  echo t("cli_net_checking")
  if hasInternetConnection():
    echo t("n_result_ok")
  else:
    echo t("n_result_fail")
    if not askYesNo(t("n_continue_anyway"), false):
      echo t("cli_aborted")
      return

  let disks = listDisks()
  if disks.len == 0:
    echo t("cli_no_disks")
    return
  let disk = chooseDisk(disks)

  var otherOses: seq[string] = @[]
  try:
    otherOses = detectOtherOperatingSystems()
  except CatchableError:
    discard
  if otherOses.len > 0:
    echo t("d_dualboot", otherOses.join(", "))

  let bootloaderMode =
    if askYesNo(t("cli_boot_prompt"), detectFirmwareMode() == bmUefi):
      bmUefi
    else:
      bmBiosLegacy

  let partitionMode =
    if askYesNo(t("cli_mode_prompt", disk.path), true):
      pmEraseDisk
    else:
      pmManual

  var filesystem = "ext4"
  var swapMode = smNone
  var swapSizeMiB = 0
  var manual = ManualPartitionAssignment(formatEsp: true, formatRoot: true, formatHome: true)

  if partitionMode == pmEraseDisk:
    echo t("p_warn", disk.path)
    let dualBootHere = filterOsesOnDisk(otherOses, disk.path)
    if dualBootHere.len > 0:
      echo t("p_erase_dualboot_warn", dualBootHere.join(", "))
    if not askYesNo(t("cli_erase_confirm"), false):
      echo t("cli_aborted")
      return
    let fsIdx = askChoice(t("cli_fs_prompt"), @Filesystems)
    filesystem = Filesystems[fsIdx]
    let swapIdx = askChoice(t("cli_swap_prompt"),
      @[t("p_swap_none"), t("p_swap_partition"), t("p_swap_file")])
    swapMode = [smNone, smPartition, smFile][swapIdx]
    if swapMode != smNone:
      swapSizeMiB = askInt(t("cli_swap_size_prompt"), 2048, 256, 65536)
  else:
    let parts = listPartitions(disk.path)
    if parts.len == 0:
      echo t("cli_no_partitions")
      return
    var partLabels: seq[string] = @[]
    for p in parts:
      let fsSuffix = if p.fsType.len > 0: ", " & p.fsType else: ""
      partLabels.add p.path & " (" & humanSize(p.sizeBytes) & fsSuffix & ")"

    while true:
      if bootloaderMode == bmUefi:
        let idx = askChoice(t("mp_esp"), partLabels)
        manual.espPart = parts[idx].path
      else:
        let idx = askChoice(t("mp_bg"), partLabels)
        manual.biosGrubPart = parts[idx].path

      let rootIdx = askChoice(t("mp_root"), partLabels)
      manual.rootPart = parts[rootIdx].path
      if parts[rootIdx].sizeBytes < MinRootPartitionSizeBytes:
        echo t("cli_root_too_small", humanSize(MinRootPartitionSizeBytes))
        continue

      manual.homePart = ""
      if askYesNo(t("cli_home_ask"), false):
        let homeIdx = askChoice(t("mp_home"), partLabels)
        manual.homePart = parts[homeIdx].path

      manual.swapPart = ""
      manual.swapFileSizeMiB = 0
      if askYesNo(t("cli_swap_ask"), false):
        let swapIdx = askChoice(t("mp_swap"), partLabels)
        manual.swapPart = parts[swapIdx].path
      elif askYesNo(t("cli_swapfile_ask"), false):
        manual.swapFileSizeMiB = askInt(t("cli_swap_size_prompt"), 2048, 256, 65536)

      # Walidacja unikalności -- ta sama partycja przypisana do więcej niż
      # jednej roli sformatowałaby/nadpisałaby dane po drodze.
      if hasDuplicatePartitions([manual.espPart, manual.biosGrubPart, manual.rootPart,
                                  manual.homePart, manual.swapPart]):
        echo t("mp_duplicate")
        continue
      break

    let fsIdx = askChoice(t("cli_fs_prompt_manual"), @Filesystems)
    filesystem = Filesystems[fsIdx]

  let useLuks = askYesNo(t("cli_luks_ask"), false)
  var luksPassphrase = ""
  if useLuks:
    echo t("p_luks_warn")
    while true:
      luksPassphrase = askSecret(t("cli_luks_pass_prompt"))
      if luksPassphrase.len == 0:
        echo t("cli_luks_empty")
        continue
      if luksPassphrase.len < MinPasswordLength:
        echo t("cli_luks_too_short", $MinPasswordLength)
        continue
      let confirm = askSecret(t("cli_luks_pass2_prompt"))
      if confirm != luksPassphrase:
        echo t("p_luks_mismatch")
        continue
      break

  echo ""
  let fullName = ask(t("cli_fullname_prompt"))
  var username = ""
  while true:
    username = ask(t("cli_username_prompt"))
    if isValidUsername(username): break
    echo t("cli_username_invalid")

  var hostname = ""
  while true:
    hostname = ask(t("cli_hostname_prompt", "zenit"))
    if hostname.len == 0: hostname = "zenit"
    if isValidHostname(hostname): break
    echo t("cli_hostname_invalid")

  var password = ""
  while password.len == 0:
    password = askSecret(t("cli_password_prompt"))
    if password.len > 0 and password.len < MinPasswordLength:
      echo t("cli_password_too_short", $MinPasswordLength)
      password = ""
      continue
    let confirm = askSecret(t("cli_password2_prompt"))
    if password != confirm:
      echo t("cli_password_mismatch")
      password = ""

  let rootPassword =
    if askYesNo(t("cli_root_password_ask"), false):
      askSecret(t("cli_root_password_prompt"))
    else:
      ""

  let autoLogin = askYesNo(t("cli_autologin_ask"), false)

  var extraPackages: seq[string] = @[]
  echo ""
  echo t("a_pkg_label")
  for pkg in OptionalPackageCatalog:
    if askYesNo("  " & pkg[1] & "?", false):
      extraPackages.add pkg[0]

  let plan = InstallPlan(
    locale: LocaleChoice(
      language: Languages[langIdx][0],
      keyboardLayout: KeyboardLayouts[kbIdx],
      timezone: Timezones[tzIdx],
    ),
    partition: PartitionPlan(
      targetDisk: disk,
      mode: partitionMode,
      bootloaderMode: bootloaderMode,
      useLuksEncryption: useLuks,
      luksPassphrase: luksPassphrase,
      swapMode: swapMode,
      swapSizeMiB: swapSizeMiB,
      filesystem: filesystem,
      manual: manual,
    ),
    account: UserAccount(
      fullName: fullName,
      username: username,
      hostname: hostname,
      password: password,
      rootPassword: rootPassword,
      autoLogin: autoLogin,
    ),
    extraPackages: extraPackages,
  )

  let swapLabel =
    if partitionMode == pmEraseDisk and swapMode == smPartition: t("val_swap_new_partition")
    elif partitionMode == pmEraseDisk and swapMode == smFile: t("val_swap_file")
    elif partitionMode == pmManual and manual.swapPart.len > 0: t("val_swap_existing")
    elif partitionMode == pmManual and manual.swapFileSizeMiB > 0: t("val_swap_file")
    else: t("val_none")

  echo ""
  echo t("cli_summary_title")
  echo "  " & t("s_disk", disk.path, humanSize(disk.sizeBytes), partitionModeLabel(partitionMode),
    filesystem, (if bootloaderMode == bmUefi: t("p_boot_uefi") else: t("p_boot_bios")))
  echo "  " & t("s_security", (if useLuks: t("val_on") else: t("val_off")), swapLabel)
  echo "  " & t("s_user", username, fullName, hostname)
  if otherOses.len > 0:
    echo "  " & t("s_dualboot", otherOses.join(", "))
  echo ""

  if not askYesNo(t("cli_confirm_install"), false):
    echo t("cli_aborted")
    return

  echo ""
  try:
    runInstall(plan, DistroName, onProgress)
    echo ""
    echo t("cli_install_done")
  except InstallerError as e:
    echo ""
    echo t("cli_install_failed", e.msg)

# --- Instalacja bezobsługowa (--autoinstall=<plik>) -------------------------
#
# Prosty format klucz=wartość (bez zależności od std/parsecfg, o jedną
# nieznaną-mi-dokładnie zależność mniej) -- patrz README.md po pełną listę
# obsługiwanych kluczy i przykładowy plik.

proc parseAnswerFile*(path: string): Table[string, string] =
  result = initTable[string, string]()
  let content = readFile(path)
  for rawLine in content.splitLines():
    let line = rawLine.strip()
    if line.len == 0 or line.startsWith("#"): continue
    let eqIdx = line.find('=')
    if eqIdx < 0: continue
    let key = line[0 ..< eqIdx].strip()
    let value = line[eqIdx + 1 .. ^1].strip()
    result[key] = value

proc getOr*(cfg: Table[string, string], key, default: string): string =
  if cfg.hasKey(key): cfg[key] else: default

proc getBoolOr*(cfg: Table[string, string], key: string, default: bool): bool =
  if not cfg.hasKey(key): return default
  cfg[key].toLowerAscii() in ["1", "true", "tak", "yes", "t"]

proc getIntOr*(cfg: Table[string, string], key: string, default: int): int =
  if not cfg.hasKey(key): return default
  try:
    parseInt(cfg[key])
  except ValueError:
    default

proc runInstallerAutoinstall*(configPath: string) =
  echo t("cli_autoinstall_banner", DistroName, configPath)

  var cfg: Table[string, string]
  try:
    cfg = parseAnswerFile(configPath)
  except IOError as e:
    echo t("cli_autoinstall_read_fail", e.msg)
    return

  try:
    let perms = getFilePermissions(configPath)
    if fpGroupRead in perms or fpOthersRead in perms:
      echo t("cli_autoinstall_perm_warn", configPath)
  except OSError:
    discard

  for key in cfg.keys:
    if key notin KnownAnswerKeys:
      echo t("cli_autoinstall_unknown_key", key)

  setUiLanguage(getOr(cfg, "language", "en_US.UTF-8"))

  let disks = listDisks()
  let diskPathWanted = getOr(cfg, "disk", "")
  var diskIdx = -1
  for i, d in disks:
    if d.path == diskPathWanted: diskIdx = i
  if diskIdx < 0:
    echo t("cli_autoinstall_disk_missing", diskPathWanted)
    return
  let disk = disks[diskIdx]

  let bootloaderMode =
    if getOr(cfg, "bootloader", "uefi").toLowerAscii() == "bios": bmBiosLegacy else: bmUefi
  let partitionMode =
    if getOr(cfg, "partition_mode", "erase").toLowerAscii() == "manual": pmManual else: pmEraseDisk
  let filesystem = getOr(cfg, "filesystem", "ext4")
  let swapMode =
    case getOr(cfg, "swap_mode", "partition").toLowerAscii()
    of "file": smFile
    of "none": smNone
    else: smPartition
  let swapSizeMiB = getIntOr(cfg, "swap_size_mib", 2048)
  let useLuks = getBoolOr(cfg, "luks", false)
  let luksPassphrase = getOr(cfg, "luks_passphrase", "")
  if not useLuks and luksPassphrase.len > 0:
    echo t("cli_autoinstall_warn_luks_passphrase_ignored")

  var manual = ManualPartitionAssignment(formatEsp: true, formatRoot: true, formatHome: true)
  manual.espPart = getOr(cfg, "manual_esp", "")
  manual.biosGrubPart = getOr(cfg, "manual_biosgrub", "")
  manual.rootPart = getOr(cfg, "manual_root", "")
  manual.homePart = getOr(cfg, "manual_home", "")
  manual.swapPart = getOr(cfg, "manual_swap", "")
  manual.swapFileSizeMiB = getIntOr(cfg, "manual_swapfile_mib", 0)

  if partitionMode == pmEraseDisk:
    if manual.espPart.len > 0 or manual.biosGrubPart.len > 0 or manual.rootPart.len > 0 or
       manual.homePart.len > 0 or manual.swapPart.len > 0 or manual.swapFileSizeMiB > 0:
      echo t("cli_autoinstall_warn_ignored_manual")
    if disk.sizeBytes < MinInstallDiskSizeBytes:
      echo t("cli_autoinstall_too_small", humanSize(MinInstallDiskSizeBytes))
      return
  else:
    if cfg.hasKey("swap_mode") or cfg.hasKey("swap_size_mib"):
      echo t("cli_autoinstall_warn_ignored_swap")
    if manual.swapPart.len > 0 and manual.swapFileSizeMiB > 0:
      echo t("cli_autoinstall_warn_swap_conflict")
    if manual.rootPart.len == 0:
      echo t("cli_autoinstall_manual_root_missing")
      return
    if bootloaderMode == bmUefi and manual.espPart.len == 0:
      echo t("cli_autoinstall_missing_boot_role", "UEFI", "esp")
      return
    if bootloaderMode == bmBiosLegacy and manual.biosGrubPart.len == 0:
      echo t("cli_autoinstall_missing_boot_role", "BIOS", "biosgrub")
      return
    # Partycje wskazane w pliku odpowiedzi muszą leżeć na dysku z disk=,
    # inaczej literówka mogłaby pomieszać partycje z dwóch różnych dysków.
    for roleEntry in [("esp", manual.espPart), ("biosgrub", manual.biosGrubPart),
                       ("root", manual.rootPart), ("home", manual.homePart),
                       ("swap", manual.swapPart)]:
      let (roleName, partPath) = roleEntry
      if partPath.len > 0 and parentDiskOf(partPath) != disk.path:
        echo t("cli_autoinstall_wrong_disk", partPath, roleName, disk.path)
        return
    if hasDuplicatePartitions([manual.espPart, manual.biosGrubPart, manual.rootPart,
                                manual.homePart, manual.swapPart]):
      echo t("cli_autoinstall_duplicate")
      return
    let parts = listPartitions(disk.path)
    var rootSize: BiggestInt = -1
    for p in parts:
      if p.path == manual.rootPart: rootSize = p.sizeBytes
    if rootSize >= 0 and rootSize < MinRootPartitionSizeBytes:
      echo t("cli_autoinstall_too_small", humanSize(MinRootPartitionSizeBytes))
      return

  var extraPackages: seq[string] = @[]
  let extraRaw = getOr(cfg, "extra_packages", "")
  if extraRaw.len > 0:
    for p in extraRaw.split(','):
      let trimmed = p.strip()
      if trimmed.len > 0: extraPackages.add trimmed

  let plan = InstallPlan(
    locale: LocaleChoice(
      language: getOr(cfg, "language", "en_US.UTF-8"),
      keyboardLayout: getOr(cfg, "keyboard", "us"),
      timezone: getOr(cfg, "timezone", "UTC"),
    ),
    partition: PartitionPlan(
      targetDisk: disk,
      mode: partitionMode,
      bootloaderMode: bootloaderMode,
      useLuksEncryption: useLuks,
      luksPassphrase: luksPassphrase,
      swapMode: swapMode,
      swapSizeMiB: swapSizeMiB,
      filesystem: filesystem,
      manual: manual,
    ),
    account: UserAccount(
      fullName: getOr(cfg, "fullname", ""),
      username: getOr(cfg, "username", ""),
      hostname: getOr(cfg, "hostname", "zenit"),
      password: getOr(cfg, "password", ""),
      rootPassword: getOr(cfg, "root_password", ""),
      autoLogin: getBoolOr(cfg, "autologin", false),
    ),
    extraPackages: extraPackages,
  )

  if plan.account.username.len == 0 or plan.account.password.len == 0:
    echo t("cli_autoinstall_missing_creds")
    return
  if not isValidUsername(plan.account.username):
    echo t("cli_autoinstall_bad_username", plan.account.username)
    return
  if not isValidHostname(plan.account.hostname):
    echo t("cli_autoinstall_bad_hostname", plan.account.hostname)
    return
  if plan.account.password.len < MinPasswordLength:
    echo t("cli_password_too_short", $MinPasswordLength)
    return
  if plan.partition.useLuksEncryption and plan.partition.luksPassphrase.len < MinPasswordLength:
    echo t("cli_luks_too_short", $MinPasswordLength)
    return

  echo t("cli_autoinstall_starting")
  try:
    runInstall(plan, DistroName, onProgress)
    echo ""
    echo t("cli_install_done")
  except InstallerError as e:
    echo ""
    echo t("cli_install_failed", e.msg)
