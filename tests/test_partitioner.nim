import std/unittest
import ../src/installerpkg/partitioner

suite "partitioner":
  test "partitionPath appends the partition number directly for sdX-style disks":
    check partitionPath("/dev/sda", 1) == "/dev/sda1"
    check partitionPath("/dev/sdb", 2) == "/dev/sdb2"

  test "partitionPath inserts 'p' for disks ending in a digit (nvme/mmcblk/loop)":
    check partitionPath("/dev/nvme0n1", 1) == "/dev/nvme0n1p1"
    check partitionPath("/dev/mmcblk0", 2) == "/dev/mmcblk0p2"
    check partitionPath("/dev/loop0", 1) == "/dev/loop0p1"
