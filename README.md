# Zenit Installer

Graficzny instalator Zenit Linux. Zbudowany w Nim, interfejs na
[Fidget](https://github.com/treeform/fidget) (immediate-mode UI,
renderowane wektorowo przez pixie/OpenGL -- bez zależności od GTK/Qt).

Funkcje: partycjonowanie automatyczne (wymaż dysk) i ręczne (przypisanie
istniejących partycji do ról, z walidacją unikalności i minimalnego
rozmiaru), swap (partycja albo plik wymiany), szyfrowanie LUKS (łącznie z
szyfrowanym swapem losowym kluczem), GRUB w trybie UEFI albo BIOS-legacy z
autodetekcją firmware'u, subwoluminy btrfs (`@`/`@home`/`@snapshots`),
ochrona przed wybraniem nośnika live jako celu instalacji, wykrywanie
innych systemów (dual-boot) przez os-prober, generowanie
`/etc/fstab`/`/etc/crypttab`, sprzątanie (odmontowanie/swapoff/luksClose)
po nieudanej instalacji, `fstrim.timer` dla SSD, instalacja na wątku
roboczym (GUI nie zamraża się na czas instalacji), interfejs w dwóch
językach (polski/angielski, przełącza się razem z językiem wybranym dla
instalowanego systemu) oraz alternatywne tryby bez GUI: tekstowy
`--server` i w pełni bezobsługowy `--autoinstall=<plik>` (patrz niżej).

## Skąd startuje

`zlb` (patrz `zlbpkg/iso.nim` w repo `zlb`) generuje w GRUB-ie dwa
oddzielne wpisy menu na zbudowanym ISO, dokładnie tak jak najnowsze
Fedory:

* **"Try/Live Zenit Linux"** -- zwykła sesja live, `boot=zenit` bez
  dodatkowego parametru.
* **"Install Zenit Linux"** -- to samo środowisko live, ale z
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
janet build.janet assets    # sprawdza, że font UI (data/fonts/) jest na miejscu -- nic już nie pobiera domyślnie
janet build.janet release   # -> bin/installer + bin/data/ (woła deps + assets automatycznie)
janet build.janet debug     # -> bin/installer-debug + bin/data/
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

### Znany problem: `File data/fonts/... does not exist` albo `key not found: head`

Obie te awarie przy STARCIE binarki (nie przy kompilacji) mają tę samą
przyczynę: Fidget doklejają `data/` do ścieżki fontu WZGLĘDEM BIEŻĄCEGO
KATALOGU ROBOCZEGO procesu, nie względem lokalizacji samego pliku
wykonywalnego. Jeśli uruchamiasz binarkę z innego katalogu niż korzeń
repozytorium (np. `cd bin && ./installer` zamiast `./bin/installer` z
korzenia), `data/fonts/UiFont-Regular.ttf` nie zostanie znaleziony.

- `File data/fonts/UiFont-Regular.ttf does not exist` -- uruchamiasz z
  niewłaściwego katalogu, albo `data/` w ogóle nie zostało skopiowane
  razem z resztą repozytorium. Uruchom binarkę z korzenia repo, albo
  skopiuj `data/` obok niej (`janet build.janet release`/`package` robi
  to automatycznie -- patrz `bin/data/` po zbudowaniu).
- `key not found: head` (albo podobny błąd parsera fontu) -- plik pod tą
  ścieżką ISTNIEJE, ale nie jest poprawnym TTF/OTF (uszkodzony download,
  strona błędu HTML zapisana pod tą nazwą itp.). Podmień go na poprawny
  plik -- domyślnie dołączony `data/fonts/UiFont-Regular.ttf` jest
  sprawdzonym, poprawnym plikiem (patrz `data/fonts/README.md`), więc
  jeśli widzisz ten błąd, prawdopodobnie ktoś go ręcznie nadpisał czymś
  zepsutym.

`app.nim::checkFontAvailable` wykrywa oba te przypadki PRZED wywołaniem
Fidget i wypisuje krótki, konkretny komunikat zamiast surowego wyjątku z
głębi biblioteki -- ale samą przyczynę (zły katalog roboczy / zły plik)
trzeba poprawić ręcznie tak czy inaczej.

## Tryb tekstowy (`--server`)

Obok kreatora GUI instalator ma też tryb tekstowy, prowadzony liniowo przez
terminal -- odpowiednik tego, co np. Ubuntu Server ma obok swojego
graficznego instalatora, przydatny na maszynach bez środowiska graficznego
(serwer, konsola tekstowa, sesja przez SSH):

