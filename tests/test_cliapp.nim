import std/[unittest, os, tables]
import ../src/installerpkg/cliapp

suite "cliapp - parseAnswerFile":
  test "parses key=value lines, trims whitespace, skips comments and blanks":
    let tmp = getTempDir() / "zenit_installer_test_answers.conf"
    writeFile(tmp, "# to jest komentarz\n\n" &
      "username = jkowalski\n" &
      "password=tajne123\n" &
      "  hostname =  zenit-test  \n\n" &
      "extra_packages=vscode -> own,firefox -> flatpak\n")
    let cfg = parseAnswerFile(tmp)
    check getOr(cfg, "username", "") == "jkowalski"
    check getOr(cfg, "password", "") == "tajne123"
    check getOr(cfg, "hostname", "") == "zenit-test"
    check getOr(cfg, "extra_packages", "") == "vscode -> own,firefox -> flatpak"
    check getOr(cfg, "nonexistent", "default") == "default"
    removeFile(tmp)

suite "cliapp - getOr/getBoolOr/getIntOr":
  test "getBoolOr recognizes truthy values and falls back otherwise":
    var cfg = initTable[string, string]()
    cfg["autologin"] = "true"
    cfg["luks"] = "tak"
    check getBoolOr(cfg, "autologin", false) == true
    check getBoolOr(cfg, "luks", false) == true
    check getBoolOr(cfg, "missing", false) == false
    check getBoolOr(cfg, "missing", true) == true

  test "getIntOr parses valid integers and falls back on bad input":
    var cfg = initTable[string, string]()
    cfg["swap_size_mib"] = "4096"
    cfg["bad_number"] = "not-a-number"
    check getIntOr(cfg, "swap_size_mib", 2048) == 4096
    check getIntOr(cfg, "bad_number", 2048) == 2048
    check getIntOr(cfg, "missing", 2048) == 2048

suite "cliapp - hasDuplicatePartitions":
  test "detects repeated non-empty paths, ignores empty ones":
    check hasDuplicatePartitions(["/dev/sda1", "/dev/sda2", "/dev/sda1"])
    check not hasDuplicatePartitions(["/dev/sda1", "/dev/sda2", ""])
    check not hasDuplicatePartitions(["", "", ""])
