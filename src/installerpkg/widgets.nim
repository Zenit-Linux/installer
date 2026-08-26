import std/strutils
import fidget

const
  ColorBg*        = "#1e1e2e"
  ColorBgAlt*     = "#181825"
  ColorSurface*   = "#313244"
  ColorAccent*    = "#89b4fa"
  ColorAccentDim* = "#45475a"
  ColorDanger*    = "#f38ba8"
  ColorText*      = "#cdd6f4"
  ColorTextDim*   = "#a6adc8"
  FontFamily*     = "UiFont" ## klucz w rejestrze fontów Fidget -- MUSI się zgadzać
                              ## z pierwszym argumentem `loadFont` w app.nim::runInstallerGui.
                              ## Fizycznie to Instrument Sans (SIL OFL 1.1, patrz
                              ## data/fonts/UiFont-OFL.txt) -- nazwa klucza jest tylko
                              ## wewnętrznym identyfikatorem Fidget, nie musi odpowiadać
                              ## prawdziwej nazwie rodziny fontu.

proc heading*(id, label: string, x, y, w: float, size: float = 28) =
  text id:
    box x, y, w, size * 1.4
    fill ColorText
    font FontFamily, size, 700, size * 1.2, hLeft, vTop
    characters label

proc paragraph*(id, label: string, x, y, w, h: float) =
  text id:
    box x, y, w, h
    fill ColorTextDim
    font FontFamily, 15, 400, 22, hLeft, vTop
    characters label

proc button*(id, label: string, x, y, w, h: float,
             primary = false, danger = false, enabled = true,
             onClickAction: proc() = nil) =
  let bg = if not enabled: ColorAccentDim
           elif danger: ColorDanger
           elif primary: ColorAccent
           else: ColorSurface
  let fg = if primary or danger: ColorBgAlt else: ColorText
  group id:
    box x, y, w, h
    if enabled and not onClickAction.isNil:
      onClick:
        onClickAction()
    rectangle id & "-bg":
      box 0, 0, w, h
      fill bg
      cornerRadius 10
    text id & "-label":
      box 0, 0, w, h
      fill fg
      font FontFamily, 15, 600, 0, hCenter, vCenter
      characters label

proc choiceChip*(id, label: string, x, y, w, h: float, selected: bool,
                  onClickAction: proc()) =
  group id:
    box x, y, w, h
    onClick:
      onClickAction()
    rectangle id & "-bg":
      box 0, 0, w, h
      fill (if selected: ColorAccent else: ColorSurface)
      cornerRadius 8
    text id & "-label":
      box 0, 0, w, h
      fill (if selected: ColorBgAlt else: ColorText)
      font FontFamily, 14, 500, 0, hCenter, vCenter
      characters label

proc checkbox*(id, label: string, x, y, w: float, value: var bool) =
  const boxSize = 22.0
  group id:
    box x, y, w, boxSize
    onClick:
      value = not value
    rectangle id & "-box":
      box 0, 0, boxSize, boxSize
      fill (if value: ColorAccent else: ColorSurface)
      cornerRadius 6
    if value:
      text id & "-check":
        box 0, 0, boxSize, boxSize
        fill ColorBgAlt
        font FontFamily, 15, 700, 0, hCenter, vCenter
        characters "V"
    text id & "-label":
      box boxSize + 10, 0, w - boxSize - 10, boxSize
      fill ColorText
      font FontFamily, 15, 400, 0, hLeft, vCenter
      characters label

proc textField*(id, placeholder: string, x, y, w, h: float, value: var string) =
  ## Pole tekstowe: `binding value` w środku `text` robi WSZYSTKO
  ## (fokus po kliknięciu, kursor, backspace, strzałki, zaznaczanie) --
  ## to jest wbudowany mechanizm Fidget (patrz typography/textbox), a
  ## nie coś, co odtwarzamy ręcznie przez keyboard.inputText.
  ##
  ## Bez maskowania -- dla pól hasła użyj `passwordField` niżej.
  group id:
    box x, y, w, h
    rectangle id & "-bg":
      box 0, 0, w, h
      fill ColorSurface
      cornerRadius 8
      stroke ColorAccentDim
      strokeWeight 1.5
    text id & "-value":
      box 12, 0, w - 24, h
      fill ColorText
      font FontFamily, 15, 400, 0, hLeft, vCenter
      binding value
    if value.len == 0:
      text id & "-placeholder":
        box 12, 0, w - 24, h
        fill ColorTextDim
        font FontFamily, 15, 400, 0, hLeft, vCenter
        characters placeholder

