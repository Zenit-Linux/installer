type DesktopInfo* = object
  id*: string
  displayName*: string
  placeholder*: bool  ## true = na razie zaślepka, brak pełnego zestawu pakietów

const KnownDesktops* = [
  DesktopInfo(id: "gnome", displayName: "GNOME", placeholder: false),
  DesktopInfo(id: "plasma", displayName: "KDE Plasma", placeholder: false),
  DesktopInfo(id: "xfce", displayName: "Xfce", placeholder: true),
  DesktopInfo(id: "cosmic", displayName: "COSMIC", placeholder: true),
  DesktopInfo(id: "budgie", displayName: "Budgie", placeholder: true),
  DesktopInfo(id: "mate", displayName: "MATE", placeholder: true),
  DesktopInfo(id: "lxqt", displayName: "LXQt", placeholder: true),
  DesktopInfo(id: "deepin", displayName: "Deepin (DDE)", placeholder: true),
  DesktopInfo(id: "enlightenment", displayName: "Enlightenment", placeholder: true),
  DesktopInfo(id: "zde", displayName: "ZDE (Zenit Desktop Environment)", placeholder: true),
  DesktopInfo(id: "blue", displayName: "Blue Environment", placeholder: true),
]
  ## `zde` i `blue` to WŁASNE środowiska ekosystemu Zenit (analogicznie do
  ## `zsrv`/`zboot`/`zesh`) -- na dziś obie tylko placeholdery, konwencja
  ## `modules/desktop-zde/` i `modules/desktop-blue/` istnieje, żeby
  ## dystrybucje mogły już teraz zarezerwować/przygotować te nazwy, bez
  ## czekania na pełną implementację.

proc findDesktopInfo*(id: string): DesktopInfo =
  for d in KnownDesktops:
    if d.id == id: return d
  DesktopInfo(id: id, displayName: id, placeholder: false)  ## nieznane -- pokaż jak jest

proc knownDesktopIds*(): seq[string] =
  result = @[]
  for d in KnownDesktops: result.add d.id
