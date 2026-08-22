import std/[os, parseopt]
import ./installerpkg/liveenv
import ./installerpkg/app

const InstallerVersion = "0.1.0"

proc printHelp() =
  echo """
Zenith Installer """ & InstallerVersion & """

USAGE:
  installer                uruchamia kreator GUI (auto-fullscreen jeśli
                            GRUB przekazał installer=1 na linii poleceń jądra)
  installer --fullscreen    wymusza tryb pełnoekranowy niezależnie od /proc/cmdline
  installer --windowed      wymusza tryb okienkowy
  installer --version        pokaż wersję
  installer --help            pokaż tę pomoc

Instalator NIGDY nie pobiera pakietów bezpośrednio (curl/wget) -- cała
instalacja systemu bazowego i dodatkowego oprogramowania przechodzi przez
`zpm --root=<target> ...` (patrz installerpkg/zpmclient.nim), łącznie z
narzędziami z własnego ekosystemu Zenith (custom/own-repository.json w zpm).
"""

proc main() =
  var forceFullscreen = false
  var forceWindowed = false

  var p = initOptParser(commandLineParams())
  for kind, key, val in p.getopt():
    case kind
    of cmdLongOption, cmdShortOption:
      case key
      of "help", "h": printHelp(); return
      of "version", "v": echo InstallerVersion; return
      of "fullscreen": forceFullscreen = true
      of "windowed": forceWindowed = true
      else: discard
    else: discard

  if getEnv("USER", "root") != "root" and not dirExists("/proc"):
    stderr.writeLine("Ostrzeżenie: /proc niedostępny -- wykrywanie trybu live może się nie udać.")

  echo "Zenith Installer " & InstallerVersion & " -- tryb startu: " & $detectBootLaunchMode()

  discard forceWindowed # honorowane wewnątrz runInstallerGui przez pole `fullscreen`
  runInstallerGui()

when isMainModule:
  main()