```bash
installer --server
```

Kreator zadaje te samo pytania co GUI (język, klawiatura, strefa czasowa,
dysk, partycjonowanie, LUKS, konto, pakiety) w formie numerowanych list i
pytań tak/nie, a na końcu woła ten sam `executor.runInstall` co GUI --
zobacz `installerpkg/cliapp.nim`. `--fullscreen`/`--windowed` nie mają w
tym trybie znaczenia.

UWAGA: to jest przełącznik czasu wykonania w JEDNEJ binarce (`bin/installer`)
-- wciąż linkuje się z Fidget/OpenGL/GLFW/X11 nawet w `--server`, bo
`installer.nim` domyślnie importuje `app.nim`. Jeśli potrzebujesz binarki,
która NIGDY nie dotyka Fidget/OpenGL/X11 (ani przy kompilacji, ani przy
linkowaniu) -- patrz "Build headless" niżej.

## Build headless (`-d:server`, bez Fidget/OpenGL/X11 w ogóle)

```bash
janet build.janet server     # -> bin/installer-server
# albo bez Janeta:
nimble buildServer            # to samo, przez nimble
```

W przeciwieństwie do runtime'owego `--server` opisanego wyżej, to jest
osobny TARGET KOMPILACJI (`nim c -d:server ...`). `installer.nim` importuje
`app.nim` warunkowo (`when not defined(server)`) -- przy `-d:server`
`app.nim`, a razem z nim cały Fidget/OpenGL/GLFW/X11, nigdy nie trafia do
kompilacji ani linkowania. Ta binarka umie tylko `--server`/`--autoinstall`
(uruchomiona bez żadnej z tych flag wypisze komunikat i zakończy się kodem
1) -- za to da się ją zbudować i uruchomić na maszynie bez żadnych
bibliotek graficznych, i `janet build.janet server` celowo pomija
`task-deps`/`task-assets` (nie trzeba instalować Fidget/OpenGL ani
pobierać fontu, żeby ją zbudować).

## Instalacja bezobsługowa (`--autoinstall=<plik>`)

Dla masowych/automatycznych wdrożeń -- odpowiednik `autoinstall`/cloud-init
w Ubuntu. Zamiast pytać interaktywnie, instalator czyta gotowe odpowiedzi z
prostego pliku klucz=wartość i instaluje bez żadnego potwierdzenia:

```bash
installer --autoinstall=/sciezka/do/odpowiedzi.conf
```

Przykładowa zawartość pliku:

```ini
# Komentarze zaczynają się od #, puste linie są ignorowane.
language=pl_PL.UTF-8
keyboard=pl
timezone=Europe/Warsaw

disk=/dev/sda
partition_mode=erase        # erase | manual
bootloader=uefi              # uefi | bios
filesystem=ext4               # ext4 | btrfs | xfs
swap_mode=partition            # none | partition | file
swap_size_mib=2048
luks=false
luks_passphrase=

# Używane tylko gdy partition_mode=manual -- ścieżki istniejących partycji,
# WSZYSTKIE muszą leżeć na dysku wskazanym przez disk= (sprawdzane) i być
# parami różne (też sprawdzane):
manual_esp=
manual_biosgrub=
manual_root=
manual_home=
manual_swap=
manual_swapfile_mib=0

fullname=Jan Kowalski
username=jkowalski
hostname=zenit-serwer
password=zmien-to-haslo
root_password=
autologin=false

extra_packages=vscode -> own,firefox -> flatpak
```

Wymagane jest przynajmniej `username=` i `password=` -- reszta ma sensowne
wartości domyślne (patrz `installerpkg/cliapp.nim::runInstallerAutoinstall`).
`disk=` musi dokładnie odpowiadać ścieżce zwróconej przez `lsblk` (np.
`/dev/sda`, `/dev/nvme0n1`) -- instalator jej nie zgaduje ani nie
dopasowuje częściowo. Przed instalacją sprawdzane jest to samo, co w
trybach interaktywnych: minimalny rozmiar dysku/partycji roota
(`MinInstallDiskSizeBytes`/`MinRootPartitionSizeBytes`), że
`manual_esp`/`manual_biosgrub`/`manual_root`/`manual_home`/`manual_swap`
leżą na dysku z `disk=` (a nie np. przez literówkę na innym dysku w tej
samej maszynie), że żadne dwie z nich nie wskazują tej samej partycji,
minimalna długość hasła (`MinPasswordLength`, patrz niżej), oraz
poprawność `username=`/`hostname=` (`installerpkg/validation.nim`). Każde
niepowodzenie walidacji przerywa instalację PRZED dotknięciem dysku.

