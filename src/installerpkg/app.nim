import std/[os, strutils]
import fidget
import ./types
import ./diskutil
import ./liveenv
import ./executor
import ./netcheck
import ./validation
import ./i18n
import ./widgets

const DistroName = "Zenit Linux"
const WindowW = 1280.0
const WindowH = 800.0
const SidebarW = 220.0
const DefaultSwapSizeMiB = 2048

const AvailableLanguages = [
  ("pl_PL.UTF-8", "Polski"),
  ("en_US.UTF-8", "English (US)"),
  ("de_DE.UTF-8", "Deutsch"),
  ("fr_FR.UTF-8", "Français"),
  ("es_ES.UTF-8", "Español"),
]

const AvailableKeyboardLayouts = ["pl", "us", "de", "fr", "es"]

const AvailableTimezones = [
  "Europe/Warsaw", "Europe/Berlin", "Europe/London",
  "Europe/Paris", "America/New_York", "UTC",
]

const OptionalPackageCatalog = [
  ("firefox -> flatpak", "Firefox (przeglądarka)"),
  ("libreoffice -> flatpak", "LibreOffice (biuro)"),
  ("gimp -> flatpak", "GIMP (grafika)"),
  ("vscode -> own", "Visual Studio Code"),
  ("steam -> flatpak", "Steam (gry)"),
]

type
  AppState = object
    step: WizardStep
    fullscreen: bool
    launchMode: BootLaunchMode

    languageIdx: int
    keyboardIdx: int
    timezoneIdx: int

    networkChecked: bool
    networkOk: bool

    disks: seq[DiskInfo]
    selectedDiskIdx: int
    liveDiskConfirmed: bool

    partitionMode: PartitionMode
    bootloaderMode: BootloaderMode
    eraseConfirmed: bool
    filesystem: string
    swapMode: SwapMode
    swapSizeMiB: int
    useLuks: bool
    luksPassphrase: string
    luksPassphraseConfirm: string

    diskPartitions: seq[PartitionInfo]
    manualEspIdx: int
    manualBiosGrubIdx: int
    manualRootIdx: int
    manualHomeIdx: int
    manualSwapIdx: int
    manualSwapFile: bool
    manualSwapFileSizeMiB: int

    otherOses: seq[string]
    otherOsesChecked: bool

    fullName, username, hostname, password, passwordConfirm, rootPassword: string
    autoLogin: bool

    selectedPackages: seq[bool]

    progressPercent: float
    progressStepName: string
    progressLog: seq[string]
    installFailed: bool
    errorMessage: string

var app = AppState(
  step: stepWelcome,
  launchMode: detectBootLaunchMode(),
  selectedDiskIdx: -1,
  partitionMode: pmEraseDisk,
  bootloaderMode: detectFirmwareMode(),
  filesystem: "ext4",
  swapMode: smNone,
  swapSizeMiB: DefaultSwapSizeMiB,
  hostname: "zenit",
  selectedPackages: newSeq[bool](OptionalPackageCatalog.len),
  manualEspIdx: -1,
  manualBiosGrubIdx: -1,
  manualRootIdx: -1,
  manualHomeIdx: -1,
  manualSwapIdx: -1,
  manualSwapFileSizeMiB: DefaultSwapSizeMiB,
)

proc stepIndex(s: WizardStep): int =
  case s
  of stepWelcome: 0
  of stepLanguage: 1
  of stepKeyboard: 2
  of stepNetwork: 3
  of stepDisk: 4
  of stepPartition: 5
  of stepManualPartitions: 5 # ta sama pozycja w pasku bocznym co "Partycjonowanie"
  of stepAccount: 6
  of stepSummary: 7
  else: 8

proc stepTitles(): array[8, string] =
  [t("nav_welcome"), t("nav_language"), t("nav_keyboard"), t("nav_network"),
   t("nav_disk"), t("nav_partition"), t("nav_account"), t("nav_summary")]

