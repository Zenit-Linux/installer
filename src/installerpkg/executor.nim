import std/typedthreads
import std/strutils
import ./types
import ./partitioner
import ./zpmclient
import ./useraccount
import ./bootloader
import ./fstab
import ./diskutil
import ./netcheck

const TargetMount = "/mnt/zenit-target"

const StepWeights = [
  ("Partycjonowanie dysku", 10.0),
  ("Inicjalizacja zpm", 5.0),
  ("Instalacja systemu bazowego", 35.0),
  ("Instalacja środowiska graficznego", 15.0),
  ("Instalacja dodatkowych pakietów", 10.0),
  ("Konfiguracja lokalizacji i konta", 10.0),
  ("Zapis /etc/fstab", 3.0),
  ("Instalacja bootloadera", 5.0),
  ("Sprzątanie", 7.0),
]

proc report(cb: ProgressCallback, stepIdx: int, status: StepStatus, logLine = "") {.gcsafe.} =
  if cb.isNil: return
  var acc = 0.0
  for i in 0 ..< stepIdx: acc += StepWeights[i][1]
  if status == ssDone: acc += StepWeights[stepIdx][1]
  cb(InstallProgress(stepName: StepWeights[stepIdx][0], status: status, percent: acc, logLine: logLine))

proc baseSystemPackages(): seq[string] =
  @["base", "linux", "linux-firmware", "systemd", "zenit-init", "networkmanager", "grub", "efibootmgr"]

proc desktopMetaPackage(desktopId: string): string =
  ## Konwencja opisana w `zlbpkg/installerconfig.nim` (repo `zlb`): każdy
  ## wpis `installer.desktops` (poza "none") odpowiada metapakietowi
  ## "zenit-desktop-<id>" (backend `own`), który zpm rozwija na pełny
  ## zestaw pakietów danego środowiska. `""`/"none" (bez GUI) zwraca pusty
  ## string -- wywołujący (runInstall, krok 3) pomija instalację w tym przypadku.
  "zenit-desktop-" & desktopId