**Bezpieczeństwo pliku odpowiedzi:** `password=`/`root_password=`/
`luks_passphrase=` leżą w nim jawnym tekstem -- to nieodłączna właściwość
tego mechanizmu (to samo dotyczy `autoinstall`/cloud-init w Ubuntu).
Instalator sam sprawdza uprawnienia pliku i ostrzega (nie blokuje), jeśli
jest czytelny dla grupy/innych -- ale to Twoja odpowiedzialność, żeby plik
nie trafił tam, gdzie nie powinien (np. `chmod 600 odpowiedzi.conf`, nie
commitować go do repozytorium, usunąć po instalacji).

`--autoinstall` jest nadrzędne wobec `--server` -- jeśli oba zostaną
podane, wygrywa autoinstall.

## Struktura

```
src/installer.nim              -- punkt wejścia, detekcja trybu startu, --server/--autoinstall,
                                   `when not defined(server): import app` (patrz "Build headless")
src/installerpkg/
  types.nim                    -- wspólne typy (WizardStep, InstallPlan, ...) + stałe polityk
                                   (MinInstallDiskSizeBytes, MinPasswordLength, ...)
  liveenv.nim                  -- odczyt /proc/cmdline (installer=1)
  validation.nim                -- walidacja username/hostname (bez std/re)
  i18n.nim                       -- słownik tłumaczeń interfejsu (pełne pl/en, częściowe de/fr/es)
  diskutil.nim                    -- wykrywanie dysków/partycji, firmware, os-prober, nośnik live
  partitioner.nim                  -- partycjonowanie + LUKS + swap + btrfs + mkfs + sprzątanie po błędzie
  fstab.nim                         -- generowanie /etc/fstab (UUID-y przez blkid)
  netcheck.nim                       -- prosty test połączenia (ping)
  zpmclient.nim                       -- JEDYNA droga instalacji pakietów (zpm --root)
  useraccount.nim                      -- hostname/locale/konto przez chroot
  bootloader.nim                        -- grub-install (UEFI/BIOS-legacy) + os-prober + LUKS
  executor.nim                           -- orkiestracja InstallPlan, postęp, wątek instalacyjny
  widgets.nim                             -- toolkit widżetów nad prymitywami Fidget (w tym
                                              passwordField, sizeStepper)
  app.nim                                  -- kreator GUI (drawMain, wołane co klatkę)
  cliapp.nim                                -- kreator tekstowy (--server) + --autoinstall, bez GUI
data/fonts/                                  -- font UI dołączony do repozytorium (patrz data/fonts/README.md
                                                 -- WAŻNE: musi leżeć obok katalogu roboczego, z którego
                                                 uruchamiasz binarkę, nie obok samego pliku wykonywalnego)
config.nims                                  -- naprawa błędu paczki opengl (--path na poziomie kompilatora nim)
tests/                                        -- testy jednostkowe czystej logiki (bez dostępu do dysku),
                                                  `nimble test` albo `janet build.janet test`
```

## Bezpieczeństwo -- co instalator sprawdza sam

* **Nośnik live jako cel instalacji.** `diskutil.detectLiveMediumDisks`
  sprawdza `/proc/mounts` (root sesji plus kilka znanych konwencji montowania
  -- `/cdrom`, `/run/live/medium`, `/run/live/rootfs`, `/lib/live/mount/medium`,
  `/run/archiso/bootmnt`, `/run/casper`, `/media/root-ro`, `/run/rootfsbase`,
  `/isodevice` -- w zależności od narzędzia, którym zbudowano live) i
  oznacza pasujące dyski jako `isLiveMedium`. Taki dysk nadal da się
  wybrać (jedyny dysk w maszynie to prawidłowy przypadek), ale wymaga
  dodatkowego, osobnego potwierdzenia -- w obu trybach, GUI i `--server`.
  Lista konwencji jest z konieczności best-effort -- nietypowe/rzadkie
  narzędzie do budowania live może się wymknąć tej detekcji.
* **Zduplikowane role w partycjonowaniu ręcznym.** Ta sama partycja nie
  może być jednocześnie np. rootem i home -- sprawdzane przed
  przejściem dalej, tą samą logiką co w `--autoinstall`
  (`app.nim::manualSelectionsUnique`, `cliapp.nim::hasDuplicatePartitions`).
