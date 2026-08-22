type
  InstallerError* = object of CatchableError

  WizardStep* = enum
    stepWelcome, stepLanguage, stepKeyboard, stepNetwork,
    stepDisk, stepPartition, stepAccount, stepSummary,
    stepInstalling, stepDone, stepError

  DiskInfo* = object
    path*: string          ## np. "/dev/sda"
    model*: string
    sizeBytes*: BiggestInt
    isRemovable*: bool
    isSsd*: bool

  PartitionMode* = enum
    pmEraseDisk         ## wymaż cały dysk, prosty layout GPT + ext4
    pmUseFreeSpace       ## użyj wolnej przestrzeni (uproszczone w tym prototypie)
    pmManual              ## zaawansowane / ręczne (placeholder na przyszłość)

  PartitionPlan* = object
    targetDisk*: DiskInfo
    mode*: PartitionMode
    useLuksEncryption*: bool
    swapSizeMiB*: int         ## 0 = brak partycji swap
    filesystem*: string        ## "ext4", "btrfs", "xfs"

  UserAccount* = object
    fullName*: string
    username*: string
    hostname*: string
    password*: string          ## trzymane w pamięci tylko na czas instalacji
    rootPassword*: string      ## puste = zablokuj konto root (sudo zamiast)
    autoLogin*: bool

  LocaleChoice* = object
    language*: string          ## np. "pl_PL.UTF-8"
    keyboardLayout*: string     ## np. "pl"
    timezone*: string           ## np. "Europe/Warsaw"

  InstallPlan* = object
    locale*: LocaleChoice
    partition*: PartitionPlan
    account*: UserAccount
    extraPackages*: seq[string]  ## dodatkowe pakiety wybrane przez użytkownika
                                  ## (instalowane przez zpm, patrz zpmclient.nim)

  StepStatus* = enum
    ssPending, ssRunning, ssDone, ssFailed

  InstallProgress* = object
    stepName*: string
    status*: StepStatus
    percent*: float          ## 0.0 .. 100.0, ogólny postęp całej instalacji
    logLine*: string           ## ostatnia linia logu do pokazania w UI

  ProgressCallback* = proc(p: InstallProgress) {.gcsafe.}

  BootLaunchMode* = enum
    ## Skąd wystartował Zenith Installer -- patrz liveenv.nim. Odzwierciedla
    ## wybór z GRUB-a wpisany przez zlbpkg/iso.nim::writeGrubCfg.
    blmLiveOnly       ## boot=zenith bez installer=1 -- zwykła sesja live
    blmInstallerAuto  ## boot=zenith installer=1 -- pełnoekranowy instalator od razu
    blmStandalone      ## uruchomiony ręcznie z zainstalowanego systemu (reinstall/recovery)
