import std/[unittest, os, strutils]
import ../src/installerpkg/fstab

suite "fstab":
  test "writeFstab creates /etc/fstab with expected structure and fallback device spec":
    let tmp = getTempDir() / "zenit_installer_test_fstab"
    removeDir(tmp)
    createDir(tmp / "etc")
    let entries = @[
      FstabEntry(partition: "/dev/does-not-exist1", mountpoint: "/", fsType: "ext4", options: "defaults"),
      FstabEntry(partition: "/dev/does-not-exist2", mountpoint: "/boot/efi", fsType: "vfat", options: "defaults,nofail"),
      FstabEntry(partition: "/dev/does-not-exist3", mountpoint: "none", fsType: "swap", options: "sw"),
    ]
    writeFstab(tmp, entries)
    let content = readFile(tmp / "etc" / "fstab")
    check "# /etc/fstab" in content
    # blkid nie znajdzie UUID dla nieistniejącego urządzenia -> fallback na
    # samą ścieżkę partycji (patrz fstab.nim::fstabLine)
    check "/dev/does-not-exist1" in content
    check "\t/\t" in content
    check "\tvfat\t" in content
    check "\tswap\t" in content
    removeDir(tmp)