proc manualSelectionsUnique(): bool =
  ## Ta sama partycja przypisana do więcej niż jednej roli sformatowałaby/
  ## nadpisała dane po drodze -- patrz partitioner.applyManualPlan, które
  ## montuje/formatuje każdą rolę niezależnie i nie ma jak tego wykryć samo.
  var chosen: seq[int] = @[]
  if app.bootloaderMode == bmUefi:
    if app.manualEspIdx >= 0: chosen.add app.manualEspIdx
  else:
    if app.manualBiosGrubIdx >= 0: chosen.add app.manualBiosGrubIdx
  if app.manualRootIdx >= 0: chosen.add app.manualRootIdx
  if app.manualHomeIdx >= 0: chosen.add app.manualHomeIdx
  if not app.manualSwapFile and app.manualSwapIdx >= 0: chosen.add app.manualSwapIdx
  for i in 0 ..< chosen.len:
    for j in i + 1 ..< chosen.len:
      if chosen[i] == chosen[j]: return false
  true

proc buildPlan(): InstallPlan =
  let disk = app.disks[app.selectedDiskIdx]

  var manual = ManualPartitionAssignment(formatEsp: true, formatRoot: true, formatHome: true)
  if app.partitionMode == pmManual:
    if app.bootloaderMode == bmUefi and app.manualEspIdx >= 0:
      manual.espPart = app.diskPartitions[app.manualEspIdx].path
    if app.bootloaderMode == bmBiosLegacy and app.manualBiosGrubIdx >= 0:
      manual.biosGrubPart = app.diskPartitions[app.manualBiosGrubIdx].path
    if app.manualRootIdx >= 0:
      manual.rootPart = app.diskPartitions[app.manualRootIdx].path
    if app.manualHomeIdx >= 0:
      manual.homePart = app.diskPartitions[app.manualHomeIdx].path
    if app.manualSwapIdx >= 0:
      manual.swapPart = app.diskPartitions[app.manualSwapIdx].path
    elif app.manualSwapFile:
      manual.swapFileSizeMiB = app.manualSwapFileSizeMiB

  InstallPlan(
    locale: LocaleChoice(
      language: AvailableLanguages[app.languageIdx][0],
      keyboardLayout: AvailableKeyboardLayouts[app.keyboardIdx],
      timezone: AvailableTimezones[app.timezoneIdx],
    ),
    partition: PartitionPlan(
      targetDisk: disk,
      mode: app.partitionMode,
      bootloaderMode: app.bootloaderMode,
      useLuksEncryption: app.useLuks,
      luksPassphrase: app.luksPassphrase,
      swapMode: app.swapMode,
      swapSizeMiB: (if app.swapMode != smNone: app.swapSizeMiB else: 0),
      filesystem: app.filesystem,
      manual: manual,
    ),
    account: UserAccount(
      fullName: app.fullName,
      username: app.username,
      hostname: app.hostname,
      password: app.password,
      rootPassword: app.rootPassword,
      autoLogin: app.autoLogin,
    ),
    extraPackages: block:
      var pkgs: seq[string] = @[]
      for i, sel in app.selectedPackages:
        if sel: pkgs.add OptionalPackageCatalog[i][0]
      pkgs
  )

proc startInstall() =
  app.installFailed = false
  app.errorMessage = ""
  app.progressLog = @[]
  app.progressPercent = 0.0
  app.progressStepName = ""
  app.step = stepInstalling
  let plan = buildPlan()
  # Instalacja jest blokująca I/O-bound (chroot/mkfs/zpm) -- odpalona na
  # wątku roboczym (executor.startInstallAsync), żeby nie zamrozić pętli
  # renderowania Fidget. `pollInstall()` (wołane co klatkę z drawMain)
  # odbiera postęp przez kanał i aktualizuje `app`.
  startInstallAsync(plan, DistroName)

proc pollInstall() =
  if app.step != stepInstalling: return
  for p in pollInstallProgress():
    app.progressStepName = p.stepName
    app.progressPercent = p.percent
    if p.logLine.len > 0:
      app.progressLog.add p.logLine
    if p.status == ssFailed:
      app.installFailed = true
      app.errorMessage = p.logLine
      app.step = stepError
    elif p.status == ssDone and p.percent >= 99.99:
      app.step = stepDone

