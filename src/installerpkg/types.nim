type
  InstallerError* = object of CatchableError

  WizardStep* = enum
    stepWelcome, stepLanguage, stepKeyboard, stepNetwork,
    stepDisk, stepPartition, stepManualPartitions, stepAccount, stepSummary,
    stepInstalling, stepDone, stepError

  DiskInfo* = object
    path*: string          ## np. "/dev/sda"
    model*: string
    sizeBytes*: BiggestInt
    isRemovable*: bool
    isSsd*: bool
    isLiveMedium*: bool     ## true jeśli na tym dysku leży aktualnie
                             ## zamontowany nośnik/root sesji live -- patrz
                             ## diskutil.detectLiveMediumDisks. NIGDY nie
                             ## powinien być wybierany bez wyraźnego,
                             ## dodatkowego potwierdzenia.

  PartitionInfo* = object
    ## Pojedyncza istniejąca partycja na wybranym dysku -- używane tylko w
    ## trybie ręcznym (pmManual), patrz diskutil.nim::listPartitions.
    path*: string           ## np. "/dev/sda1"
    sizeBytes*: BiggestInt
    fsType*: string          ## z lsblk FSTYPE, może być puste (nieznany/surowy)

  PartitionMode* = enum
    pmEraseDisk         ## wymaż cały dysk, prosty layout GPT (ESP/bios_grub + swap? + root)
    pmUseFreeSpace       ## użyj wolnej przestrzeni (uproszczone w tym prototypie)
    pmManual              ## przypisanie istniejących partycji do ról, patrz
                            ## ManualPartitionAssignment -- same partycje nie są
                            ## tworzone ani zmieniane rozmiarowo przez instalator

  BootloaderMode* = enum
    bmUefi        ## grub-install --target=x86_64-efi, wymaga partycji ESP (fat32)
    bmBiosLegacy   ## grub-install --target=i386-pc, wymaga partycji bios_grub na GPT

  SwapMode* = enum
    smNone         ## brak swapu
    smPartition     ## dedykowana partycja swap (pmEraseDisk: nowa; pmManual: istniejąca)
    smFile           ## plik wymiany wewnątrz systemu plików roota (swapSizeMiB decyduje o rozmiarze)

  ManualPartitionAssignment* = object
    ## Przypisanie istniejących partycji do ról w trybie pmManual.
    espPart*: string          ## wymagane przy bmUefi
    biosGrubPart*: string      ## wymagane przy bmBiosLegacy (partycja z flagą
                                 ## bios_grub, nigdy nie formatowana)
    rootPart*: string           ## wymagane zawsze
    swapPart*: string            ## opcjonalne, puste = brak dedykowanej partycji swap
    swapFileSizeMiB*: int          ## >0 = plik wymiany wewnątrz roota (alternatywa
                                     ## dla swapPart -- oba naraz nie mają sensu,
                                     ## swapPart ma priorytet jeśli ustawione)
    homePart*: string             ## opcjonalne, puste = /home zostaje na partycji roota
    formatEsp*: bool
    formatRoot*: bool
    formatHome*: bool

  PartitionPlan* = object
    targetDisk*: DiskInfo
    mode*: PartitionMode
    bootloaderMode*: BootloaderMode
    useLuksEncryption*: bool
    luksPassphrase*: string    ## trzymane w pamięci tylko na czas instalacji
    swapMode*: SwapMode         ## dotyczy tylko pmEraseDisk -- w pmManual o
                                  ## swapie decyduje manual.swapPart/swapFileSizeMiB
    swapSizeMiB*: int             ## rozmiar swapu (partycji albo pliku), 0 = brak
    filesystem*: string             ## "ext4", "btrfs", "xfs"
    manual*: ManualPartitionAssignment

  MountedPartition* = object
    ## Zwracane przez partitioner.applyPartitionPlan -- używane przez
    ## executor.nim do wygenerowania /etc/fstab i /etc/crypttab.
    devicePath*: string      ## surowe urządzenie blokowe (partycja fizyczna,
                              ## NIGDY /dev/mapper/... nawet dla LUKS) -- puste
                              ## dla swapfile (nie ma bloku, tylko plik).
    fstabDevice*: string      ## urządzenie/ścieżka do wpisania do fstab (dla
                                ## LUKS: /dev/mapper/<nazwa>, dla swapfile: sama
                                ## ścieżka pliku, w przeciwnym razie ==devicePath)
    mountpoint*: string        ## "none" dla swap
    fsType*: string
    isEncrypted*: bool           ## true jeśli fstabDevice to /dev/mapper/... (LUKS,
                                   ## łącznie z losowo-kluczowym szyfrowanym swapem)
    extraMountOptions*: string     ## dodatkowe opcje mount/fstab (np. "subvol=@"
                                     ## dla subwoluminów btrfs), puste = brak

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
    ## Skąd wystartował Zenit Installer -- patrz liveenv.nim. Odzwierciedla
    ## wybór z GRUB-a wpisany przez zlbpkg/iso.nim::writeGrubCfg.
    blmLiveOnly       ## boot=zenit bez installer=1 -- zwykła sesja live
    blmInstallerAuto  ## boot=zenit installer=1 -- pełnoekranowy instalator od razu
    blmStandalone      ## uruchomiony ręcznie z zainstalowanego systemu (reinstall/recovery)

const
  MinInstallDiskSizeBytes* = 8_589_934_592'i64   # 8 GiB -- minimalny sensowny cel instalacji
  MinRootPartitionSizeBytes* = 8_589_934_592'i64  # 8 GiB -- to samo dla ręcznie wybranej partycji roota
  MinPasswordLength* = 8   # dotyczy hasła użytkownika, hasła root i hasła LUKS jednakowo
