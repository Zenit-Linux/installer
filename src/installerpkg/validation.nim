import std/strutils

proc isValidUsername*(name: string): bool =
  ## Podzbiór reguł `useradd`/`adduser`: małe litery, cyfry, `_`/`-`,
  ## zaczyna się od litery albo `_`, maks. 32 znaki.
  if name.len == 0 or name.len > 32: return false
  let first = name[0]
  if not ((first.isAlphaAscii and first.isLowerAscii) or first == '_'):
    return false
  for ch in name:
    if not ((ch.isAlphaAscii and ch.isLowerAscii) or ch.isDigit or ch in {'_', '-'}):
      return false
  true

proc isValidHostname*(name: string): bool =
  ## Pojedyncza etykieta hostname (RFC 1123, bez kropek): litery, cyfry,
  ## `-`, nie zaczyna/kończy się myślnikiem, maks. 63 znaki.
  if name.len == 0 or name.len > 63: return false
  if name[0] == '-' or name[^1] == '-': return false
  for ch in name:
    if not (ch.isAlphaNumeric or ch == '-'):
      return false
  true