proc drawSidebar() =
  group "sidebar":
    box 0, 0, SidebarW, WindowH
    fill widgets.ColorBgAlt
    for i, title in stepTitles():
      sidebarItem("nav-" & $i, title, 16, 90 + i.float * 46, SidebarW - 32, 38,
        active = stepIndex(app.step) == i, done = stepIndex(app.step) > i)
    heading("brand", DistroName, 20, 24, SidebarW - 40, 20)

proc drawWelcome(x0: float) =
  heading("w-title", t("w_title", DistroName), x0, 100, 760, 34)
  paragraph("w-body", t("w_body", DistroName), x0, 150, 700, 90)
  var y = 260.0
  if app.launchMode == blmStandalone:
    paragraph("w-standalone", t("w_standalone_warning"), x0, y, 700, 44)
    y += 60
  paragraph("w-theme-label", t("w_theme_label"), x0, y, 300, 22)
  y += 30
  choiceChip("theme-dark", t("w_theme_dark"), x0, y, 140, 40,
    currentTheme == themeDark, proc() = applyTheme(themeDark))
  choiceChip("theme-light", t("w_theme_light"), x0 + 150, y, 140, 40,
    currentTheme == themeLight, proc() = applyTheme(themeLight))
  y += 56
  button("w-start", t("btn_start"), x0, y, 200, 52, primary = true,
    onClickAction = proc() = app.step = stepLanguage)

proc drawLanguage(x0: float) =
  heading("l-title", t("l_title"), x0, 90, 700, 30)
  for i, lang in AvailableLanguages:
    choiceChip("lang-" & $i, lang[1], x0, 150 + i.float * 54, 320, 44,
      app.languageIdx == i, proc() = app.languageIdx = i)
  button("l-back", t("btn_back"), x0, 620, 140, 46,
    onClickAction = proc() = app.step = stepWelcome)
  button("l-next", t("btn_next"), x0 + 160, 620, 140, 46, primary = true,
    onClickAction = proc() =
      setUiLanguage(AvailableLanguages[app.languageIdx][0])
      app.step = stepKeyboard)

proc drawKeyboard(x0: float) =
  heading("k-title", t("k_title"), x0, 90, 700, 30)
  paragraph("k-kb-label", t("k_kb_label"), x0, 140, 400, 24)
  for i, layout in AvailableKeyboardLayouts:
    choiceChip("kb-" & $i, layout, x0 + i.float * 90, 170, 80, 40,
      app.keyboardIdx == i, proc() = app.keyboardIdx = i)
  paragraph("k-tz-label", t("k_tz_label"), x0, 230, 400, 24)
  for i, tz in AvailableTimezones:
    choiceChip("tz-" & $i, tz, x0, 260 + i.float * 48, 260, 40,
      app.timezoneIdx == i, proc() = app.timezoneIdx = i)
  button("k-back", t("btn_back"), x0, 620, 140, 46,
    onClickAction = proc() = app.step = stepLanguage)
  button("k-next", t("btn_next"), x0 + 160, 620, 140, 46, primary = true,
    onClickAction = proc() = app.step = stepNetwork)

proc drawNetwork(x0: float) =
  heading("n-title", t("n_title"), x0, 90, 700, 30)
  paragraph("n-body", t("n_body"), x0, 150, 700, 70)
  button("n-check", t("btn_check_connection"), x0, 230, 240, 44,
    onClickAction = proc() =
      app.networkChecked = true
      app.networkOk = hasInternetConnection())
  if app.networkChecked:
    paragraph("n-result", (if app.networkOk: t("n_result_ok") else: t("n_result_fail")),
      x0, 284, 700, 26)
  button("n-back", t("btn_back"), x0, 340, 140, 46,
    onClickAction = proc() = app.step = stepKeyboard)
  button("n-next", t("btn_next"), x0 + 160, 340, 140, 46, primary = true,
    onClickAction = proc() =
      app.disks = listDisks()
      try:
        app.otherOses = detectOtherOperatingSystems()
      except CatchableError:
        app.otherOses = @[]
      app.otherOsesChecked = true
      app.step = stepDisk)

