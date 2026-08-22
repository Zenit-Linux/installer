import std/[os, osproc, strformat]
import ./types

proc chroot(target: string, shellCmd: string): tuple[output: string, exitCode: int] =
  execCmdEx(&"chroot {target} /bin/sh -c \"{shellCmd}\"")

proc requireOk(target, shellCmd, context: string) =
  let (output, code) = chroot(target, shellCmd)
  if code != 0:
    raise newException(InstallerError, &"{context} nie powiodło się ({code}): {output}")

proc applyLocale*(target: string, locale: LocaleChoice) =
  writeFile(target / "etc" / "hostname", "") # nadpisywane przez applyAccount poniżej
  requireOk(target, &"echo '{locale.language} UTF-8' > /etc/locale.gen && locale-gen", "Generowanie locale")
  requireOk(target, &"echo 'LANG={locale.language}' > /etc/locale.conf", "Ustawianie LANG")
  requireOk(target, &"ln -sf /usr/share/zoneinfo/{locale.timezone} /etc/localtime", "Ustawianie strefy czasowej")
  requireOk(target, &"echo 'KEYMAP={locale.keyboardLayout}' > /etc/vconsole.conf", "Ustawianie układu klawiatury")

proc applyAccount*(target: string, account: UserAccount) =
  writeFile(target / "etc" / "hostname", account.hostname & "\n")

  requireOk(target,
    &"useradd -m -c '{account.fullName}' -s /bin/bash '{account.username}'",
    "Tworzenie użytkownika")

  # Hasła podawane przez `chpasswd` zamiast argumentu w linii poleceń,
  # żeby nie lądowały w historii procesów (ps aux) na żywym systemie.
  let passInput = &"{account.username}:{account.password}"
  discard execCmdEx(&"echo '{passInput}' | chroot {target} chpasswd")

  requireOk(target, &"usermod -aG wheel,sudo '{account.username}'", "Dodawanie do grupy administracyjnej")

  if account.rootPassword.len > 0:
    let rootInput = &"root:{account.rootPassword}"
    discard execCmdEx(&"echo '{rootInput}' | chroot {target} chpasswd")
  else:
    requireOk(target, "passwd -l root", "Blokowanie konta root (używaj sudo)")

  if account.autoLogin:
    createDir(target / "etc" / "gdm")
    writeFile(target / "etc" / "gdm" / "custom.conf",
      "[daemon]\nAutomaticLoginEnable=true\nAutomaticLogin=" & account.username & "\n")
