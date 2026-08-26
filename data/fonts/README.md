# data/fonts/

Fidget renderuje tekst wektorowo i potrzebuje pliku fontu -- doklejanego
automatycznie pod ścieżkę `data/` przez `loadFont`/`startFidget` (stąd
katalog `data/` w KORZENIU repozytorium, nie `assets/fonts/` jak można by
się spodziewać patrząc tylko na argument przekazywany w kodzie).

## Ważne: `data/` musi leżeć obok katalogu roboczego, z którego uruchamiasz binarkę

Fidget doklejają `"data/"` do ścieżki assetu WZGLĘDEM BIEŻĄCEGO KATALOGU
ROBOCZEGO procesu (CWD) w chwili uruchomienia, NIE względem lokalizacji
samego pliku wykonywalnego. Innymi słowy:

```bash
cd /gdziekolwiek/leży/repo
./bin/installer          # OK -- CWD to katalog z data/
```

```bash
cd /gdziekolwiek/leży/repo/bin
./installer               # BŁĄD -- CWD to bin/, tam nie ma data/
                           # (chyba że skopiowałeś data/ też do bin/,
                           #  co robi `janet build.janet release/package`)
```

Jeśli GUI wysypuje się przy starcie komunikatem o braku pliku fontu albo
"key not found: head" (uszkodzony/zły plik), sprawdź NAJPIERW to -- w
większości przypadków to jest cała przyczyna, nie zepsuty build.
`app.nim::checkFontAvailable` próbuje to wykryć i wypisać czytelny
komunikat zamiast surowego wyjątku z głębi Fidget/pixie, ale samo
uruchomienie z niewłaściwego katalogu i tak trzeba poprawić ręcznie.

## Skąd ten plik

`UiFont-Regular.ttf` to font Instrument Sans (SIL Open Font License 1.1,
pełny tekst w `UiFont-OFL.txt` w tym samym katalogu) -- w odróżnieniu od
wcześniejszej wersji tego projektu, plik jest częścią repozytorium (nie
pobierany z sieci przy każdym budowaniu), żeby `nimble install`/`nimble
build`/ręczne `nim c` działały od razu, bez zależności od `janet
build.janet assets` czy dostępności konkretnego URL-a w chwili budowania.

`janet build.janet assets` tylko WERYFIKUJE, że ten plik tu jest i wypisuje
błąd, jeśli nie (np. po płytkim `git clone`/skopiowaniu samych `src/`) --
nic już nie pobiera domyślnie.

## Podmiana na inny font

Chcesz dokładnie oryginalnego Intera zamiast Instrument Sans? `janet
build.janet fetch-inter` podmienia ten plik (wymaga sieci). Możesz też
podmienić go ręcznie na dowolny TTF/OTF -- nazwa pliku i klucz `FontFamily`
("UiFont") są zdefiniowane w `src/installerpkg/widgets.nim` i
`src/installerpkg/app.nim::FontRelPath`, jeśli chcesz też zmienić nazwę.