proc diskLabel(d: DiskInfo): string =
  result = d.path & "   " & d.model & "   (" & humanSize(d.sizeBytes) & ")"
  if d.isRemovable: result.add t("tag_removable")
  if d.isLiveMedium: result.add t("tag_live")

proc drawDisk(x0: float) =
  heading("d-title", t("d_title"), x0, 90, 700, 30)
  if app.disks.len == 0:
    paragraph("d-empty", t("d_empty"), x0, 150, 700, 40)
  for i, d in app.disks:
    choiceChip("disk-" & $i, diskLabel(d), x0, 150 + i.float * 54, 700, 44,
      app.selectedDiskIdx == i,
      proc() =
        app.selectedDiskIdx = i
        app.liveDiskConfirmed = false)
  var y = 150.0 + app.disks.len.float * 54 + 16
  if app.otherOsesChecked and app.otherOses.len > 0:
    paragraph("d-dualboot", t("d_dualboot", app.otherOses.join(", ")), x0, y, 700, 44)
    y += 54

  var canProceed = app.selectedDiskIdx >= 0
  if app.selectedDiskIdx >= 0:
    let disk = app.disks[app.selectedDiskIdx]
    if disk.sizeBytes < MinInstallDiskSizeBytes:
      paragraph("d-too-small", t("d_too_small", humanSize(MinInstallDiskSizeBytes)), x0, y, 700, 30)
      y += 40
      canProceed = false
    elif disk.isLiveMedium:
      paragraph("d-live-warn", t("d_live_warning"), x0, y, 700, 44)
      y += 50
      checkbox("d-live-confirm", t("d_live_confirm"), x0, y, 400, app.liveDiskConfirmed)
      y += 46
      canProceed = app.liveDiskConfirmed

  button("d-back", t("btn_back"), x0, 700, 140, 46,
    onClickAction = proc() = app.step = stepNetwork)
  button("d-next", t("btn_next"), x0 + 160, 700, 140, 46,
    primary = true, enabled = canProceed,
    onClickAction = proc() =
      if canProceed: app.step = stepPartition)

