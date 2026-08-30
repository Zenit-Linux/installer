version       = "0.1.0"
author        = "Zenit Linux Developers"
description   = "Zenit Installer -- graficzny instalator Zenit Linux (Fidget UI)"
license       = "BSD-3"
srcDir        = "src"
bin           = @["installer"]
binDir        = "bin"

# Dependencies
requires "nim >= 2.0.0"
requires "fidget >= 0.4.0"   # immediate-mode UI (treeform/fidget) -- lekki, nowoczesny,
                              # renderowany wektorowo przez OpenGL/pixie, bez zależności od GTK/Qt
requires "hcl_nim >= 0.1"

# --- Zależność na `opengl` --------------------------------------------
# UWAGA: ostatnie wydania paczki nimble `opengl` (m.in. commit taggowany
# jako 1.2.9, oraz -- jak się okazuje -- także #head, bo wskazuje na ten
# sam commit) mają pliki *.nim w KORZENIU paczki, a nie w src/. Log
# builda pokazuje przy okazji:
#   Warning: Declarative parser failed, the file had to be parsed with
#            the VM parser. Please fix your nimble file.
# co jest tym samym symptomem tej niespójności w opengl.nimble. Nimble
# mimo to każe nimowi szukać w .../opengl-<hash>/src/opengl.nim, którego
# tam nie ma -> `Error: cannot open file: opengl` w fidget/opengl/base.nim.
#
# Pinowanie wersji NIE pomaga (sprawdzone: #head i 1.2.9 to ten sam
# commit/układ plików) -- naprawa jest w config.nims (w tym samym
# katalogu co ten plik), ładowanym automatycznie przez `nim` przy każdej
# kompilacji: dokłada poprawny --path wykryty dynamicznie, bez
# dotykania cache'u nimble. Zobacz README.md, sekcja "Znany problem".
requires "opengl >= 1.2.3"

task buildRelease, "Build optimized release binary":
  exec "test -f data/fonts/UiFont-Regular.ttf || (echo 'BRAK data/fonts/UiFont-Regular.ttf -- patrz data/fonts/README.md' && exit 1)"
  exec "nim c -d:release -d:ssl --opt:speed -o:bin/installer src/installer.nim"

task buildServer, "Build a headless binary (-d:server) -- no Fidget/OpenGL/X11 linked at all":
  exec "nim c -d:release -d:server -d:ssl --opt:speed -o:bin/installer-server src/installer.nim"

task test, "Run unit tests (pure-logic + isolated tempdir file I/O, no real disk access)":
  exec "nim c -r tests/test_diskutil.nim"
  exec "nim c -r tests/test_validation.nim"
  exec "nim c -r tests/test_partitioner.nim"
  exec "nim c -r tests/test_i18n.nim"
  exec "nim c -r tests/test_fstab.nim"
  exec "nim c -r tests/test_cliapp.nim"
