import std/[os, parseopt]
import ./installerpkg/liveenv
import ./installerpkg/cliapp

const InstallerVersion = "0.1.0"

when not defined(server):
  import ./installerpkg/app
else:
  # Build headless (`nim c -d:server`, patrz `Installer.nimble::buildServer`
  # / `janet build.janet server`): `app.nim` (i przez nią cały Fidget/
  # OpenGL/GLFW/X11) nie jest w ogóle importowane ani linkowane -- to
  # jedyny sposób na PRAWDZIWIE headless build tego instalatora, bo sam
  # runtime'owy przełącznik `--server` (patrz main() niżej) nadal linkuje
  # się z GUI, tylko go nie otwiera. Ten stub istnieje wyłącznie po to,
  # żeby main() miało co wywołać, gdyby ktoś mimo wszystko odpalił binarkę
  # headless bez --server/--autoinstall.
  proc runInstallerGui(forceFullscreen = false, forceWindowed = false) =
    stderr.writeLine("Ta binarka (zbudowana z -d:server) nie zawiera GUI -- " &
      "użyj --server albo --autoinstall=<plik>.")
    quit(1)

proc printHelp() =
  echo """
Zenit Installer """ & InstallerVersion & """

USAGE:
  installer                  uruchamia kreator GUI (auto-fullscreen jeśli
                              GRUB przekazał installer=1 na linii poleceń jądra)
  installer --fullscreen     wymusza tryb pełnoekranowy niezależnie od /proc/cmdline
  installer --windowed       wymusza tryb okienkowy
  installer --server         tryb tekstowy (TTY) -- kreator prowadzony przez
                              terminal, bez GUI/Fidget/OpenGL. Ten sam
                              InstallPlan i ten sam executor co GUI -- różni
                              się tylko sposobem zbierania odpowiedzi.
                              Odpowiednik trybu tekstowego, jaki np. Ubuntu
                              Server ma obok swojego graficznego instalatora --
                              przydatne na maszynach bez środowiska graficznego
                              (serwery, konsola tekstowa, sesja przez SSH).
                              UWAGA: to przełącznik czasu wykonania w TEJ
                              SAMEJ binarce -- wciąż linkuje się z Fidget/
                              OpenGL. Dla prawdziwie headless builda bez
                              żadnych zależności graficznych zobacz
                              `nimble buildServer` / `janet build.janet server`.
  installer --autoinstall=<plik>
                              instalacja w pełni bezobsługowa -- odpowiedzi
                              brane z pliku klucz=wartość zamiast z terminala.
                              Nadrzędne wobec --server (odpowiedzi już są, więc
                              GUI/TTY nie jest w ogóle uruchamiane). Format
                              pliku i lista kluczy: patrz README.md.
  installer --version        pokaż wersję
  installer --help           pokaż tę pomoc

Instalator NIGDY nie pobiera pakietów bezpośrednio (curl/wget) -- cała
instalacja systemu bazowego i dodatkowego oprogramowania przechodzi przez
`zpm --root=<target> ...` (patrz installerpkg/zpmclient.nim), łącznie z
narzędziami z własnego ekosystemu Zenit (custom/own-repository.json w zpm).
"""

proc main() =
  var forceFullscreen = false
  var forceWindowed = false
  var serverMode = false
  var autoinstallPath = ""

  var p = initOptParser(commandLineParams())
  for kind, key, val in p.getopt():
    case kind
    of cmdLongOption, cmdShortOption:
      case key
      of "help", "h": printHelp(); return
      of "version", "v": echo InstallerVersion; return
      of "fullscreen": forceFullscreen = true
      of "windowed": forceWindowed = true
      of "server": serverMode = true
      of "autoinstall": autoinstallPath = val
      else: discard
    else: discard

  if getEnv("USER", "root") != "root" and not dirExists("/proc"):
    stderr.writeLine("Ostrzeżenie: /proc niedostępny -- wykrywanie trybu live może się nie udać.")

  echo "Zenit Installer " & InstallerVersion & " -- tryb startu: " & $detectBootLaunchMode()

  if autoinstallPath.len > 0:
    # W pełni bezobsługowe -- ani GUI, ani interaktywny TTY (patrz
    # installerpkg/cliapp.nim::runInstallerAutoinstall). Nadrzędne wobec
    # --server, gdyby oba zostały podane naraz.
    runInstallerAutoinstall(autoinstallPath)
  elif serverMode:
    # Tryb tekstowy -- bez GUI/Fidget, wymaga tylko terminala (patrz
    # installerpkg/cliapp.nim). `--fullscreen`/`--windowed` nie mają tu
    # znaczenia i są ignorowane.
    runInstallerCli()
  else:
    runInstallerGui(forceFullscreen = forceFullscreen, forceWindowed = forceWindowed)

when isMainModule:
  main()