proc drawPartition(x0: float) =
  heading("p-title", t("p_title"), x0, 90, 700, 30)
  if app.selectedDiskIdx >= 0:
    paragraph("p-disk", t("p_disk", app.disks[app.selectedDiskIdx].path), x0, 128, 700, 22)

  paragraph("p-mode-label", t("p_mode_label"), x0, 158, 400, 22)
  choiceChip("mode-erase", t("p_mode_erase"), x0, 186, 210, 40,
    app.partitionMode == pmEraseDisk, proc() = app.partitionMode = pmEraseDisk)
  choiceChip("mode-manual", t("p_mode_manual"), x0 + 220, 186, 260, 40,
    app.partitionMode == pmManual, proc() = app.partitionMode = pmManual)

  paragraph("p-boot-label", t("p_boot_label"), x0, 240, 400, 22)
  choiceChip("boot-uefi", t("p_boot_uefi"), x0, 268, 140, 40,
    app.bootloaderMode == bmUefi, proc() = app.bootloaderMode = bmUefi)
  choiceChip("boot-bios", t("p_boot_bios"), x0 + 150, 268, 180, 40,
    app.bootloaderMode == bmBiosLegacy, proc() = app.bootloaderMode = bmBiosLegacy)

  var y = 322.0
  if app.partitionMode == pmEraseDisk:
    if app.selectedDiskIdx >= 0:
      paragraph("p-warn", t("p_warn", app.disks[app.selectedDiskIdx].path), x0, y, 700, 26)
      y += 30
      let dualBootHere = diskutil.filterOsesOnDisk(app.otherOses, app.disks[app.selectedDiskIdx].path)
      if dualBootHere.len > 0:
        paragraph("p-erase-dualboot", t("p_erase_dualboot_warn", dualBootHere.join(", ")), x0, y, 700, 34)
        y += 34
    else:
      y += 30
    checkbox("p-confirm", t("p_confirm"), x0, y, 400, app.eraseConfirmed)
    y += 40
    paragraph("p-fs-label", t("p_fs_label"), x0, y, 400, 22)
    y += 24
    for i, fs in ["ext4", "btrfs", "xfs"]:
      choiceChip("fs-" & $i, fs, x0 + i.float * 110, y, 100, 40,
        app.filesystem == fs, proc() = app.filesystem = fs)
    y += 46
    paragraph("p-swap-label", t("p_swap_label"), x0, y, 400, 22)
    y += 24
    choiceChip("swap-none", t("p_swap_none"), x0, y, 120, 40,
      app.swapMode == smNone, proc() = app.swapMode = smNone)
    choiceChip("swap-part", t("p_swap_partition"), x0 + 130, y, 190, 40,
      app.swapMode == smPartition, proc() = app.swapMode = smPartition)
    choiceChip("swap-file", t("p_swap_file"), x0 + 330, y, 220, 40,
      app.swapMode == smFile, proc() = app.swapMode = smFile)
    if app.swapMode != smNone:
      sizeStepper("swap-size", x0 + 560, y, 220, 40, app.swapSizeMiB, 256, 256, 65536)
    y += 44
  else:
    app.eraseConfirmed = true # tryb ręczny nie kasuje niczego automatycznie
    paragraph("p-manual-info", t("p_manual_info"), x0, y, 700, 44)
    y += 60

  checkbox("p-encrypt", t("p_encrypt"), x0, y, 340, app.useLuks)
  y += 36
  var luksOk = true
  if app.useLuks:
    paragraph("p-luks-warn", t("p_luks_warn"), x0, y, 700, 24)
    y += 26
    passwordField("p-luks-pass", t("p_luks_pass"), x0, y, 420, 44, app.luksPassphrase)
    y += 48
    passwordField("p-luks-pass2", t("p_luks_pass2"), x0, y, 420, 44, app.luksPassphraseConfirm)
    y += 34
    let luksLongEnough = app.luksPassphrase.len >= MinPasswordLength
    luksOk = luksLongEnough and app.luksPassphrase == app.luksPassphraseConfirm
    if app.luksPassphrase.len > 0 and not luksLongEnough:
      paragraph("p-luks-short", t("val_password_min", $MinPasswordLength), x0, y, 400, 22)
      y += 22
    elif app.luksPassphrase.len > 0 and app.luksPassphraseConfirm.len > 0 and not luksOk:
      paragraph("p-luks-mismatch", t("p_luks_mismatch"), x0, y, 400, 22)
      y += 22
    y += 6

  button("p-back", t("btn_back"), x0, y, 140, 46,
    onClickAction = proc() = app.step = stepDisk)

  let canProceed = (app.partitionMode == pmEraseDisk or app.partitionMode == pmManual) and
                    (app.partitionMode != pmEraseDisk or app.eraseConfirmed) and luksOk
  button("p-next", t("btn_next"), x0 + 160, y, 140, 46, primary = true, enabled = canProceed,
    onClickAction = proc() =
      if not canProceed: return
      if app.partitionMode == pmManual:
        app.diskPartitions = listPartitions(app.disks[app.selectedDiskIdx].path)
        app.step = stepManualPartitions
      else:
        app.step = stepAccount)

proc roleSelector(idPrefix, label: string, x0, y: float, parts: seq[PartitionInfo],
                   selected: int, allowNone: bool, onSelect: proc(idx: int)) =
  paragraph(idPrefix & "-label", label, x0, y, 600, 20)
  var cx = x0
  let cy = y + 24
  if allowNone:
    choiceChip(idPrefix & "-none", t("mp_none"), cx, cy, 90, 36,
      selected == -1, proc() = onSelect(-1))
    cx += 100
  for i, p in parts:
    let lbl = p.path & " (" & humanSize(p.sizeBytes) &
              (if p.fsType.len > 0: ", " & p.fsType else: "") & ")"
    choiceChip(idPrefix & "-" & $i, lbl, cx, cy, 230, 36,
      selected == i, proc() = onSelect(i))
    cx += 240