proc runInstall*(plan: InstallPlan, distroName: string, cb: ProgressCallback = nil) =
  # `mounted` musi być zadeklarowane PRZED `try`, żeby handler `except` niżej
  # miał do niego dostęp nawet jeśli samo partycjonowanie (krok 0) rzuci
  # wyjątek, zanim zdąży cokolwiek przypisać (wtedy zostaje puste i handler
  # po prostu nic nie sprząta -- partitioner.applyPartitionPlan sam już
  # posprzątał po sobie w takim przypadku, patrz partitioner.nim::bestEffortUndo).
  var mounted: seq[MountedPartition] = @[]
  try:
    # 0. Partycjonowanie ---------------------------------------------------
    report(cb, 0, ssRunning)
    mounted = applyPartitionPlan(plan.partition, TargetMount)
    report(cb, 0, ssDone)

    # 1. zpm init -------------------------------------------------------------
    report(cb, 1, ssRunning)
    if not hasInternetConnection():
      report(cb, 1, ssRunning,
        "Ostrzeżenie: brak połączenia sieciowego -- instalacja pakietów przez zpm może się nie powieść.")
    if not zpmInitTarget(TargetMount, "", proc(l: string) {.closure, gcsafe.} = report(cb, 1, ssRunning, l)):
      raise newException(InstallerError, "zpm init nie powiodło się")
    report(cb, 1, ssDone)

    # 2. System bazowy ----------------------------------------------------
    report(cb, 2, ssRunning)
    if not zpmInstallTarget(TargetMount, baseSystemPackages(), "",
                             proc(l: string) {.closure, gcsafe.} = report(cb, 2, ssRunning, l)):
      raise newException(InstallerError, "Instalacja systemu bazowego nie powiodła się")
    report(cb, 2, ssDone)

    # 3. Środowisko graficzne -------------------------------------------------
    report(cb, 3, ssRunning)
    if plan.desktop.len > 0 and plan.desktop.toLowerAscii != "none":
      if not zpmInstallTarget(TargetMount, @[desktopMetaPackage(plan.desktop)], "",
                               proc(l: string) {.closure, gcsafe.} = report(cb, 3, ssRunning, l)):
        raise newException(InstallerError,
          "Instalacja środowiska graficznego '" & plan.desktop & "' nie powiodła się")
    report(cb, 3, ssDone)

    # 4. Dodatkowe pakiety --------------------------------------------------
    report(cb, 4, ssRunning)
    if plan.extraPackages.len > 0:
      discard zpmInstallTarget(TargetMount, plan.extraPackages, "",
                                proc(l: string) {.closure, gcsafe.} = report(cb, 4, ssRunning, l))
    report(cb, 4, ssDone)

    # 5. Lokalizacja + konto -------------------------------------------------
    report(cb, 5, ssRunning)
    applyLocale(TargetMount, plan.locale)
    applyAccount(TargetMount, plan.account)
    report(cb, 5, ssDone)

    # 6. fstab + crypttab ----------------------------------------------------
    report(cb, 6, ssRunning)
    var fstabEntries: seq[FstabEntry] = @[]
    for m in mounted:
      if m.mountpoint == "none": continue # swap dopisywane osobno niżej
      var opts = if m.mountpoint == "/": "defaults" else: "defaults,nofail"
      if m.extraMountOptions.len > 0: opts.add("," & m.extraMountOptions)
      fstabEntries.add FstabEntry(partition: m.fstabDevice, mountpoint: m.mountpoint,
        fsType: m.fsType, options: opts)
    for m in mounted:
      if m.fsType == "swap":
        fstabEntries.add FstabEntry(partition: m.fstabDevice, mountpoint: "none",
          fsType: "swap", options: "sw")
    writeFstab(TargetMount, fstabEntries)
    for m in mounted:
      if not m.isEncrypted: continue
      if m.mountpoint == "/":
        writeCrypttab(TargetMount, m.devicePath)
      elif m.fsType == "swap":
        writeSwapCrypttab(TargetMount, m.devicePath)
    report(cb, 6, ssDone)

    # 7. Bootloader -----------------------------------------------------------
    report(cb, 7, ssRunning)
    var otherOses: seq[string] = @[]
    try:
      otherOses = detectOtherOperatingSystems()
    except CatchableError:
      discard
    installBootloader(TargetMount, plan.partition.bootloaderMode,
      plan.partition.targetDisk.path, distroName,
      useLuks = plan.partition.useLuksEncryption,
      enableOsProber = otherOses.len > 0)
    enableSsdMaintenance(TargetMount, plan.partition.targetDisk)
    report(cb, 7, ssDone)

    # 8. Sprzątanie -------------------------------------------------------
    report(cb, 8, ssRunning)
    discard zpmSyncTarget(TargetMount)
    var swapParts: seq[string] = @[]
    for m in mounted:
      if m.fsType == "swap" and m.fstabDevice.len > 0: swapParts.add m.fstabDevice
    unmountTarget(TargetMount, plan.partition.useLuksEncryption, swapParts)
    report(cb, 8, ssDone)

  except InstallerError as e:
    # Best-effort sprzątanie -- jeśli partycjonowanie (krok 0) się udało, ale
    # coś PÓŹNIEJ (zpm/locale/fstab/bootloader) zawiodło, odmontuj wszystko,
    # co zdążyło się zamontować, wyłącz swap i zamknij LUKS -- żeby kolejna
    # próba instalacji nie gryzła się z resztkami tej. Błąd sprzątania nigdy
    # nie zasłania oryginalnego błędu instalacji (patrz unmountTarget --
    # wszystkie jego kroki są już same w sobie `discard`/best-effort).
    if mounted.len > 0:
      var swapParts: seq[string] = @[]
      for m in mounted:
        if m.fsType == "swap" and m.fstabDevice.len > 0: swapParts.add m.fstabDevice
      unmountTarget(TargetMount, plan.partition.useLuksEncryption, swapParts)
    if not cb.isNil:
      cb(InstallProgress(stepName: "Błąd instalacji", status: ssFailed, percent: 0.0, logLine: e.msg))
    raise

# --- Instalacja asynchroniczna (wątek roboczy) ------------------------------
#
# `runInstall` powyżej jest w pełni synchroniczne i blokujące (partycjonowanie,
# chroot, zpm to operacje I/O-bound trwające dziesiątki sekund/minuty) --
# wołanie go bezpośrednio z pętli renderowania Fidget zamroziłoby całe okno
# na czas instalacji. `startInstallAsync`/`pollInstallProgress` uruchamiają
# je na osobnym wątku (std/typedthreads, domyślne w Nim >= 2.0) i przekazują
# postęp przez `Channel`, bezpieczny do nieblokującego odpytywania
# (`tryRecv`) co klatkę z `drawMain` w app.nim.

type InstallThreadArgs = tuple[plan: InstallPlan, distroName: string]

var progressChan: Channel[InstallProgress]
progressChan.open()

var installThread: Thread[InstallThreadArgs]

proc installThreadBody(args: InstallThreadArgs) {.thread, gcsafe.} =
  let onProgress = proc(p: InstallProgress) {.closure, gcsafe.} =
    progressChan.send(p)
  try:
    runInstall(args.plan, args.distroName, onProgress)
  except InstallerError:
    discard # runInstall już wysłało ssFailed przez onProgress przed ponownym raise

proc startInstallAsync*(plan: InstallPlan, distroName: string) =
  createThread(installThread, installThreadBody, (plan, distroName))

proc pollInstallProgress*(): seq[InstallProgress] =
  ## Nieblokujące -- wyciąga wszystkie wiadomości, jakie zdążyły się
  ## nazbierać od poprzedniej klatki. Wołane co klatkę z app.nim::drawMain,
  ## tylko gdy `app.step == stepInstalling`.
  result = @[]
  while true:
    let (ok, p) = progressChan.tryRecv()
    if not ok: break
    result.add p
