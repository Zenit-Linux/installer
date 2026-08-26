import std/osproc

proc hasInternetConnection*(host = "1.1.1.1"): bool =
  ## Szybki, jednorazowy test połączenia (pojedynczy ping, timeout 2s).
  ## Używane tylko jako informacja dla użytkownika w kroku "Sieć" (patrz
  ## app.nim::drawNetwork) -- nigdy nie blokuje dalszych kroków kreatora,
  ## bo np. środowisko bez uprawnień do ICMP zwróciłoby fałszywy negatyw
  ## mimo działającego DNS/HTTP, którego faktycznie potrzebuje zpm.
  let (_, code) = execCmdEx("ping -c 1 -W 2 " & host)
  code == 0