proc drawManualPartitions(x0: float) =
  heading("mp-title", t("mp_title"), x0, 90, 700, 30)
  let parts = app.diskPartitions
  if parts.len == 0:
    paragraph("mp-empty", t("mp_empty"), x0, 130, 700, 40)

  var y = 140.0
  if app.bootloaderMode == bmUefi:
    roleSelector("mp-esp", t("mp_esp"), x0, y, parts, app.manualEspIdx, false,
      proc(idx: int) = app.manualEspIdx = idx)
  else:
    roleSelector("mp-bg", t("mp_bg"), x0, y, parts, app.manualBiosGrubIdx, false,
      proc(idx: int) = app.manualBiosGrubIdx = idx)
  y += 72
  roleSelector("mp-root", t("mp_root"), x0, y, parts, app.manualRootIdx, false,
    proc(idx: int) = app.manualRootIdx = idx)
  y += 72
  roleSelector("mp-home", t("mp_home"), x0, y, parts, app.manualHomeIdx, true,
    proc(idx: int) = app.manualHomeIdx = idx)
  y += 72
  roleSelector("mp-swap", t("mp_swap"), x0, y, parts, app.manualSwapIdx, true,
    proc(idx: int) =
      app.manualSwapIdx = idx
      if idx >= 0: app.manualSwapFile = false)
  y += 60
  if app.manualSwapIdx < 0:
    checkbox("mp-swapfile", t("mp_swapfile"), x0, y, 500, app.manualSwapFile)
    if app.manualSwapFile:
      sizeStepper("mp-swapfile-size", x0 + 510, y - 8, 220, 40, app.manualSwapFileSizeMiB, 256, 256, 65536)
    y += 40
  y += 20

  var rootTooSmall = false
  if app.manualRootIdx >= 0 and app.manualRootIdx < parts.len:
    rootTooSmall = parts[app.manualRootIdx].sizeBytes < MinRootPartitionSizeBytes

  let bootRoleOk = (if app.bootloaderMode == bmUefi: app.manualEspIdx >= 0
                     else: app.manualBiosGrubIdx >= 0)
  let unique = manualSelectionsUnique()
  let canProceed = app.manualRootIdx >= 0 and bootRoleOk and unique and not rootTooSmall

  if not unique:
    paragraph("mp-dup-warn", t("mp_duplicate"), x0, y, 700, 26)
    y += 32
  if rootTooSmall:
    paragraph("mp-small-warn", t("mp_too_small", humanSize(MinRootPartitionSizeBytes)), x0, y, 700, 26)
    y += 32

  button("mp-back", t("btn_back"), x0, y, 140, 46,
    onClickAction = proc() = app.step = stepPartition)
  button("mp-next", t("btn_next"), x0 + 160, y, 140, 46, primary = true, enabled = canProceed,
    onClickAction = proc() =
      if canProceed: app.step = stepAccount)