* **Za mały dysk/partycja.** `MinInstallDiskSizeBytes`/
  `MinRootPartitionSizeBytes` w `types.nim` (domyślnie 8 GiB) blokują
  kontynuację, zanim cokolwiek zostanie zapisane na dysk -- we WSZYSTKICH
  trybach, łącznie z `--autoinstall`.
* **Za krótkie hasło.** `MinPasswordLength` w `types.nim` (domyślnie 8
  znaków) dotyczy jednakowo hasła użytkownika, hasła root i hasła
  szyfrowania LUKS, we wszystkich trybach. To prosta, jawna polityka
  długości -- nie próba oceny "siły" hasła (entropii, słownikowości itp.),
  co jest znacznie bardziej subiektywne i poza zakresem tego prototypu.
* **Sprzątanie po nieudanej instalacji.** Błąd w dowolnym miejscu --
  także w połowie samego partycjonowania -- odmontowuje to, co zdążyło
  się zamontować, wyłącza swap i zamyka kontener LUKS
  (`partitioner.nim::bestEffortUndo`, `executor.nim::runInstall`).
* **Szyfrowany swap.** Gdy LUKS jest włączony, swap (partycja) dostaje
  losowy klucz z `/dev/urandom` przy każdym rozruchu (crypttab), zamiast
  zostać zapisany jawnym tekstem. Plik wymiany (`swapfile`) automatycznie
  dziedziczy szyfrowanie, bo leży wewnątrz już zaszyfrowanego roota.
* **Kasowanie dysku z wykrytym innym systemem.** Gdy tryb "wymaż cały
  dysk" dotyczy dysku, na którym os-prober wykrył inny system operacyjny,
  pokazywane jest dodatkowe, jawne ostrzeżenie o tym KONKRETNYM systemie
  tuż przy przycisku potwierdzenia (`diskutil.filterOsesOnDisk`) -- osobno
  od ogólnej listy "wykryto inne systemy" pokazywanej przy wyborze dysku.
* **Uprawnienia pliku `--autoinstall`.** Patrz sekcja wyżej -- ostrzeżenie
  (nie blokada), jeśli plik z hasłami jest czytelny dla grupy/innych.

## Co dalej (poza zakresem tego prototypu)

* Prawdziwa klawiatura wirtualna / IME dla sesji GUI bez fizycznej
  klawiatury (tablety w trybie live) -- tryb `--server`/build headless
  obchodzi ten problem, ale nie zastępuje go dla desktopowego przypadku użycia.
* Wsparcie dla limine jako alternatywy dla GRUB (obecnie: GRUB w trybie
  UEFI albo BIOS-legacy, patrz `bootloader.nim`).
* Automatyczne dual-boot jest już wykrywane przez `os-prober`
  (`diskutil.detectOtherOperatingSystems`) i włączane w `grub-mkconfig`
  (`GRUB_DISABLE_OS_PROBER=false`), ale samo montowanie/łączenie z
  konkretnymi wpisami menu innych systemów wciąż zostaje w gestii
  GRUB-a/os-probera, nie tego instalatora.
* Interfejs instalatora (`i18n.nim`) ma PEŁNE tłumaczenia tylko pl/en --
  niemiecki/francuski/hiszpański pokrywają tylko najbardziej widoczne
  stringi (nagłówki, przyciski, etykiety kroków, główne ostrzeżenia);
  rzadsze klucze (część promptów `--server`, komunikaty `--autoinstall`)
  celowo spadają na angielski zamiast na zgadywane tłumaczenie
  krytycznego komunikatu (patrz komentarz na górze `i18n.nim`). Inne
  języki (np. polski wybrany jako en_US dla systemu) zawsze dostają
  angielski interfejs instalatora.
* Testy (`tests/`) pokrywają tylko czystą, bezstanową logikę
  (`partitionPath`, `humanSize`, `parentDiskOf`, walidatory) -- kod
  wykonujący realne operacje na dysku/chroot nie ma automatycznych testów
  (wymagałby kontenera/VM z uprawnieniami roota do sensownego mockowania).
* Rozmiar swapu (partycji albo pliku) jest teraz konfigurowalny w GUI
  (`widgets.sizeStepper`, krok 256 MiB) i w `--server`
  (`cliapp.askInt`) -- ale nadal krokowo/z ograniczonym zakresem
  (256 MiB-64 GiB), nie dowolna precyzyjna wartość wpisywana z klawiatury
  (patrz uzasadnienie w komentarzu `widgets.sizeStepper`).
