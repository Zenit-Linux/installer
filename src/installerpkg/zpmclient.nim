import std/[os, osproc, streams]

proc findZpmBinary(): string =
  ## Ten sam porządek wyszukiwania co w zlbpkg/zpm.nim: najpierw obok
  ## instalatora (osadzone przez `zlb build rootfs` -> embedInstaller /
  ## moduł zpm -> own), potem PATH.
  let candidates = [
    "/usr/local/bin/zpm",
    "/usr/bin/zpm",
    getAppDir() / "zpm"
  ]
  for c in candidates:
    if fileExists(c): return c
  findExe("zpm")

proc runZpm*(args: seq[string], onLine: proc(line: string) {.gcsafe.} = nil): tuple[ok: bool, output: string] =
  let bin = findZpmBinary()
  if bin.len == 0:
    return (false, "zpm nie znaleziony -- zainstaluj go najpierw (patrz custom/own-repository.json)")
  let p = startProcess(bin, args = args, options = {poUsePath, poStdErrToStdOut})
  var full = ""
  let stream = p.outputStream
  while not stream.atEnd:
    let line = stream.readLine()
    full.add(line & "\n")
    if not onLine.isNil: onLine(line)
  let code = p.waitForExit()
  close(p)
  (code == 0, full)

proc zpmInitTarget*(target, trustKeys: string, onLine: proc(line: string) {.gcsafe.} = nil): bool =
  var args = @["--root=" & target, "init"]
  if trustKeys.len > 0: args.add "--trust-keys=" & trustKeys
  let (ok, _) = runZpm(args, onLine)
  ok

proc zpmInstallTarget*(target: string, packages: seq[string], backend = "",
                        onLine: proc(line: string) {.gcsafe.} = nil): bool =
  if packages.len == 0: return true
  var args = @["--root=" & target]
  if backend.len > 0: args.add "--backend=" & backend
  args.add "install"
  args.add packages
  let (ok, _) = runZpm(args, onLine)
  ok

proc zpmSyncTarget*(target: string, onLine: proc(line: string) {.gcsafe.} = nil): bool =
  let (ok, _) = runZpm(@["--root=" & target, "sync"], onLine)
  ok

proc installEcosystemTool*(target, toolName: string,
                            onLine: proc(line: string) {.gcsafe.} = nil): bool =
  ## Wygodny skrót do instalowania narzędzia z custom/own-repository.json
  ## (np. dociągnięcie świeższej wersji `zpm` samego siebie do docelowego
  ## systemu) bez wymyślania nowej ścieżki -- to zwyczajny `zpm install`
  ## z backendem `own`.
  zpmInstallTarget(target, @[toolName], "own", onLine)
