import std/os
import fidget
import ./types
import ./diskutil
import ./liveenv
import ./executor
import ./widgets

const DistroName = "Zenith Linux"
const WindowW = 1280.0
const WindowH = 800.0
const SidebarW = 220.0

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

const StepTitles = ["Witaj", "Język", "Klawiatura", "Sieć", "Dysk",
                     "Partycjonowanie", "Konto", "Podsumowanie"]

type
  AppState = object
    step: WizardStep
    fullscreen: bool

    languageIdx: int
    keyboardIdx: int
    timezoneIdx: int

    disks: seq[DiskInfo]
    selectedDiskIdx: int
    eraseConfirmed: bool
    filesystem: string

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
  selectedDiskIdx: -1,
  filesystem: "ext4",
  hostname: "zenith",
  selectedPackages: newSeq[bool](OptionalPackageCatalog.len),
)

proc stepIndex(s: WizardStep): int =
  case s
  of stepWelcome: 0
  of stepLanguage: 1
  of stepKeyboard: 2
  of stepNetwork: 3
  of stepDisk: 4
  of stepPartition: 5
  of stepAccount: 6
  of stepSummary: 7
  else: 8

proc buildPlan(): InstallPlan =
  let disk = app.disks[app.selectedDiskIdx]
  InstallPlan(
    locale: LocaleChoice(
      language: AvailableLanguages[app.languageIdx][0],
      keyboardLayout: AvailableKeyboardLayouts[app.keyboardIdx],
      timezone: AvailableTimezones[app.timezoneIdx],
    ),
    partition: PartitionPlan(
      targetDisk: disk,
      mode: pmEraseDisk,
      useLuksEncryption: false,
      swapSizeMiB: 2048,
      filesystem: app.filesystem,
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

proc onInstallProgress(p: InstallProgress) {.gcsafe.} =
  ## Nazwana procedura (nie anonimowa lambda) z jawnym {.gcsafe.}:
  ## anonimowa lambda przekazana bezpośrednio do runInstall() nie
  ## przechwytuje żadnej zmiennej LOKALNEJ (tylko globalne `app`), więc
  ## Nim kompilował ją jako {.nimcall.} bez środowiska -- niezgodne z
  ## typem ProgressCallback = proc(p: InstallProgress) {.gcsafe.}, który
  ## (jako typ proc) domyślnie oczekuje konwencji {.closure.}. Nazwana
  ## procedura, przekazana przez nazwę (nie jako literał lambdy), zostaje
  ## poprawnie i niejawnie skonwertowana do closure z pustym środowiskiem
  ## -- to standardowa, dozwolona konwersja w Nim. (UWAGA: samo
  ## {.closure.} jako pragma NIE jest dozwolone na definicjach top-level,
  ## stąd brak go tutaj -- inaczej niż przy anonimowych lambdach w
  ## executor.nim, gdzie jest legalne i potrzebne.)
  {.gcsafe.}:
    app.progressStepName = p.stepName
    app.progressPercent = p.percent
    if p.logLine.len > 0:
      app.progressLog.add p.logLine
    if p.status == ssFailed:
      app.installFailed = true
      app.errorMessage = p.logLine

proc startInstall() =
  app.step = stepInstalling
  let plan = buildPlan()
  # Instalacja jest blokująca I/O-bound (chroot/mkfs/zpm). W pełnej
  # implementacji odpalana na wątku roboczym (std/threads) z kolejką
  # wiadomości odczytywaną w drawMain(), żeby nie blokować pętli
  # renderowania Fidget. Tu, dla przejrzystości prototypu, wołamy
  # bezpośrednio i aktualizujemy `app` po każdym kroku przez callback.
  try:
    runInstall(plan, DistroName, onInstallProgress)
    app.step = stepDone
  except InstallerError as e:
    app.installFailed = true
    app.errorMessage = e.msg
    app.step = stepError

proc drawSidebar() =
  group "sidebar":
    box 0, 0, SidebarW, WindowH
    fill widgets.ColorBgAlt
    for i, title in StepTitles:
      sidebarItem("nav-" & $i, title, 16, 90 + i.float * 46, SidebarW - 32, 38,
        active = stepIndex(app.step) == i, done = stepIndex(app.step) > i)
    heading("brand", DistroName, 20, 24, SidebarW - 40, 20)

proc drawWelcome(x0: float) =
  heading("w-title", "Witamy w instalatorze " & DistroName, x0, 100, 760, 34)
  paragraph("w-body",
    "Ten kreator przeprowadzi Cię przez instalację " & DistroName &
    " na tym komputerze. Wszystkie pakiety -- system bazowy i " &
    "opcjonalne oprogramowanie -- są instalowane przez zpm, " &
    "nigdy pojedynczym skryptem curl.",
    x0, 150, 700, 90)
  button("w-start", "Rozpocznij", x0, 260, 200, 52, primary = true,
    onClickAction = proc() = app.step = stepLanguage)

proc drawLanguage(x0: float) =
  heading("l-title", "Wybierz język systemu", x0, 90, 700, 30)
  for i, lang in AvailableLanguages:
    choiceChip("lang-" & $i, lang[1], x0, 150 + i.float * 54, 320, 44,
      app.languageIdx == i, proc() = app.languageIdx = i)
  button("l-back", "Wstecz", x0, 620, 140, 46,
    onClickAction = proc() = app.step = stepWelcome)
  button("l-next", "Dalej", x0 + 160, 620, 140, 46, primary = true,
    onClickAction = proc() = app.step = stepKeyboard)

proc drawKeyboard(x0: float) =
  heading("k-title", "Klawiatura i strefa czasowa", x0, 90, 700, 30)
  paragraph("k-kb-label", "Układ klawiatury", x0, 140, 400, 24)
  for i, layout in AvailableKeyboardLayouts:
    choiceChip("kb-" & $i, layout, x0 + i.float * 90, 170, 80, 40,
      app.keyboardIdx == i, proc() = app.keyboardIdx = i)
  paragraph("k-tz-label", "Strefa czasowa", x0, 230, 400, 24)
  for i, tz in AvailableTimezones:
    choiceChip("tz-" & $i, tz, x0, 260 + i.float * 48, 260, 40,
      app.timezoneIdx == i, proc() = app.timezoneIdx = i)
  button("k-back", "Wstecz", x0, 620, 140, 46,
    onClickAction = proc() = app.step = stepLanguage)
  button("k-next", "Dalej", x0 + 160, 620, 140, 46, primary = true,
    onClickAction = proc() = app.step = stepNetwork)

proc drawNetwork(x0: float) =
  heading("n-title", "Połączenie sieciowe", x0, 90, 700, 30)
  paragraph("n-body",
    "Instalator używa zpm do pobierania pakietów -- upewnij się, że masz " &
    "połączenie z internetem (Wi-Fi/Ethernet) skonfigurowane przez " &
    "NetworkManager w tej sesji live.",
    x0, 150, 700, 70)
  button("n-back", "Wstecz", x0, 260, 140, 46,
    onClickAction = proc() = app.step = stepKeyboard)
  button("n-next", "Dalej", x0 + 160, 260, 140, 46, primary = true,
    onClickAction = proc() =
      app.disks = listDisks()
      app.step = stepDisk)

proc drawDisk(x0: float) =
  heading("d-title", "Wybierz dysk docelowy", x0, 90, 700, 30)
  if app.disks.len == 0:
    paragraph("d-empty", "Nie wykryto żadnych dysków (lsblk niedostępny lub brak nośników).",
      x0, 150, 700, 40)
  for i, d in app.disks:
    let label = d.path & "   " & d.model & "   (" & humanSize(d.sizeBytes) & ")"
    choiceChip("disk-" & $i, label, x0, 150 + i.float * 54, 700, 44,
      app.selectedDiskIdx == i, proc() = app.selectedDiskIdx = i)
  button("d-back", "Wstecz", x0, 620, 140, 46,
    onClickAction = proc() = app.step = stepNetwork)
  button("d-next", "Dalej", x0 + 160, 620, 140, 46,
    primary = true, enabled = app.selectedDiskIdx >= 0,
    onClickAction = proc() =
      if app.selectedDiskIdx >= 0: app.step = stepPartition)

proc drawPartition(x0: float) =
  heading("p-title", "Partycjonowanie", x0, 90, 700, 30)
  if app.selectedDiskIdx >= 0:
    paragraph("p-warn",
      "UWAGA: cały dysk " & app.disks[app.selectedDiskIdx].path &
      " zostanie WYMAZANY i sformatowany.",
      x0, 140, 700, 40)
  checkbox("p-confirm", "Rozumiem, wymaż cały dysk", x0, 190, 400, app.eraseConfirmed)
  paragraph("p-fs-label", "System plików", x0, 240, 400, 24)
  for i, fs in ["ext4", "btrfs", "xfs"]:
    choiceChip("fs-" & $i, fs, x0 + i.float * 110, 270, 100, 40,
      app.filesystem == fs, proc() = app.filesystem = fs)
  button("p-back", "Wstecz", x0, 620, 140, 46,
    onClickAction = proc() = app.step = stepDisk)
  button("p-next", "Dalej", x0 + 160, 620, 140, 46,
    primary = true, enabled = app.eraseConfirmed,
    onClickAction = proc() =
      if app.eraseConfirmed: app.step = stepAccount)

proc drawAccount(x0: float) =
  heading("a-title", "Utwórz konto użytkownika", x0, 90, 700, 30)
  textField("a-fullname", "Imię i nazwisko", x0, 140, 420, 44, app.fullName)
  textField("a-username", "Nazwa użytkownika", x0, 194, 420, 44, app.username)
  textField("a-hostname", "Nazwa komputera", x0, 248, 420, 44, app.hostname)
  textField("a-password", "Hasło", x0, 302, 420, 44, app.password)
  textField("a-password2", "Powtórz hasło", x0, 356, 420, 44, app.passwordConfirm)
  checkbox("a-autologin", "Automatyczne logowanie", x0, 412, 300, app.autoLogin)

  paragraph("a-pkg-label", "Dodatkowe oprogramowanie (instalowane przez zpm):",
    x0, 460, 500, 24)
  for i, pkg in OptionalPackageCatalog:
    checkbox("pkg-" & $i, pkg[1], x0, 490 + i.float * 32, 400, app.selectedPackages[i])

  let canProceed = app.username.len > 0 and app.password.len > 0 and
                    app.password == app.passwordConfirm
  button("a-back", "Wstecz", x0, 700, 140, 46,
    onClickAction = proc() = app.step = stepPartition)
  button("a-next", "Dalej", x0 + 160, 700, 140, 46,
    primary = true, enabled = canProceed,
    onClickAction = proc() =
      if canProceed: app.step = stepSummary)

proc drawSummary(x0: float) =
  heading("s-title", "Podsumowanie", x0, 90, 700, 30)
  let disk = app.disks[app.selectedDiskIdx]
  paragraph("s-disk",
    "Dysk: " & disk.path & " (" & humanSize(disk.sizeBytes) & "), system plików: " & app.filesystem,
    x0, 150, 700, 26)
  paragraph("s-user",
    "Użytkownik: " & app.username & " (" & app.fullName & "), host: " & app.hostname,
    x0, 180, 700, 26)
  paragraph("s-locale",
    "Język: " & AvailableLanguages[app.languageIdx][1] &
    ", klawiatura: " & AvailableKeyboardLayouts[app.keyboardIdx] &
    ", strefa: " & AvailableTimezones[app.timezoneIdx],
    x0, 210, 700, 26)
  paragraph("s-pkgs",
    "Pakiety systemu bazowego oraz wybrane pozycje dodatkowe instalowane " &
    "wyłącznie przez zpm -- zero curl.",
    x0, 250, 700, 40)
  button("s-back", "Wstecz", x0, 320, 140, 46,
    onClickAction = proc() = app.step = stepAccount)
  button("s-install", "Instaluj", x0 + 160, 320, 160, 46, danger = true,
    onClickAction = proc() = startInstall())

proc drawInstalling(x0: float) =
  heading("i-title", "Instalowanie " & DistroName & "...", x0, 90, 700, 30)
  progressBar("i-bar", x0, 150, 700, 18, app.progressPercent / 100.0)
  paragraph("i-step", app.progressStepName, x0, 180, 700, 26)
  let logStart = max(0, app.progressLog.len - 16)
  for i in logStart ..< app.progressLog.len:
    paragraph("i-log-" & $i, app.progressLog[i], x0, 220 + (i - logStart).float * 22, 700, 20)

proc drawDone(x0: float) =
  heading("done-title", "Instalacja zakończona!", x0, 120, 700, 34)
  paragraph("done-body",
    "Możesz teraz zrestartować komputer i uruchomić " & DistroName & " z dysku.",
    x0, 170, 700, 30)
  button("done-reboot", "Uruchom ponownie", x0, 230, 220, 52, primary = true,
    onClickAction = proc() = discard execShellCmd("systemctl reboot"))

proc drawError(x0: float) =
  heading("err-title", "Instalacja nie powiodła się", x0, 120, 700, 34)
  paragraph("err-body", app.errorMessage, x0, 170, 700, 60)
  button("err-back", "Wróć do podsumowania", x0, 250, 260, 46,
    onClickAction = proc() = app.step = stepSummary)

proc drawMain() =
  setTitle(DistroName & " Installer")
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
    of stepAccount: drawAccount(x0)
    of stepSummary: drawSummary(x0)
    of stepInstalling: drawInstalling(x0)
    of stepDone: drawDone(x0)
    of stepError: drawError(x0)

proc runInstallerGui*(forceFullscreen = false, forceWindowed = false) =
  var auto = shouldAutoLaunchFullscreen()
  if forceFullscreen: auto = true
  if forceWindowed: auto = false
  app.fullscreen = auto

  loadFont(FontFamily, "assets/fonts/Inter-Regular.ttf")

  startFidget(
    drawMain,
    w = WindowW.int,
    h = WindowH.int,
    fullscreen = app.fullscreen
  )
