import std/[os, strutils]

proc findOpenglRoot(): string =
  ## Zwraca katalog zawierający prawdziwy opengl.nim, albo "" jeśli:
  ##  - paczka nie jest jeszcze zainstalowana,
  ##  - albo już leży tam, gdzie nimble się tego spodziewa (src/) i nic
  ##    nie trzeba dokładać.
  let nimbleDir = getEnv("NIMBLE_DIR", getHomeDir() / ".nimble")
  let pkgsDir = nimbleDir / "pkgs2"
  if not dirExists(pkgsDir):
    return ""
  for kind, path in walkDir(pkgsDir):
    if kind notin {pcDir, pcLinkToDir}: continue
    if not extractFilename(path).startsWith("opengl-"): continue
    if fileExists(path / "src" / "opengl.nim"):
      return ""  # już we właściwym miejscu, nic do naprawienia
    if fileExists(path / "opengl.nim"):
      return path
  ""

let openglRoot = findOpenglRoot()
if openglRoot.len > 0:
  echo "[config.nims] Znana niespójność paczki 'opengl': opengl.nim jest w " &
       openglRoot & ", nie w .../src -- dokładam poprawny --path."
  switch("path", openglRoot)

# --- Znane błędy typu w 'fidget': callbacki GLFW z "gołymi" typami Nim
# zamiast typów importc (`int32`/`float64` zamiast `cint`/`cdouble`) ----
# `fidget` (sprawdzone na 0.7.10, ten sam kod jest na `master`) rejestruje
# część callbacków GLFW z parametrami w "gołych" typach Nim zamiast tych,
# jakich oczekuje `staticglfw` >= 4.1.2 (wymagane przez fidget.nimble) w
# `*Fun` (np. `FrameBufferSizeFun = proc (window: Window, width: cint,
# height: cint)`, `ScrollFun = proc (window: Window, xoffset: cdouble,
# yoffset: cdouble)`). Typy w każdej parze mają identyczną reprezentację
# w pamięci (`cint`==`int32`, `cdouble`==`float64` na tej platformie),
# ale dla Nim to różne typy importc (patrz nim-lang/Nim#11797) --
# dopasowanie typu proc-a przy przekazywaniu callbacku jako wartości
# (np. `window.setFramebufferSizeCallback(onResize)`) nie przechodzi,
# więc kompilacja pada w `fidget/opengl/base.nim` błędem "type mismatch"
# ZANIM cokolwiek z tego repo w ogóle zacznie się kompilować. To błąd w
# `fidget`, nie w tym repozytorium. Sprawdziłem WSZYSTKIE 7 callbacków
# GLFW w tym pliku (onResize/onFocus/onSetKey/onScroll/onMouseButton/
# onMouseMove/onSetCharCallback) naprzeciw odpowiadających im `*Fun` w
# `staticglfw`: tylko te dwa niżej się nie zgadzają, reszta już poprawnie
# używa `cint`/`cdouble`/`cuint`. W obu przypadkach parametr, którego typ
# zmieniamy, albo w ogóle nie jest użyty w ciele proc-a (`onResize`),
# albo jest używany wyłącznie w arytmetyce zmiennoprzecinkowej, gdzie
# `cdouble` zachowuje się identycznie jak `float64` (`onScroll`) -- więc
# zmiana samych typów parametrów jest w 100% bezpieczna i nic w
# zachowaniu nie zmienia. Naprawiamy to tym samym sposobem co
# niespójność 'opengl' wyżej: łatamy plik już pobrany przez nimble do
# `~/.nimble/pkgs2/`, zamiast trzymać widelec całego `fidget` w tym repo.
const fidgetCallbackFixes = [
  ("onResize(handle: staticglfw.Window, w, h: int32)",
   "onResize(handle: staticglfw.Window, w, h: cint)"),
  ("onScroll(window: staticglfw.Window, xoffset, yoffset: float64)",
   "onScroll(window: staticglfw.Window, xoffset, yoffset: cdouble)"),
]

proc findFidgetBase(): string =
  ## Zwraca ścieżkę do `fidget/opengl/base.nim`, jeśli plik istnieje i
  ## nadal zawiera CHOĆ JEDEN z powyższych błędów typu, albo "" jeśli
  ## `fidget` nie jest (jeszcze) zainstalowany albo wszystkie znane
  ## niezgodności są już naprawione (np. przyszła wersja paczki, która
  ## sama używa poprawnych typów) -- w obu tych przypadkach nie ma czego
  ## łatać. Jeśli katalog `fidget-*` istnieje, ale żaden z dwóch znanych
  ## układów (`fidget/opengl/base.nim` albo `src/fidget/opengl/base.nim`)
  ## nie pasuje, wypisuje diagnostykę zamiast cicho nic nie robić --
  ## inaczej ta funkcja mogłaby milcząco nie łatać niczego, a kompilacja
  ## i tak potem padnie tym samym błędem "type mismatch" bez wyjaśnienia,
  ## dlaczego łatka się nie odpaliła.
  let nimbleDir = getEnv("NIMBLE_DIR", getHomeDir() / ".nimble")
  let pkgsDir = nimbleDir / "pkgs2"
  if not dirExists(pkgsDir):
    return ""
  for kind, path in walkDir(pkgsDir):
    # `notin {pcDir, pcLinkToDir}` (nie tylko `!= pcDir`) -- niektóre
    # instalacje nimble trzymają pakiety w pkgs2/ jako dowiązania
    # symboliczne do katalogów, a gołe `kind != pcDir` je pomijało,
    # przez co ta łatka mogła nigdy się nie uruchamiać mimo że fidget
    # był realnie zainstalowany (dokładnie ten sam filtr wyżej przy
    # 'opengl' miał tę samą lukę -- naprawione tam też).
    if kind notin {pcDir, pcLinkToDir}: continue
    if not extractFilename(path).startsWith("fidget-"): continue
    # Układ w pkgs2/ zależy od `srcDir` w fidget.nimble -- sprawdzamy
    # oba warianty, żeby nie połamać się na przyszłej/innej wersji paczki.
    var found = false
    for candidate in [path / "fidget" / "opengl" / "base.nim",
                      path / "src" / "fidget" / "opengl" / "base.nim"]:
      if not fileExists(candidate): continue
      found = true
      let content = readFile(candidate)
      for (bugPattern, _) in fidgetCallbackFixes:
        if content.contains(bugPattern):
          return candidate
    if not found:
      echo "[config.nims] Znaleziono katalog '" & extractFilename(path) &
           "' w pkgs2/, ale brak w nim fidget/opengl/base.nim pod " &
           "znanymi ścieżkami -- pomijam łatkę fidget (sprawdź układ paczki ręcznie)."
  ""

let fidgetBase = findFidgetBase()
if fidgetBase.len > 0:
  var content = readFile(fidgetBase)
  var patchedAny = false
  for (bugPattern, fixed) in fidgetCallbackFixes:
    if content.contains(bugPattern):
      echo "[config.nims] Znany błąd typu w 'fidget' -- łatam '" &
           bugPattern & "' w " & fidgetBase & "."
      content = content.replace(bugPattern, fixed)
      patchedAny = true
  if patchedAny:
    writeFile(fidgetBase, content)
