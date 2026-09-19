(def stage (os/getenv "ZPM_PACKAGE_STAGE_DIR"))

(defn fail [msg]
  (eprint "recipe.janet: " msg)
  (os/exit 1))

(defn run [cmd]
  # `os/shell` zwraca kod wyjścia polecenia (jak C-owe system()) --
  # zero == sukces.
  (def code (os/shell cmd))
  (unless (zero? code)
    (fail (string "'" cmd "' zakończone kodem " code))))

(defn ensure-dir [path]
  # `os/mkdir` w Janet nie jest rekurencyjne i zgłasza błąd, jeśli katalog
  # już istnieje -- oba przypadki są tu nieszkodliwe, więc łykamy błąd.
  (try (os/mkdir path) ([_] nil)))

(defn ensure-dir-p [path]
  # Rekurencyjny odpowiednik `mkdir -p` z powyższego `ensure-dir`,
  # potrzebny bo stage dir dostajemy jako gołe "usr/local/..." bez
  # gwarancji, że pośrednie katalogi już istnieją.
  (var acc "")
  (each part (string/split "/" path)
    (when (> (length part) 0)
      (set acc (string acc "/" part))
      (ensure-dir acc))))

# packaging/recipe.janet leży w <repo>/packaging -- katalog wyżej to
# korzeń repo, niezależnie od tego, skąd faktycznie wywołano `zpk build`
# (tak samo jak w recipe.janet samego zpk).
(def repo-root (string (os/cwd) "/.."))

(def prebuilt (os/getenv "ZPK_PACKAGING_PREBUILT_BIN"))

(def bin-dir-built
  # Jeśli CI/operator zbudował już `bin/installer` wcześniej w tym samym
  # biegu (np. osobnym krokiem `janet build.janet release`), nie buduj
  # drugi raz -- oczekujemy, że `data/` leży OBOK wskazanej binarki,
  # dokładnie tak jak zostawia to `task-release`/`task-package` w
  # `build.janet`.
  (if (and prebuilt (> (length prebuilt) 0))
    (string/slice prebuilt 0 (- (length prebuilt) (length "/installer")))
    (do
      (run (string "command -v janet >/dev/null 2>&1 || "
                   "{ echo \"recipe.janet: brak 'janet' w PATH\" >&2; exit 1; }"))
      # `task-release` w build.janet woła sam deps + assets, kompiluje
      # `bin/installer` i kopiuje `data/` obok niego jako `bin/data/` --
      # dokładnie układ, którego potrzebujemy niżej.
      (run (string "cd " repo-root " && janet build.janet release"))
      (string repo-root "/bin"))))

(def bin-path (string bin-dir-built "/installer"))
(def data-path (string bin-dir-built "/data"))

(unless (os/stat bin-path :mode)
  (fail (string "nie znaleziono zbudowanej binarki: " bin-path)))
(unless (os/stat data-path :mode)
  (fail (string "nie znaleziono katalogu z fontami: " data-path
                " (spodziewany obok binarki, patrz build.janet::task-release)")))

(ensure-dir stage)

# Binarka + data/ (fonty) trafiają RAZEM do jednego katalogu w
# /usr/local/lib/installer/ -- to jest jedyny układ, w którym font UI
# faktycznie się znajduje: Fidget doklejają "data/" do ścieżki assetu
# WZGLĘDEM BIEŻĄCEGO KATALOGU ROBOCZEGO procesu, nie względem lokalizacji
# pliku wykonywalnego (patrz src/installerpkg/app.nim::checkFontAvailable
# i data/fonts/README.md) -- samo skopiowanie fontów "obok" pliku w
# /usr/local/bin/ by tu NIE wystarczyło, bo CWD użytkownika przy
# uruchamianiu może być dowolny. Dlatego /usr/local/bin/installer
# poniżej to cienki wrapper, który najpierw `cd` do tego katalogu.
(def lib-dir (string stage "/usr/local/lib/installer"))
(def bin-dir (string stage "/usr/local/bin"))
(ensure-dir-p lib-dir)
(ensure-dir-p bin-dir)

(def dest-bin (string lib-dir "/installer"))
(spit dest-bin (slurp bin-path))
(run (string "chmod +x " dest-bin))

# Kopiujemy cały data/ (nie tylko .ttf) -- data/fonts/README.md i
# UiFont-OFL.txt (licencja OFL fontu) mają zostać razem z plikiem, tak
# samo jak w bin/data/ produkowanym przez build.janet.
(run (string "cp -r " data-path " " lib-dir "/data"))

(def wrapper (string bin-dir "/installer"))
(spit wrapper
  (string
    "#!/bin/sh\n"
    "# Wrapper wygenerowany przez packaging/recipe.janet -- `installer`\n"
    "# potrzebuje uruchomienia z katalogu, w którym leży `data/` (patrz\n"
    "# komentarz przy `lib-dir` w recipe.janet), więc niezależnie od tego,\n"
    "# z jakiego katalogu wywoła go użytkownik/PATH, najpierw `cd` do\n"
    "# /usr/local/lib/installer.\n"
    "set -e\n"
    "cd /usr/local/lib/installer\n"
    "exec ./installer \"$@\"\n"))
(run (string "chmod +x " wrapper))