proc passwordField*(id, placeholder: string, x, y, w, h: float, value: var string) =
  ## Jak `textField`, ale maskuje wpisywane znaki -- bez zgadywania
  ## niepotwierdzonego API Fidget do podmiany renderowanych znaków
  ## WEWNĄTRZ `binding` (o czym ostrzega komentarz w `textField`). Zamiast
  ## tego: prawdziwe pole edycyjne nadal używa `binding value` (żeby
  ## zadziałały kursor/backspace/strzałki -- to jedyny sposób edycji, jaki
  ## mamy), ale jego kolor tekstu (`fill`) jest taki sam jak tło pola, więc
  ## wpisywane znaki są wizualnie niewidoczne. Osobny, nakładający się
  ## tekst (zwykłe `characters`, NIE `binding`) pokazuje kropki w liczbie
  ## równej `value.len`. Oba triki (`binding` i `fill` w kolorze tła) są
  ## już użyte gdzie indziej w tym pliku -- to nie jest nowe, niepewne API,
  ## tylko ich kombinacja.
  group id:
    box x, y, w, h
    rectangle id & "-bg":
      box 0, 0, w, h
      fill ColorSurface
      cornerRadius 8
      stroke ColorAccentDim
      strokeWeight 1.5
    text id & "-edit":
      box 12, 0, w - 24, h
      fill ColorSurface # celowo = kolor tła: prawdziwa edycja, niewidoczny tekst
      font FontFamily, 15, 400, 0, hLeft, vCenter
      binding value
    if value.len > 0:
      text id & "-dots":
        box 12, 0, w - 24, h
        fill ColorText
        font FontFamily, 15, 400, 0, hLeft, vCenter
        characters "•".repeat(value.len)
    else:
      text id & "-placeholder":
        box 12, 0, w - 24, h
        fill ColorTextDim
        font FontFamily, 15, 400, 0, hLeft, vCenter
        characters placeholder

proc sizeStepper*(id: string, x, y, w, h: float, valueMiB: var int,
                   stepMiB, minMiB, maxMiB: int) =
  ## Licznik +/- do wyboru rozmiaru w MiB -- prostszy i bezpieczniejszy niż
  ## parsowanie na bieżąco dowolnego tekstu wpisanego w textField, i
  ## spójny ze stylem reszty UI (wybiera się klikając, nie pisząc liczby).
  ## Trzy niezależne, płaskie `group`-y (minus/wartość/plus) zamiast
  ## zagnieżdżania grup w grupie -- ten sam, jedno-poziomowy wzorzec co
  ## `button`/`checkbox`/`textField` powyżej, żadnego nowego API.
  let btnW = h
  let labelW = w - 2 * btnW - 16
  group id & "-minus":
    box x, y, btnW, h
    onClick:
      valueMiB = max(minMiB, valueMiB - stepMiB)
    rectangle id & "-minus-bg":
      box 0, 0, btnW, h
      fill ColorSurface
      cornerRadius 8
    text id & "-minus-label":
      box 0, 0, btnW, h
      fill ColorText
      font FontFamily, 18, 700, 0, hCenter, vCenter
      characters "-"
  group id & "-value":
    box x + btnW + 8, y, labelW, h
    text id & "-value-label":
      box 0, 0, labelW, h
      fill ColorText
      font FontFamily, 15, 500, 0, hCenter, vCenter
      characters (if valueMiB >= 1024: (valueMiB.float / 1024.0).formatFloat(precision = 1) & " GiB"
                  else: $valueMiB & " MiB")
  group id & "-plus":
    box x + btnW + 8 + labelW + 8, y, btnW, h
    onClick:
      valueMiB = min(maxMiB, valueMiB + stepMiB)
    rectangle id & "-plus-bg":
      box 0, 0, btnW, h
      fill ColorSurface
      cornerRadius 8
    text id & "-plus-label":
      box 0, 0, btnW, h
      fill ColorText
      font FontFamily, 18, 700, 0, hCenter, vCenter
      characters "+"

proc progressBar*(id: string, x, y, w, h: float, fraction: float) =
  group id:
    box x, y, w, h
    rectangle id & "-track":
      box 0, 0, w, h
      fill ColorSurface
      cornerRadius h / 2
    rectangle id & "-fill":
      box 0, 0, w * clamp(fraction, 0.0, 1.0), h
      fill ColorAccent
      cornerRadius h / 2

proc sidebarItem*(id, label: string, x, y, w, h: float, active, done: bool) =
  group id:
    box x, y, w, h
    if active:
      rectangle id & "-bg":
        box 0, 0, w, h
        fill ColorSurface
        cornerRadius 8
    text id & "-label":
      box 12, 0, w - 12, h
      fill (if done: ColorAccent elif active: ColorText else: ColorTextDim)
      font FontFamily, 14, (if active: 700 else: 400), 0, hLeft, vCenter
      characters label
