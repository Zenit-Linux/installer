import std/unittest
import std/strutils
import ../src/installerpkg/validation

suite "validation - username":
  test "accepts valid usernames":
    check isValidUsername("kasia")
    check isValidUsername("_svc")
    check isValidUsername("user-1")
    check isValidUsername("a")

  test "rejects invalid usernames":
    check not isValidUsername("")
    check not isValidUsername("Kasia")       # wielka litera
    check not isValidUsername("1user")       # zaczyna się od cyfry
    check not isValidUsername("user name")   # spacja
    check not isValidUsername("user.name")   # kropka
    check not isValidUsername(repeat("a", 33))  # za długie

suite "validation - hostname":
  test "accepts valid hostnames":
    check isValidHostname("zenit")
    check isValidHostname("host-1")
    check isValidHostname("A1")

  test "rejects invalid hostnames":
    check not isValidHostname("")
    check not isValidHostname("-bad")
    check not isValidHostname("bad-")
    check not isValidHostname("bad host")
    check not isValidHostname("bad.host")