proc drawAccount(x0: float) =
  heading("a-title", t("a_title"), x0, 90, 700, 30)
  textField("a-fullname", t("a_fullname"), x0, 140, 420, 44, app.fullName)
  textField("a-username", t("a_username"), x0, 194, 420, 44, app.username)
  let usernameValid = app.username.len == 0 or isValidUsername(app.username)
  if not usernameValid:
    paragraph("a-username-hint", t("a_username_hint"), x0 + 430, 206, 320, 20)
  textField("a-hostname", t("a_hostname"), x0, 248, 420, 44, app.hostname)
  let hostnameValid = app.hostname.len == 0 or isValidHostname(app.hostname)
  if not hostnameValid:
    paragraph("a-hostname-hint", t("a_hostname_hint"), x0 + 430, 260, 320, 20)
  passwordField("a-password", t("a_password"), x0, 302, 420, 44, app.password)
  passwordField("a-password2", t("a_password2"), x0, 356, 420, 44, app.passwordConfirm)
  let passwordLongEnough = app.password.len == 0 or app.password.len >= MinPasswordLength
  let passwordsMatch = app.password.len == 0 or app.password == app.passwordConfirm
  if not passwordLongEnough:
    paragraph("a-password-hint", t("val_password_min", $MinPasswordLength), x0 + 430, 314, 320, 20)
  elif not passwordsMatch:
    paragraph("a-password-hint", t("a_password_mismatch"), x0 + 430, 368, 320, 20)
  checkbox("a-autologin", t("a_autologin"), x0, 412, 300, app.autoLogin)

  paragraph("a-pkg-label", t("a_pkg_label"), x0, 460, 500, 24)
  for i, pkg in OptionalPackageCatalog:
    checkbox("pkg-" & $i, pkg[1], x0, 490 + i.float * 32, 400, app.selectedPackages[i])

  let canProceed = isValidUsername(app.username) and isValidHostname(app.hostname) and
                    app.password.len >= MinPasswordLength and app.password == app.passwordConfirm
  button("a-back", t("btn_back"), x0, 700, 140, 46,
    onClickAction = proc() =
      app.step = (if app.partitionMode == pmManual: stepManualPartitions else: stepPartition))
  button("a-next", t("btn_next"), x0 + 160, 700, 140, 46,
    primary = true, enabled = canProceed,
    onClickAction = proc() =
      if canProceed: app.step = stepSummary)

proc drawSummary(x0: float) =
  heading("s-title", t("s_title"), x0, 90, 700, 30)
  let disk = app.disks[app.selectedDiskIdx]
  let modeLabel = case app.partitionMode
    of pmEraseDisk: t("p_mode_erase")
    of pmManual: t("p_mode_manual")
    of pmUseFreeSpace: t("p_mode_freespace")
  paragraph("s-disk",
    t("s_disk", disk.path, humanSize(disk.sizeBytes), modeLabel, app.filesystem,
      (if app.bootloaderMode == bmUefi: t("p_boot_uefi") else: t("p_boot_bios"))),
    x0, 150, 700, 26)
  let swapLabel =
    if app.partitionMode == pmEraseDisk and app.swapMode == smPartition: t("val_swap_new_partition")
    elif app.partitionMode == pmEraseDisk and app.swapMode == smFile: t("val_swap_file")
    elif app.partitionMode == pmManual and app.manualSwapIdx >= 0: t("val_swap_existing")
    elif app.partitionMode == pmManual and app.manualSwapFile: t("val_swap_file")
    else: t("val_none")
  paragraph("s-security",
    t("s_security", (if app.useLuks: t("val_on") else: t("val_off")), swapLabel),
    x0, 178, 700, 26)
  paragraph("s-user", t("s_user", app.username, app.fullName, app.hostname), x0, 206, 700, 26)
  paragraph("s-locale",
    t("s_locale", AvailableLanguages[app.languageIdx][1], AvailableKeyboardLayouts[app.keyboardIdx],
      AvailableTimezones[app.timezoneIdx]),
    x0, 234, 700, 26)
  var y = 262.0
  if app.otherOses.len > 0:
    paragraph("s-dualboot", t("s_dualboot", app.otherOses.join(", ")), x0, y, 700, 30)
    y += 36
  paragraph("s-pkgs", t("s_pkgs"), x0, y, 700, 40)
  y += 60
  button("s-back", t("btn_back"), x0, y, 140, 46,
    onClickAction = proc() = app.step = stepAccount)
  button("s-install", t("btn_install"), x0 + 160, y, 160, 46, danger = true,
    onClickAction = proc() = startInstall())

proc drawInstalling(x0: float) =
  heading("i-title", t("i_title", DistroName), x0, 90, 700, 30)
  progressBar("i-bar", x0, 150, 700, 18, app.progressPercent / 100.0)
  paragraph("i-step", app.progressStepName, x0, 180, 700, 26)
  let logStart = max(0, app.progressLog.len - 16)
  for i in logStart ..< app.progressLog.len:
    paragraph("i-log-" & $i, app.progressLog[i], x0, 220 + (i - logStart).float * 22, 700, 20)

