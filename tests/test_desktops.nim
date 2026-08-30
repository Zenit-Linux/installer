import std/[unittest, strutils]
import ../src/installerpkg/desktops
import ../src/installerpkg/config
import ../src/installerpkg/types

suite "desktops (kanoniczny katalog środowisk graficznych)":
  test "findDesktopInfo zwraca znane środowisko z displayName i placeholder":
    let gnome = findDesktopInfo("gnome")
    check gnome.displayName == "GNOME"
    check gnome.placeholder == false

    let cosmic = findDesktopInfo("cosmic")
    check cosmic.displayName == "COSMIC"
    check cosmic.placeholder == true

  test "findDesktopInfo dla nieznanego id zwraca je jako displayName, placeholder=false":
    let unknown = findDesktopInfo("totally-unknown-de")
    check unknown.displayName == "totally-unknown-de"
    check unknown.placeholder == false

  test "zde i blue są w katalogu jako placeholdery (własne środowiska Zenit)":
    let zde = findDesktopInfo("zde")
    check zde.placeholder == true
    check "Zenit" in zde.displayName

    let blue = findDesktopInfo("blue")
    check blue.placeholder == true
    check blue.displayName == "Blue Environment"

  test "knownDesktopIds zawiera przynajmniej gnome/plasma/xfce/cosmic/budgie/zde/blue":
    let ids = knownDesktopIds()
    for expected in ["gnome", "plasma", "xfce", "cosmic", "budgie", "zde", "blue"]:
      check expected in ids

suite "availableDesktops -- sentinel 'all'":
  test "desktops = [\"all\"] rozwija się do pełnego katalogu + none":
    let cfg = RunnerConfig(present: true, desktops: @["all"])
    let result = availableDesktops(cfg)
    check "none" in result
    check result[^1] == "none"  # none zawsze na końcu
    for id in knownDesktopIds():
      check id in result

  test "desktops = [\"gnome\", \"plasma\"] (bez 'all') NIE rozwija się do pełnego katalogu":
    let cfg = RunnerConfig(present: true, desktops: @["gnome", "plasma"])
    let result = availableDesktops(cfg)
    check result == @["gnome", "plasma", "none"]
    check "cosmic" notin result

  test "desktops = [\"all\", \"none\"] nie duplikuje 'none'":
    let cfg = RunnerConfig(present: true, desktops: @["all", "none"])
    let result = availableDesktops(cfg)
    check result.len == knownDesktopIds().len + 1  # + "none" raz
    check result[^1] == "none"
