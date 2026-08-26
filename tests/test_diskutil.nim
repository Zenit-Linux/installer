import std/unittest
import ../src/installerpkg/diskutil

suite "diskutil":
  test "humanSize formats bytes into human-readable units":
    check humanSize(0) == "0.0 B"
    check humanSize(1024) == "1.0 KiB"
    check humanSize(1_073_741_824) == "1.0 GiB"

  test "parentDiskOf strips trailing partition numbers":
    check parentDiskOf("/dev/sda1") == "/dev/sda"
    check parentDiskOf("/dev/sda12") == "/dev/sda"
    check parentDiskOf("/dev/sda") == "/dev/sda"

  test "parentDiskOf handles nvme/mmcblk 'pN' suffix style":
    check parentDiskOf("/dev/nvme0n1p1") == "/dev/nvme0n1"
    check parentDiskOf("/dev/mmcblk0p2") == "/dev/mmcblk0"
    check parentDiskOf("/dev/nvme0n1") == "/dev/nvme0n1"

  test "parentDiskOf on empty string returns empty string":
    check parentDiskOf("") == ""

suite "diskutil - filterOsesOnDisk":
  test "keeps only entries whose partition is on the given disk":
    let oses = @[
      "/dev/sda2:Windows 10:Windows:chain",
      "/dev/sdb1:Ubuntu 22.04:Ubuntu:linux",
    ]
    check filterOsesOnDisk(oses, "/dev/sda") == @["/dev/sda2:Windows 10:Windows:chain"]
    check filterOsesOnDisk(oses, "/dev/sdb") == @["/dev/sdb1:Ubuntu 22.04:Ubuntu:linux"]
    check filterOsesOnDisk(oses, "/dev/sdc").len == 0

  test "ignores malformed lines without a colon":
    check filterOsesOnDisk(@["garbage line"], "/dev/sda").len == 0
