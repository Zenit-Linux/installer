import std/[unittest, os, tempfiles]
import ../src/installerpkg/config
import ../src/installerpkg/types

## Testy dla `installerpkg/config.nim` -- czytanie `installer/config.hcl`
## W TRAKCIE DZIAŁANIA instalatora (przez wspólną bibliotekę hcl-nim,
## patrz `installerpkg/hclnim.nim`). Odpowiednik po stronie zlb (budowanie
## obrazu, nie runtime) ma własne testy w `zlb/tests/test_core.nim` (suite
## "installerconfig").

suite "config (runtime installer/config.hcl)":
  test "brak pliku -> present=false, sensowne domyślne (instalator nadal startuje)":
    let cfg = loadRunnerConfig("/nonexistent/path/config.hcl", "/nonexistent/branding")
    check cfg.present == false
    check cfg.desktops.len == 0
    check cfg.locales == @["en_US.UTF-8"]

  test "uszkodzony config.hcl -> present=false zamiast crasha":
    let dir = createTempDir("installertest", "")
    defer: removeDir(dir)
    let path = dir / "config.hcl"
    writeFile(path, "installer {\n  desktops = [\"gnome\"\n")  # niedomknięte
    let cfg = loadRunnerConfig(path, dir)
    check cfg.present == false

  test "parsuje installer {} i branding {} poprawnie":
    let dir = createTempDir("installertest", "")
    defer: removeDir(dir)
    let path = dir / "config.hcl"
    writeFile(path, """
      installer {
        desktop_selector = true
        desktops = ["gnome", "plasma", "xfce"]
        default_desktop = "gnome"
        locales = ["pl_PL.UTF-8", "en_US.UTF-8", "de_DE.UTF-8"]
        default_locale = "pl_PL.UTF-8"
        title = "Zenit Linux Installer"
      }
      branding {
        icon = "icon.png"
        banner = "banner.png"
      }
    """)
    writeFile(dir / "icon.png", "x")
    let cfg = loadRunnerConfig(path, dir)
    check cfg.present == true
    check cfg.desktopSelector == true
    check cfg.desktops == @["gnome", "plasma", "xfce"]
    check cfg.defaultDesktop == "gnome"
    check cfg.locales == @["pl_PL.UTF-8", "en_US.UTF-8", "de_DE.UTF-8"]
    check cfg.title == "Zenit Linux Installer"
    check cfg.brandingIconPath == dir / "icon.png"
    check cfg.brandingBannerPath == ""  # banner.png wskazany, ale nie istnieje na dysku

  test "availableDesktops zawsze dopisuje 'none' na końcu":
    let cfg = RunnerConfig(desktops: @["gnome", "plasma"])
    check availableDesktops(cfg) == @["gnome", "plasma", "none"]

  test "availableDesktops nie duplikuje 'none' jeśli już wymienione":
    let cfg = RunnerConfig(desktops: @["gnome", "none"])
    check availableDesktops(cfg) == @["gnome", "none"]
