import std/[os, strutils]
import ./types
import ./hclcore as impl
import ./desktops

const AllDesktopsSentinel = "all"
  ## MUSI być identyczne z `zlbpkg/installerconfig.nim::AllDesktopsSentinel`
  ## w repo `zlb` -- ta sama zasada duplikacji co `RunnerConfigPath`/
  ## `RunnerBrandingDir` (patrz types.nim): jedna stała, dwa repo, bo nie
  ## ma między nimi współdzielonej biblioteki typów.

proc defaultRunnerConfig(): RunnerConfig =
  RunnerConfig(
    present: false,
    desktopSelector: false,
    desktops: @[],
    defaultDesktop: "",
    defaultLocale: "en_US.UTF-8",
    locales: @["en_US.UTF-8"],
    allowManualPartitioning: true,
    title: "",
    brandingIconPath: "",
    brandingBannerPath: ""
  )

proc loadRunnerConfig*(configPath = RunnerConfigPath, brandingDir = RunnerBrandingDir): RunnerConfig =
  ## Nigdy nie rzuca -- brak/uszkodzony config.hcl to sytuacja, w której
  ## instalator MUSI dać się uruchomić mimo wszystko (np. do
  ## developmentu poza obrazem Zenit, albo odzyskiwania po błędzie builda
  ## dystrybucji) -- po prostu z pustą listą desktopów (ekran wyboru DE
  ## się nie pokaże) i jednym domyślnym locale.
  result = defaultRunnerConfig()
  if not fileExists(configPath):
    return

  var root: impl.HclValue
  try:
    root = impl.parseHcl(readFile(configPath))
  except impl.HclError:
    # Uszkodzony config.hcl w obrazie -- nie blokujemy instalatora,
    # tylko cicho wracamy do domyślnych (executor/cliapp mogą zalogować
    # to wywołującemu, jeśli chcą -- ta funkcja się temu celowo nie sprzeciwia).
    return
  result.present = true

  let installerBlk = impl.getBlock(root, "installer")
  if installerBlk != nil:
    result.desktopSelector = impl.getBool(installerBlk, "desktop_selector", false)
    let desktops = impl.getStrList(installerBlk, "desktops")
    if desktops.len > 0: result.desktops = desktops
    result.defaultDesktop = impl.getStr(installerBlk, "default_desktop", "")
    result.defaultLocale = impl.getStr(installerBlk, "default_locale", result.defaultLocale)
    let locales = impl.getStrList(installerBlk, "locales")
    if locales.len > 0: result.locales = locales
    result.allowManualPartitioning = impl.getBool(
      installerBlk, "allow_manual_partitioning", true)
    result.title = impl.getStr(installerBlk, "title", "")

  let brandingBlk = impl.getBlock(root, "branding")
  if brandingBlk != nil:
    let icon = impl.getStr(brandingBlk, "icon", "")
    if icon.len > 0 and fileExists(brandingDir / icon):
      result.brandingIconPath = brandingDir / icon
    let banner = impl.getStr(brandingBlk, "banner", "")
    if banner.len > 0 and fileExists(brandingDir / banner):
      result.brandingBannerPath = brandingDir / banner

proc availableDesktops*(cfg: RunnerConfig): seq[string] =
  ## Lista do pokazania w kreatorze -- zawsze zawiera "none" (instalacja
  ## bez GUI) na końcu, nawet jeśli config.hcl go nie wymienia jawnie.
  ##
  ## Jeśli `installer.desktops` w config.hcl zawiera sentinel `"all"`,
  ## zwraca PEŁNY katalog znanych środowisk (patrz `desktops.nim::
  ## KnownDesktops`) zamiast tylko jawnie wymienionych -- to jest
  ## implementacja opcji "all": "użytkownik może wybrać własne środowisko
  ## graficzne z całej listy podczas instalacji".
  result = @[]
  if AllDesktopsSentinel in cfg.desktops:
    result.add knownDesktopIds()
  else:
    for d in cfg.desktops:
      if d.toLowerAscii != "none": result.add d
  result.add "none"
