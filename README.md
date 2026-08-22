# Zenit Installer

Graficzny instalator Zenith Linux. Zbudowany w Nim, interfejs na
[Fidget](https://github.com/treeform/fidget) (immediate-mode UI,
renderowane wektorowo przez pixie/OpenGL -- bez zależności od GTK/Qt).

## Skąd startuje

`zlb` (patrz `zlbpkg/iso.nim` w repo `zlb`) generuje w GRUB-ie dwa
oddzielne wpisy menu na zbudowanym ISO, dokładnie tak jak najnowsze
Fedory:

* **"Try/Live Zenith Linux"** -- zwykła sesja live, `boot=zenith` bez
  dodatkowego parametru.
* **"Install Zenith Linux"** -- to samo środowisko live, ale z
  `installer=1` na linii poleceń jądra.

`installerpkg/liveenv.nim` czyta `/proc/cmdline` i na tej podstawie
`installer.nim` decyduje, czy wystartować od razu pełnoekranowo
(`blmInstallerAuto`), czy zostać zwykłą aplikacją dostępną z pulpitu
live (`blmLiveOnly`), czy działać jako samodzielne narzędzie
reinstalacji/odzyskiwania uruchomione ręcznie z zainstalowanego systemu
(`blmStandalone`).

Binarka `installer` sama trafia do obrazu przez ekosystem `own` zpm
(`custom/own-repository.json` w repo `zpm`) i jest osadzana w rootfsie
przez `zlbpkg/rootfs.nim::embedInstaller` w repo `zlb` -- nigdy przez
`curl`.

## Zero curl -- wszystko przez zpm

Cała instalacja (system bazowy + opcjonalne pakiety wybrane w
kreatorze) przechodzi przez `installerpkg/zpmclient.nim`, które woła
wyłącznie `zpm --root=<target> ...`. Zpm samo rozstrzyga, z którego
backendu skorzystać (apt/dnf/pacman/zypper/flatpak/snap/brew/cargo/pip/
npm/`own`) na podstawie `distro.base` / jawnej adnotacji `pakiet ->
backend`.

## Budowanie

### Zależności systemowe (Linux)

Fidget renderuje przez OpenGL/GLFW i linkuje bezpośrednio z X11 --
zainstaluj nagłówki deweloperskie zanim uruchomisz `nimble`/`janet`.
Bez nich `nimble build` kompiluje sam kod Nim poprawnie, ale pada na
etapie kompilacji C-ka dołączonego przez `staticglfw` z błędem:

```
fatal error: X11/Xlib.h: No such file or directory
```

Naprawa (Debian/Ubuntu -- jako root pomiń `sudo`):

```bash
sudo apt update
sudo apt install -y libglfw3-dev libgl1-mesa-dev libglu1-mesa-dev \
  xorg-dev libxi-dev libxcursor-dev libxinerama-dev libxrandr-dev
```

Na Fedorze/RHEL: `sudo dnf install glfw-devel mesa-libGL-devel mesa-libGLU-devel libXi-devel libXcursor-devel libXinerama-devel libXrandr-devel`.
Na Arch: `sudo pacman -S glfw-x11 mesa glu libxi libxcursor libxinerama libxrandr`.

### Budowa

```bash
janet build.janet deps      # nimble install --depsOnly + naprawia paczkę opengl (patrz niżej)
janet build.janet assets    # pobiera font Inter (wymagany przez Fidget)
janet build.janet release   # -> bin/installer (woła deps + assets automatycznie)
janet build.janet debug     # -> bin/installer-debug
janet build.janet check     # tylko sprawdzenie typów
janet build.janet package v0.1
```

Bez Janeta: `nimble install -y --depsOnly && nimble buildRelease`.

### Znany problem: `Error: cannot open file: opengl`

Jeśli `nimble build`/`nimble buildRelease` kończy się:

```
Warning: Declarative parser failed, the file had to be parsed with the VM parser.
...
--path:.../opengl-<hash>/src ...
fidget/opengl/base.nim(1, 57) Error: cannot open file: opengl
```

to **nie jest błąd w tym repozytorium**. Paczka nimble `opengl`
([nim-lang/opengl](https://github.com/nim-lang/opengl)) trzyma pliki
`*.nim` w KORZENIU paczki, a nie w podkatalogu `src/`. Mimo to (efekt
tej samej niespójności `opengl.nimble`, która wywołuje warning o
przełączeniu na stary parser VM) nimble każe nimowi szukać ich pod
`.../opengl-<hash>/src/opengl.nim` -- ta ścieżka po prostu nie istnieje,
więc kompilacja pada. **Pinowanie innej wersji (w tym `#head`) tego nie
naprawia** -- sprawdzone, że wskazują na ten sam układ plików.

Naprawa działa na poziomie samego kompilatora `nim`, a nie nimble:
**`config.nims`** w korzeniu repo jest ładowany automatycznie przez
`nim` przy KAŻDEJ kompilacji tego projektu -- czy to przez
`nimble build`, `nimble buildRelease`, czy nawet gołe
`nim c src/installer.nim`. Skanuje `~/.nimble/pkgs2/opengl-*`, znajduje
faktyczne miejsce, w którym leży `opengl.nim` (u nas: katalog główny
paczki, `.../opengl-<hash>/opengl.nim`, a NIE `.../src/opengl.nim`,
którego nimble błędnie się spodziewa), i dokłada poprawny `--path` dla
bieżącej kompilacji -- bez dotykania cache'u nimble. Sprawdzone
działa: nie wymaga żadnego ręcznego kroku, wystarczy zwykłe
`nimble build`.

Jeśli mimo wszystko zobaczysz ten błąd, uruchom ręcznie i wklej wynik:

```bash
find ~/.nimble/pkgs2/opengl-* -maxdepth 3
```

## Struktura

```
src/installer.nim              -- punkt wejścia, detekcja trybu startu
src/installerpkg/
  types.nim                    -- wspólne typy (WizardStep, InstallPlan, ...)
  liveenv.nim                  -- odczyt /proc/cmdline (installer=1)
  diskutil.nim                 -- wykrywanie dysków (lsblk --json)
  partitioner.nim               -- partycjonowanie + mkfs + montowanie
  zpmclient.nim                 -- JEDYNA droga instalacji pakietów (zpm --root)
  useraccount.nim               -- hostname/locale/konto przez chroot
  bootloader.nim                 -- grub-install / grub-mkconfig
  executor.nim                    -- orkiestracja całego InstallPlan + postęp
  widgets.nim                     -- mały toolkit widżetów nad prymitywami Fidget
  app.nim                          -- kreator (drawMain, wołane co klatkę)
assets/fonts/                       -- font wymagany przez Fidget (pobierany przez build.janet)
config.nims                         -- naprawa błędu paczki opengl (--path na poziomie kompilatora nim)
```

## Co dalej (poza zakresem tego prototypu)

* Partycjonowanie ręczne (`pmManual`) i szyfrowanie LUKS
  (`useLuksEncryption` jest już w typach, ale nieobsłużone).
  Wsparcie dla BIOS-legacy / limine obok obecnego GRUB+UEFI.
* Instalacja na wątku roboczym zamiast blokowania pętli renderowania
  Fidget podczas `runInstall`.
* Prawdziwa klawiatura wirtualna / IME dla sesji bez fizycznej
  klawiatury (tablety w trybie live).
* Automatyczne wykrywanie i dual-boot z istniejącymi systemami.
