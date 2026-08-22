# assets/fonts/

Fidget renderuje tekst wektorowo i potrzebuje pliku fontu wskazanego w
`installerpkg/app.nim` (`loadFont(FontFamily, "assets/fonts/Inter-Regular.ttf")`).

Ten katalog jest celowo pusty w repozytorium źródłowym (binarne pliki
fontów nie trafiają do kontroli wersji tego projektu) -- `build.janet`
pobiera `Inter-Regular.ttf` (licencja OFL, https://rsms.me/inter/) do
tego katalogu jako część zadania `assets` przed kompilacją. Jeśli
budujesz ręcznie bez `janet build.janet`, umieść tu dowolny plik TTF/OTF
i zaktualizuj nazwę w `app.nim`.