proc drawDone(x0: float) =
  heading("done-title", t("done_title"), x0, 120, 700, 34)
  paragraph("done-body", t("done_body", DistroName), x0, 170, 700, 30)
  button("done-reboot", t("btn_reboot"), x0, 230, 220, 52, primary = true,
    onClickAction = proc() = discard execShellCmd("systemctl reboot"))

proc drawError(x0: float) =
  heading("err-title", t("err_title"), x0, 120, 700, 34)
  paragraph("err-body", app.errorMessage, x0, 170, 700, 60)
  button("err-back", t("btn_back_to_summary"), x0, 250, 260, 46,
    onClickAction = proc() = app.step = stepSummary)

proc drawMain() =
  setTitle(DistroName & " Installer")
  pollInstall()
  frame "root":
    box 0, 0, WindowW, WindowH
    fill widgets.ColorBg

    let showSidebar = app.step notin {stepWelcome, stepInstalling, stepDone, stepError}
    let x0 = if showSidebar: SidebarW + 60 else: 60.0

    if showSidebar:
      drawSidebar()

    case app.step
    of stepWelcome: drawWelcome(x0)
    of stepLanguage: drawLanguage(x0)
    of stepKeyboard: drawKeyboard(x0)
    of stepNetwork: drawNetwork(x0)
    of stepDisk: drawDisk(x0)
    of stepPartition: drawPartition(x0)
    of stepManualPartitions: drawManualPartitions(x0)
    of stepAccount: drawAccount(x0)
    of stepSummary: drawSummary(x0)
    of stepInstalling: drawInstalling(x0)
    of stepDone: drawDone(x0)
    of stepError: drawError(x0)

const FontRelPath = "fonts/UiFont-Regular.ttf"
  ## Ścieżka WZGLĘDEM katalogu "data/" -- Fidget (`loadFont`/`startFidget`)
  ## doklejają "data/" automatycznie do każdej ścieżki assetu, więc
  ## rzeczywisty plik na dysku to "data/" & FontRelPath (patrz
  ## `checkFontAvailable` niżej i data/fonts/README.md).

proc checkFontAvailable(): bool =
  ## Sprawdzane PRZED `loadFont`, żeby dać czytelny komunikat po polsku
  ## zamiast surowego IOError/KeyError z głębi Fidget/pixie (dokładnie to
  ## się stało w praktyce: brak pliku dawał nieczytelne "File ... does not
  ## exist", a uszkodzony/zły plik -- "key not found: head" przy próbie
  ## odczytania tabeli sfnt).
  let fullPath = "data" / FontRelPath
  if not fileExists(fullPath):
    stderr.writeLine("Brak pliku fontu: " & fullPath)
    stderr.writeLine("Katalog 'data/' (z fontem UI, patrz data/fonts/) musi leżeć " &
      "obok binarki -- upewnij się, że go skopiowałeś/aś razem z bin/installer, " &
      "albo uruchamiasz binarkę z katalogu głównego repozytorium.")
    return false
  var content: string
  try:
    content = readFile(fullPath)
  except IOError:
    stderr.writeLine("Nie można odczytać pliku fontu: " & fullPath)
    return false
  const validMagics = ["\x00\x01\x00\x00", "OTTO", "true", "ttcf"]
  if content.len < 4 or content[0 .. 3] notin validMagics:
    stderr.writeLine("Plik fontu " & fullPath & " wygląda na uszkodzony " &
      "(nieprawidłowy nagłówek TTF/OTF) -- podmień go na poprawny plik i spróbuj ponownie.")
    return false
  true

proc runInstallerGui*(forceFullscreen = false, forceWindowed = false) =
  var auto = shouldAutoLaunchFullscreen()
  if forceFullscreen: auto = true
  if forceWindowed: auto = false
  app.fullscreen = auto

  if not checkFontAvailable():
    quit(1)

  loadFont(FontFamily, FontRelPath)

  startFidget(
    drawMain,
    w = WindowW.int,
    h = WindowH.int,
    fullscreen = app.fullscreen
  )
