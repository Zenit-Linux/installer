import std/[json, osproc, strutils, os]
import ./types

proc listDisks*(): seq[DiskInfo] =
  ## Używa `lsblk --json` (dostępny na każdym rozsądnym live-CD) zamiast
  ## ręcznego parsowania /sys/block, bo daje już model/rozmiar/removable
  ## w ustrukturyzowanej formie.
  result = @[]
  if findExe("lsblk").len == 0:
    return
  let (output, code) = execCmdEx("lsblk --json --bytes -o NAME,MODEL,SIZE,RM,ROTA,TYPE")
  if code != 0 or output.len == 0:
    return
  var data: JsonNode
  try:
    data = parseJson(output)
  except JsonParsingError:
    return
  if not data.hasKey("blockdevices"): return
  for dev in data["blockdevices"]:
    if dev{"type"}.getStr("") != "disk": continue
    let name = dev{"name"}.getStr("")
    if name.len == 0: continue
    result.add DiskInfo(
      path: "/dev/" & name,
      model: dev{"model"}.getStr("nieznany model").strip(),
      sizeBytes: dev{"size"}.getBiggestInt(0),
      isRemovable: dev{"rm"}.getBool(false),
      isSsd: not dev{"rota"}.getBool(true)
    )

proc humanSize*(bytes: BiggestInt): string =
  const units = ["B", "KiB", "MiB", "GiB", "TiB"]
  var val = bytes.float
  var i = 0
  while val >= 1024.0 and i < units.high:
    val /= 1024.0
    inc i
  result = val.formatFloat(precision = 1) & " " & units[i]
