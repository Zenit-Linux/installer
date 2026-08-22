#!/usr/bin/env janet

(def out-dir "bin")
(def src-file "src/installer.nim")
(def font-path "assets/fonts/Inter-Regular.ttf")
(def font-url "https://github.com/rsms/inter/raw/master/docs/font-files/Inter-Regular.ttf")

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
  (unless (os/stat font-path)
    (print "Pobieram font " font-path " ...")
    (sh (string "curl -fsSL -o " font-path " " font-url))))

(defn task-release []
  (task-deps)
  (task-assets)
  (ensure-out-dir)
  (sh (string "nim c -d:release --opt:speed --out:" out-dir "/installer " src-file))
  (print "-> " out-dir "/installer"))

(defn task-debug []
  (task-assets)
  (ensure-out-dir)
  (sh (string "nim c --out:" out-dir "/installer-debug " src-file))
  (print "-> " out-dir "/installer-debug"))

(defn task-check []
  (sh (string "nim check " src-file)))

(defn task-clean []
  (sh (string "rm -rf " out-dir " nimcache nimblecache")))

(defn task-distclean []
  (task-clean)
  (sh (string "rm -f " font-path)))

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
  (sh (string "sha256sum " name " > " out-dir "/SHA256SUMS-" version))
  (print "package " version " gotowy: " name))

(defn main [&opt task & args]
  (case task
    "deps" (task-deps)
    "assets" (task-assets)
    "release" (task-release)
    "debug" (task-debug)
    "check" (task-check)
    "clean" (task-clean)
    "distclean" (task-distclean)
    "package" (task-package (or (first args) "dev"))
    nil (task-release)
    (do
      (eprint "Nieznane zadanie: " task)
      (eprint "Użycie: janet build.janet <deps|assets|release|debug|check|clean|distclean|package [wersja]>")
      (os/exit 1))))

(let [all-args (or (dyn :args) @[])
      task (get all-args 1)
      rest-args (array/slice all-args 2)]
  (main task ;rest-args))
