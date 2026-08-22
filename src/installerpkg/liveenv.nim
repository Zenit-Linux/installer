import std/strutils
import ./types

proc readKernelCmdline*(): string =
  try:
    readFile("/proc/cmdline").strip()
  except IOError:
    ""

proc detectBootLaunchMode*(): BootLaunchMode =
  let cmdline = readKernelCmdline()
  if cmdline.len == 0:
    # brak /proc/cmdline (np. uruchomiony na hoście deweloperskim, nie
    # w środowisku live) -- traktuj jak samodzielne uruchomienie.
    return blmStandalone
  let params = cmdline.splitWhitespace()
  var isZenithLive = false
  var installerRequested = false
  for p in params:
    if p == "boot=zenith": isZenithLive = true
    if p == "installer=1" or p == "installer": installerRequested = true
  if not isZenithLive:
    return blmStandalone
  if installerRequested: blmInstallerAuto else: blmLiveOnly

proc isLiveEnvironment*(): bool =
  detectBootLaunchMode() != blmStandalone

proc shouldAutoLaunchFullscreen*(): bool =
  detectBootLaunchMode() == blmInstallerAuto
