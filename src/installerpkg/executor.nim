import ./types
import ./partitioner
import ./zpmclient
import ./useraccount
import ./bootloader

const TargetMount = "/mnt/zenith-target"

const StepWeights = [
  ("Partycjonowanie dysku", 10.0),
  ("Inicjalizacja zpm", 5.0),
  ("Instalacja systemu bazowego", 45.0),
  ("Instalacja dodatkowych pakietów", 15.0),
  ("Konfiguracja lokalizacji i konta", 10.0),
  ("Instalacja GRUB", 10.0),
  ("Sprzątanie", 5.0),
]

proc report(cb: ProgressCallback, stepIdx: int, status: StepStatus, logLine = "") {.gcsafe.} =
  if cb.isNil: return
  var acc = 0.0
  for i in 0 ..< stepIdx: acc += StepWeights[i][1]
  if status == ssDone: acc += StepWeights[stepIdx][1]
  cb(InstallProgress(stepName: StepWeights[stepIdx][0], status: status, percent: acc, logLine: logLine))

proc baseSystemPackages(): seq[string] =
  @["base", "linux", "linux-firmware", "systemd", "zenith-init", "networkmanager", "grub", "efibootmgr"]

proc runInstall*(plan: InstallPlan, distroName: string, cb: ProgressCallback = nil) =
  # Lambdy niżej łapią `cb` (parametr, nie zmienna globalna) -- to
  # prawidłowa domknięcie/{.closure.}. Jawne {.gcsafe.} usuwa
  # niejednoznaczność przy dopasowywaniu do `proc(line: string) {.gcsafe.}`
  # oczekiwanego przez zpmclient (patrz ten sam problem i wyjaśnienie w
  # app.nim::onInstallProgress).
  try:
    # 0. Partycjonowanie ---------------------------------------------------
    report(cb, 0, ssRunning)
    discard applyPartitionPlan(plan.partition, TargetMount)
    report(cb, 0, ssDone)

    # 1. zpm init -----------------------------------------------------------
    report(cb, 1, ssRunning)
    if not zpmInitTarget(TargetMount, "", proc(l: string) {.closure, gcsafe.} = report(cb, 1, ssRunning, l)):
      raise newException(InstallerError, "zpm init nie powiodło się")
    report(cb, 1, ssDone)

    # 2. System bazowy --------------------------------------------------
    report(cb, 2, ssRunning)
    if not zpmInstallTarget(TargetMount, baseSystemPackages(), "",
                             proc(l: string) {.closure, gcsafe.} = report(cb, 2, ssRunning, l)):
      raise newException(InstallerError, "Instalacja systemu bazowego nie powiodła się")
    report(cb, 2, ssDone)

    # 3. Dodatkowe pakiety -------------------------------------------------
    report(cb, 3, ssRunning)
    if plan.extraPackages.len > 0:
      discard zpmInstallTarget(TargetMount, plan.extraPackages, "",
                                proc(l: string) {.closure, gcsafe.} = report(cb, 3, ssRunning, l))
    report(cb, 3, ssDone)

    # 4. Lokalizacja + konto ------------------------------------------------
    report(cb, 4, ssRunning)
    applyLocale(TargetMount, plan.locale)
    applyAccount(TargetMount, plan.account)
    report(cb, 4, ssDone)

    # 5. Bootloader --------------------------------------------------------
    report(cb, 5, ssRunning)
    installGrub(TargetMount, plan.partition.targetDisk.path, distroName)
    report(cb, 5, ssDone)

    # 6. Sprzątanie ----------------------------------------------------
    report(cb, 6, ssRunning)
    discard zpmSyncTarget(TargetMount)
    unmountTarget(TargetMount)
    report(cb, 6, ssDone)

  except InstallerError as e:
    if not cb.isNil:
      cb(InstallProgress(stepName: "Błąd instalacji", status: ssFailed, percent: 0.0, logLine: e.msg))
    raise
