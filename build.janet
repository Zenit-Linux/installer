#!/usr/bin/env janet

(def out-dir "bin")
(def src-file "src/installer.nim")
(def data-dir "data")
(def bundled-font (string data-dir "/fonts/UiFont-Regular.ttf"))
# Opcjonalna podmiana na "prawdziwy" Inter zamiast dołączonego Instrument
# Sans -- patrz `task-fetch-inter` niżej. Font w repo (data/fonts/) jest
# WYSTARCZAJĄCY sam w sobie (patrz data/fonts/README.md); to tylko
# wygodny sposób na podmianę, jeśli ktoś wolałby dokładnie Inter.
(def inter-url "https://github.com/rsms/inter/raw/master/docs/font-files/Inter-Regular.ttf")

(defn sh
  [cmd]
  (print "$ " cmd)
  (def code (os/execute ["/bin/sh" "-c" cmd] :p))
  (when (not= code 0)
    (eprint "build.janet: polecenie nie powiodło się (kod " code "): " cmd)
    (os/exit code)))

(defn ensure-out-dir [] (os/mkdir out-dir))

(defn task-deps []
  (print "Instaluję zależności nimble (fidget, opengl, ...)...")
  (print "Naprawa znanego błędu paczki 'opengl' (--path na poziomie nima) siedzi w config.nims i")
  (print "działa automatycznie przy kompilacji -- nic dodatkowego nie trzeba tu robić.")
  (sh "nimble install -y --depsOnly"))

(defn task-assets []
  # Font UI (data/fonts/UiFont-Regular.ttf) jest już częścią repozytorium
  # -- w odróżnieniu od wcześniejszej wersji tego skryptu, NIC tu nie
  # trzeba pobierać z sieci, żeby GUI działało. To zadanie tylko
  # sprawdza, że plik faktycznie tam jest (np. po płytkim `git clone`
  # albo ręcznym kopiowaniu samych src/) i daje czytelny komunikat, jeśli
  # nie -- ten sam problem, który wcześniej ujawniał się dopiero w
  # trakcie działania binarki jako nieczytelny błąd Fidget/pixie.
  (if (os/stat bundled-font)
    (print "Font UI OK: " bundled-font)
    (do
      (eprint "BRAK: " bundled-font)
      (eprint "Ten plik powinien być częścią repozytorium (patrz data/fonts/README.md) --")
      (eprint "sprawdź, czy katalog data/ został skopiowany razem z resztą projektu.")
      (os/exit 1))))

(defn task-fetch-inter []
  # Opcjonalne: podmienia dołączony font na "prawdziwy" Inter -- wymaga
  # sieci. Nigdy wołane automatycznie przez release/debug/package (patrz
  # task-assets wyżej, które tylko WERYFIKUJE, że jakiś font już jest).
  (print "Pobieram Inter-Regular.ttf jako zamiennik dołączonego fontu ...")
  (sh (string "curl -fsSL -o " bundled-font " " inter-url))
  (print "Podmieniono -- upewnij się, że plik faktycznie jest poprawnym TTF (uruchom `janet build.janet assets`)."))

(defn task-release []
  (task-deps)
  (task-assets)
  (ensure-out-dir)
  (sh (string "nim c -d:release --opt:speed --out:" out-dir "/installer " src-file))
  (sh (string "cp -r " data-dir " " out-dir "/"))
  (print "-> " out-dir "/installer (+ " out-dir "/" data-dir "/ -- MUSZĄ zostać razem)"))

(defn task-debug []
  (task-assets)
  (ensure-out-dir)
  (sh (string "nim c --out:" out-dir "/installer-debug " src-file))
  (sh (string "cp -r " data-dir " " out-dir "/"))
  (print "-> " out-dir "/installer-debug (+ " out-dir "/" data-dir "/)"))

(defn task-server []
  # Celowo BEZ task-deps/task-assets/kopiowania data/: `-d:server` sprawia,
  # że installer.nim w ogóle nie importuje app.nim (patrz `when not
  # defined(server)` tamże), więc Fidget/OpenGL nigdy nie trafiają do
  # kompilacji ani linkowania -- ta binarka nigdy nie woła loadFont, więc
  # nie potrzebuje data/fonts/ w ogóle.
  (ensure-out-dir)
  (sh (string "nim c -d:release -d:server --opt:speed --out:" out-dir "/installer-server " src-file))
  (print "-> " out-dir "/installer-server (headless -- bez Fidget/OpenGL/X11, bez data/)"))

(defn task-check []
  (sh (string "nim check " src-file)))

(defn task-test []
  (sh "nim c -r tests/test_diskutil.nim")
  (sh "nim c -r tests/test_validation.nim")
  (sh "nim c -r tests/test_partitioner.nim")
  (sh "nim c -r tests/test_i18n.nim"))

(defn task-clean []
  (sh (string "rm -rf " out-dir " nimcache nimblecache")))

(defn task-distclean []
  (task-clean))
  # UWAGA: font w data/fonts/ NIE jest tu usuwany -- to teraz plik
  # źródłowy repozytorium (jak każdy .nim), a nie artefakt pobrany przez
  # task-assets (patrz komentarz przy task-assets wyżej).

(defn detect-os []
  (case (os/which)
    :linux "linux"
    :macos "macos"
    :windows "windows"
    "unknown"))

(defn detect-arch []
  (def p (os/spawn ["uname" "-m"] :p {:out :pipe}))
  (def out (string/trim (:read (p :out) :all)))
  (os/proc-wait p)
  out)

(defn task-package [version]
  (task-release)
  (def osname (detect-os))
  (def arch (detect-arch))
  (def name (string out-dir "/installer-" osname "-" arch))
  (sh (string "cp " out-dir "/installer " name))
  (sh (string "cp -r " data-dir " " out-dir "/" "installer-" osname "-" arch "-data"))
  (sh (string "sha256sum " name " > " out-dir "/SHA256SUMS-" version))
  (print "package " version " gotowy: " name " (+ katalog data/ obok niego, wymagany do działania GUI)"))

(defn main [&opt task & args]
  (case task
    "deps" (task-deps)
    "assets" (task-assets)
    "fetch-inter" (task-fetch-inter)
    "release" (task-release)
    "debug" (task-debug)
    "server" (task-server)
    "check" (task-check)
    "test" (task-test)
    "clean" (task-clean)
    "distclean" (task-distclean)
    "package" (task-package (or (first args) "dev"))
    nil (task-release)
    (do
      (eprint "Nieznane zadanie: " task)
      (eprint "Użycie: janet build.janet <deps|assets|fetch-inter|release|debug|server|check|test|clean|distclean|package [wersja]>")
      (os/exit 1))))

(let [all-args (or (dyn :args) @[])
      task (get all-args 1)
      rest-args (array/slice all-args 2)]
  (main task ;rest-args))
