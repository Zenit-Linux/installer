import std/[tables, strutils]

type UiLang* = enum langPl, langEn, langDe, langFr, langEs

var currentLang*: UiLang = langPl

const entries = [
  # -- wspólne przyciski/etykiety ----------------------------------------
  ("btn_back", "Wstecz", "Back"),
  ("btn_next", "Dalej", "Next"),
  ("btn_start", "Rozpocznij", "Start"),
  ("btn_install", "Instaluj", "Install"),
  ("btn_reboot", "Uruchom ponownie", "Reboot"),
  ("btn_check_connection", "Sprawdź połączenie", "Check connection"),
  ("btn_back_to_summary", "Wróć do podsumowania", "Back to summary"),

  # -- pasek boczny / kroki kreatora --------------------------------------
  ("nav_welcome", "Witaj", "Welcome"),
  ("nav_language", "Język", "Language"),
  ("nav_keyboard", "Klawiatura", "Keyboard"),
  ("nav_network", "Sieć", "Network"),
  ("nav_disk", "Dysk", "Disk"),
  ("nav_partition", "Partycjonowanie", "Partitioning"),
  ("nav_account", "Konto", "Account"),
  ("nav_summary", "Podsumowanie", "Summary"),

  # -- powitanie -----------------------------------------------------------
  ("w_title", "Witamy w instalatorze $1", "Welcome to the $1 installer"),
  ("w_body",
    "Ten kreator przeprowadzi Cię przez instalację $1 na tym komputerze. " &
    "Wszystkie pakiety -- system bazowy i opcjonalne oprogramowanie -- są " &
    "instalowane przez zpm, nigdy pojedynczym skryptem curl.",
    "This wizard will walk you through installing $1 on this computer. " &
    "All packages -- the base system and any optional software -- are " &
    "installed through zpm, never a single curl script."),
  ("w_standalone_warning",
    "Instalator działa na już zainstalowanym systemie (tryb reinstalacji/" &
    "ratunkowy) -- kontynuacja nadpisze wybrany dysk.",
    "The installer is running on an already-installed system (reinstall/" &
    "recovery mode) -- continuing will overwrite the disk you select."),

  # -- język ---------------------------------------------------------------
  ("l_title", "Wybierz język systemu", "Choose the system language"),

  # -- klawiatura / strefa czasowa ------------------------------------------
  ("k_title", "Klawiatura i strefa czasowa", "Keyboard and timezone"),
  ("k_kb_label", "Układ klawiatury", "Keyboard layout"),
  ("k_tz_label", "Strefa czasowa", "Timezone"),

  # -- sieć -----------------------------------------------------------------
  ("n_title", "Połączenie sieciowe", "Network connection"),
  ("n_body",
    "Instalator używa zpm do pobierania pakietów -- upewnij się, że masz " &
    "połączenie z internetem (Wi-Fi/Ethernet) skonfigurowane przez " &
    "NetworkManager w tej sesji live.",
    "The installer uses zpm to fetch packages -- make sure you have a " &
    "working internet connection (Wi-Fi/Ethernet) configured through " &
    "NetworkManager in this live session."),
  ("n_result_ok", "Połączenie działa.", "Connection is working."),
  ("n_result_fail",
    "Brak połączenia -- instalacja pakietów przez zpm może się nie powieść.",
    "No connection -- installing packages via zpm may fail."),
  ("n_continue_anyway", "Kontynuować bez potwierdzonego połączenia?",
    "Continue without confirmed connectivity?"),

  # -- dysk -------------------------------------------------------------------
  ("d_title", "Wybierz dysk docelowy", "Choose the target disk"),
  ("d_empty", "Nie wykryto żadnych dysków (lsblk niedostępny lub brak nośników).",
    "No disks were detected (lsblk unavailable or no media present)."),
  ("d_dualboot",
    "Wykryto inne systemy operacyjne -- zostaną dodane do menu GRUB: $1",
    "Other operating systems detected -- they will be added to the GRUB menu: $1"),
  ("d_too_small", "Wybrany dysk jest zbyt mały (minimum $1).",
    "The selected disk is too small (minimum $1)."),
  ("d_live_warning",
    "UWAGA: to wygląda na nośnik, z którego uruchomiona jest ta sesja live. " &
    "Wybór go jako celu instalacji prawdopodobnie zepsuje bieżącą sesję.",
    "WARNING: this looks like the medium this live session is running from. " &
    "Picking it as the install target will likely break the current session."),
  ("d_live_confirm", "Rozumiem ryzyko, to jest właściwy dysk",
    "I understand the risk, this is the right disk"),
  ("tag_removable", " [wymienny]", " [removable]"),
  ("tag_live", " [NOŚNIK LIVE]", " [LIVE MEDIUM]"),

  # -- partycjonowanie ---------------------------------------------------------
  ("p_title", "Partycjonowanie", "Partitioning"),
  ("p_disk", "Dysk: $1", "Disk: $1"),
  ("p_mode_label", "Tryb partycjonowania", "Partitioning mode"),
  ("p_mode_erase", "Wymaż cały dysk", "Erase entire disk"),
  ("p_mode_manual", "Ręcznie (istniejące partycje)", "Manual (existing partitions)"),
  ("p_mode_freespace", "wolna przestrzeń", "free space"),
  ("p_boot_label", "Tryb rozruchu", "Boot mode"),
  ("p_boot_uefi", "UEFI", "UEFI"),
  ("p_boot_bios", "BIOS / legacy", "BIOS / legacy"),
  ("p_warn", "UWAGA: cały dysk $1 zostanie WYMAZANY i sformatowany.",
    "WARNING: the entire disk $1 will be ERASED and formatted."),
  ("p_erase_dualboot_warn",
    "Ten dysk zawiera też wykryty inny system: $1 -- zostanie usunięty razem z resztą dysku.",
    "This disk also contains a detected other system: $1 -- it will be erased along with the rest of the disk."),
  ("p_confirm", "Rozumiem, wymaż cały dysk", "I understand, erase the entire disk"),
  ("p_fs_label", "System plików", "Filesystem"),
  ("p_swap_label", "Partycja wymiany (swap)", "Swap"),
  ("p_swap_none", "Brak", "None"),
  ("p_swap_partition", "Partycja (2 GiB)", "Partition (2 GiB)"),
  ("p_swap_file", "Plik (2 GiB, w roocie)", "File (2 GiB, inside root)"),
  ("p_manual_info",
    "Na następnym ekranie przypiszesz istniejące partycje do ról (root, " &
    "ESP lub bios_grub, opcjonalnie home i swap). Instalator ich nie " &
    "tworzy ani nie zmienia im rozmiaru.",
    "On the next screen you will assign existing partitions to roles " &
    "(root, ESP or bios_grub, optionally home and swap). The installer " &
    "never creates or resizes them."),
  ("p_encrypt", "Szyfruj partycję roota (LUKS)", "Encrypt root partition (LUKS)"),
  ("p_luks_warn",
    "Zapisz to hasło w bezpiecznym miejscu -- bez niego dysk jest NIEODZYSKIWALNY.",
    "Write this passphrase down somewhere safe -- without it the disk is UNRECOVERABLE."),
  ("p_luks_pass", "Hasło szyfrowania dysku", "Disk encryption passphrase"),
  ("p_luks_pass2", "Powtórz hasło szyfrowania", "Repeat encryption passphrase"),
  ("p_luks_mismatch", "Hasła szyfrowania się różnią.", "Encryption passphrases do not match."),

  # -- ręczne partycjonowanie -----------------------------------------------
  ("mp_title", "Przypisz istniejące partycje", "Assign existing partitions"),
  ("mp_empty",
    "Nie wykryto żadnych partycji na tym dysku (lsblk niedostępny albo dysk jest pusty).",
    "No partitions were detected on this disk (lsblk unavailable or the disk is empty)."),
  ("mp_esp", "Partycja ESP (FAT32, montowana pod /boot/efi)",
    "ESP partition (FAT32, mounted at /boot/efi)"),
  ("mp_bg", "Partycja bios_grub (surowa, nieformatowana)",
    "bios_grub partition (raw, never formatted)"),
  ("mp_root", "Partycja roota (zostanie sformatowana)", "Root partition (will be formatted)"),
  ("mp_home", "Partycja /home (opcjonalnie)", "/home partition (optional)"),
  ("mp_swap", "Partycja swap (opcjonalnie)", "Swap partition (optional)"),
  ("mp_none", "(brak)", "(none)"),
  ("mp_swapfile",
    "Zamiast tego użyj pliku wymiany (2 GiB) wewnątrz roota",
    "Use a swap file (2 GiB) inside root instead"),
  ("mp_duplicate",
    "Ta sama partycja jest przypisana do więcej niż jednej roli -- popraw wybór.",
    "The same partition is assigned to more than one role -- fix your selection."),
  ("mp_too_small", "Partycja roota jest zbyt mała (minimum $1).",
    "The root partition is too small (minimum $1)."),

  # -- konto --------------------------------------------------------------------
  ("a_title", "Utwórz konto użytkownika", "Create a user account"),
  ("a_fullname", "Imię i nazwisko", "Full name"),
  ("a_username", "Nazwa użytkownika", "Username"),
  ("a_username_hint",
    "małe litery, cyfry, _ i -, zaczynająca się od litery lub _",
    "lowercase letters, digits, _ and -, starting with a letter or _"),
  ("a_hostname", "Nazwa komputera", "Computer name"),
  ("a_hostname_hint",
    "litery, cyfry i -, bez - na początku/końcu",
    "letters, digits and -, no leading/trailing -"),
  ("a_password", "Hasło", "Password"),
  ("a_password2", "Powtórz hasło", "Repeat password"),
  ("a_password_mismatch", "Hasła się różnią.", "Passwords do not match."),
  ("val_password_min", "Minimum $1 znaków.", "Minimum $1 characters."),
  ("a_autologin", "Automatyczne logowanie", "Automatic login"),
  ("a_pkg_label", "Dodatkowe oprogramowanie (instalowane przez zpm):",
    "Additional software (installed via zpm):"),

  # -- podsumowanie ----------------------------------------------------------
  ("s_title", "Podsumowanie", "Summary"),
  ("s_disk", "Dysk: $1 ($2), tryb: $3, system plików: $4, rozruch: $5",
    "Disk: $1 ($2), mode: $3, filesystem: $4, boot: $5"),
  ("s_security", "Szyfrowanie LUKS: $1, swap: $2", "LUKS encryption: $1, swap: $2"),
  ("s_user", "Użytkownik: $1 ($2), host: $3", "User: $1 ($2), host: $3"),
  ("s_locale", "Język: $1, klawiatura: $2, strefa: $3", "Language: $1, keyboard: $2, timezone: $3"),
  ("s_dualboot",
    "Inne systemy wykryte przez os-prober (zostaną dodane do menu GRUB): $1",
    "Other systems detected by os-prober (will be added to the GRUB menu): $1"),
  ("s_pkgs",
    "Pakiety systemu bazowego oraz wybrane pozycje dodatkowe instalowane " &
    "wyłącznie przez zpm -- zero curl.",
    "Base system packages and any selected extras are installed only " &
    "through zpm -- zero curl."),
  ("val_on", "włączone", "enabled"),
  ("val_off", "wyłączone", "disabled"),
  ("val_none", "brak", "none"),
  ("val_swap_new_partition", "2 GiB (nowa partycja)", "2 GiB (new partition)"),
  ("val_swap_existing", "istniejąca partycja", "existing partition"),
  ("val_swap_file", "plik wymiany", "swap file"),

  # -- instalacja / koniec ---------------------------------------------------
  ("i_title", "Instalowanie $1...", "Installing $1..."),
  ("done_title", "Instalacja zakończona!", "Installation complete!"),
  ("done_body", "Możesz teraz zrestartować komputer i uruchomić $1 z dysku.",
    "You can now reboot and start $1 from disk."),
  ("err_title", "Instalacja nie powiodła się", "Installation failed"),

  # -- tryb tekstowy (--server) -----------------------------------------------
  ("cli_banner", "$1 -- instalacja tekstowa (tryb --server, bez GUI)",
    "$1 -- text-mode installation (--server mode, no GUI)"),
  ("cli_lang_prompt", "Wybierz język systemu:", "Choose the system language:"),
  ("cli_kb_prompt", "Wybierz układ klawiatury:", "Choose keyboard layout:"),
  ("cli_tz_prompt", "Wybierz strefę czasową:", "Choose timezone:"),
  ("cli_net_checking", "Sprawdzanie połączenia sieciowego...", "Checking network connection..."),
  ("cli_aborted", "Instalacja przerwana.", "Installation aborted."),
  ("cli_no_disks",
    "Nie wykryto żadnych dysków (lsblk niedostępny lub brak nośników). Przerywam.",
    "No disks detected (lsblk unavailable or no media present). Aborting."),
  ("cli_disk_prompt", "Wybierz dysk docelowy:", "Choose the target disk:"),
  ("cli_disk_too_small", "Wybrany dysk jest zbyt mały (minimum $1). Wybierz inny.",
    "The selected disk is too small (minimum $1). Choose another one."),
  ("cli_disk_live_confirm",
    "To jest nośnik live -- na pewno kontynuować z tym dyskiem?",
    "This is the live medium -- really continue with this disk?"),
  ("cli_boot_prompt", "Rozruch UEFI? (Nie = BIOS/legacy)", "UEFI boot? (No = BIOS/legacy)"),
  ("cli_mode_prompt",
    "Wymazać cały dysk $1 i użyć prostego layoutu? (Nie = przypisanie istniejących partycji)",
    "Erase the entire disk $1 and use the simple layout? (No = assign existing partitions)"),
  ("cli_erase_confirm", "Rozumiesz i chcesz kontynuować?", "Do you understand and want to continue?"),
  ("cli_fs_prompt", "System plików:", "Filesystem:"),
  ("cli_fs_prompt_manual", "System plików dla roota (i /home, jeśli formatowane):",
    "Filesystem for root (and /home, if formatted):"),
  ("cli_swap_size_prompt", "Rozmiar swapu w MiB", "Swap size in MiB"),
  ("cli_swap_prompt", "Wymiana (swap):", "Swap:"),
  ("cli_no_partitions", "Nie wykryto żadnych partycji na tym dysku. Przerywam.",
    "No partitions detected on this disk. Aborting."),
  ("cli_root_too_small",
    "Wybrana partycja roota jest zbyt mała (minimum $1). Wybierz inną.",
    "The selected root partition is too small (minimum $1). Choose another one."),
  ("cli_home_ask", "Użyć osobnej partycji /home?", "Use a separate /home partition?"),
  ("cli_swap_ask", "Użyć osobnej partycji swap?", "Use a separate swap partition?"),
  ("cli_swapfile_ask",
    "Zamiast tego użyć pliku wymiany (2 GiB) wewnątrz roota?",
    "Use a swap file (2 GiB) inside root instead?"),
  ("cli_luks_ask", "Szyfrować partycję roota (LUKS)?", "Encrypt root partition (LUKS)?"),
  ("cli_luks_pass_prompt", "Hasło szyfrowania dysku: ", "Disk encryption passphrase: "),
  ("cli_luks_pass2_prompt", "Powtórz hasło szyfrowania: ", "Repeat encryption passphrase: "),
  ("cli_luks_empty", "Hasło nie może być puste.", "Passphrase cannot be empty."),
  ("cli_luks_too_short", "Hasło szyfrowania musi mieć co najmniej $1 znaków.",
    "The encryption passphrase must be at least $1 characters long."),
  ("cli_fullname_prompt", "Imię i nazwisko: ", "Full name: "),
  ("cli_username_prompt", "Nazwa użytkownika: ", "Username: "),
  ("cli_username_invalid",
    "Nieprawidłowa nazwa użytkownika (małe litery, cyfry, _ i -, zaczynająca się od litery lub _).",
    "Invalid username (lowercase letters, digits, _ and -, starting with a letter or _)."),
  ("cli_hostname_prompt", "Nazwa komputera [$1]: ", "Computer name [$1]: "),
  ("cli_hostname_invalid",
    "Nieprawidłowa nazwa komputera (litery, cyfry i -, bez - na początku/końcu).",
    "Invalid computer name (letters, digits and -, no leading/trailing -)."),
  ("cli_password_prompt", "Hasło: ", "Password: "),
  ("cli_password2_prompt", "Powtórz hasło: ", "Repeat password: "),
  ("cli_password_mismatch", "Hasła się różnią, spróbuj ponownie.", "Passwords do not match, try again."),
  ("cli_password_too_short", "Hasło musi mieć co najmniej $1 znaków.",
    "The password must be at least $1 characters long."),
  ("cli_root_password_ask",
    "Ustawić osobne hasło root? (Nie = zablokuj konto root, używaj sudo)",
    "Set a separate root password? (No = lock the root account, use sudo)"),
  ("cli_root_password_prompt", "Hasło root: ", "Root password: "),
  ("cli_autologin_ask", "Włączyć automatyczne logowanie?", "Enable automatic login?"),
  ("cli_summary_title", "Podsumowanie:", "Summary:"),
  ("cli_confirm_install", "Rozpocząć instalację?", "Start installation?"),
  ("cli_install_done",
    "Instalacja zakończona! Możesz teraz zrestartować komputer.",
    "Installation complete! You can now reboot."),
  ("cli_install_failed", "Instalacja nie powiodła się: $1", "Installation failed: $1"),
  ("cli_step_ok", "OK", "OK"),
  ("cli_step_error", "BŁĄD", "ERROR"),

  # -- --autoinstall ------------------------------------------------------------
  ("cli_autoinstall_banner", "$1 -- instalacja automatyczna (--autoinstall=$2)",
    "$1 -- unattended installation (--autoinstall=$2)"),
  ("cli_autoinstall_read_fail", "Nie można odczytać pliku odpowiedzi: $1",
    "Could not read the answer file: $1"),
  ("cli_autoinstall_disk_missing",
    "Dysk '$1' nie został znaleziony (disk=... w pliku odpowiedzi). Przerywam.",
    "Disk '$1' was not found (disk=... in the answer file). Aborting."),
  ("cli_autoinstall_manual_root_missing",
    "Tryb ręczny wymaga manual_root=... w pliku odpowiedzi. Przerywam.",
    "Manual mode requires manual_root=... in the answer file. Aborting."),
  ("cli_autoinstall_missing_creds",
    "Plik odpowiedzi musi zawierać przynajmniej username=... i password=.... Przerywam.",
    "The answer file must contain at least username=... and password=.... Aborting."),
  ("cli_autoinstall_bad_username",
    "Nieprawidłowa nazwa użytkownika w pliku odpowiedzi: $1",
    "Invalid username in the answer file: $1"),
  ("cli_autoinstall_bad_hostname",
    "Nieprawidłowa nazwa komputera w pliku odpowiedzi: $1",
    "Invalid computer name in the answer file: $1"),
  ("cli_autoinstall_starting",
    "Rozpoczynam instalację bez potwierdzenia (tryb autoinstall)...",
    "Starting installation without confirmation (autoinstall mode)..."),
  ("cli_autoinstall_perm_warn",
    "Ostrzeżenie: plik odpowiedzi jest czytelny dla innych użytkowników " &
    "systemu ($1) -- może zawierać hasła w czystym tekście. Rozważ `chmod 600`.",
    "Warning: the answer file is readable by other users on this system " &
    "($1) -- it may contain plaintext passwords. Consider `chmod 600`."),
  ("cli_autoinstall_duplicate",
    "Ta sama partycja jest przypisana do więcej niż jednej roli w pliku odpowiedzi. Przerywam.",
    "The same partition is assigned to more than one role in the answer file. Aborting."),
  ("cli_autoinstall_too_small",
    "Wybrany dysk lub partycja roota jest zbyt mała (minimum $1). Przerywam.",
    "The selected disk or root partition is too small (minimum $1). Aborting."),
  ("cli_autoinstall_wrong_disk",
    "Partycja '$1' (manual_$2=...) nie leży na dysku '$3' wskazanym przez disk=. Przerywam.",
    "Partition '$1' (manual_$2=...) is not on the disk '$3' given by disk=. Aborting."),
]

var plDict = initTable[string, string]()
var enDict = initTable[string, string]()
for e in entries:
  plDict[e[0]] = e[1]
  enDict[e[0]] = e[2]

# -- niemiecki/francuski/hiszpański: tylko najbardziej widoczne stringi ------
# (key, de, fr, es) -- patrz wyjaśnienie zakresu na górze pliku.
const extraTranslations = [
  ("nav_welcome", "Willkommen", "Bienvenue", "Bienvenida"),
  ("nav_language", "Sprache", "Langue", "Idioma"),
  ("nav_keyboard", "Tastatur", "Clavier", "Teclado"),
  ("nav_network", "Netzwerk", "Réseau", "Red"),
  ("nav_disk", "Laufwerk", "Disque", "Disco"),
  ("nav_partition", "Partitionierung", "Partitionnement", "Particionado"),
  ("nav_account", "Konto", "Compte", "Cuenta"),
  ("nav_summary", "Zusammenfassung", "Résumé", "Resumen"),

  ("btn_back", "Zurück", "Retour", "Atrás"),
  ("btn_next", "Weiter", "Suivant", "Siguiente"),
  ("btn_start", "Starten", "Démarrer", "Empezar"),
  ("btn_install", "Installieren", "Installer", "Instalar"),
  ("btn_reboot", "Neu starten", "Redémarrer", "Reiniciar"),
  ("btn_check_connection", "Verbindung prüfen", "Vérifier la connexion", "Comprobar conexión"),
  ("btn_back_to_summary", "Zurück zur Zusammenfassung", "Retour au résumé", "Volver al resumen"),

  ("w_title", "Willkommen beim $1-Installer", "Bienvenue dans l'installateur $1", "Bienvenido al instalador de $1"),
  ("w_body",
    "Dieser Assistent führt Sie durch die Installation von $1 auf diesem " &
    "Computer. Alle Pakete -- das Basissystem und optionale Software -- " &
    "werden über zpm installiert, niemals durch ein einzelnes curl-Skript.",
    "Cet assistant vous guidera dans l'installation de $1 sur cet " &
    "ordinateur. Tous les paquets -- système de base et logiciels " &
    "optionnels -- sont installés via zpm, jamais par un simple script curl.",
    "Este asistente le guiará por la instalación de $1 en este equipo. " &
    "Todos los paquetes -- el sistema base y el software opcional -- se " &
    "instalan mediante zpm, nunca con un simple script curl."),
  ("w_standalone_warning",
    "Der Installer läuft auf einem bereits installierten System " &
    "(Neuinstallations-/Rettungsmodus) -- ein Fortfahren überschreibt das gewählte Laufwerk.",
    "L'installateur fonctionne sur un système déjà installé (mode " &
    "réinstallation/dépannage) -- continuer écrasera le disque choisi.",
    "El instalador se está ejecutando en un sistema ya instalado (modo " &
    "reinstalación/rescate) -- continuar sobrescribirá el disco elegido."),

  ("l_title", "Systemsprache wählen", "Choisissez la langue du système", "Elija el idioma del sistema"),

  ("k_title", "Tastatur und Zeitzone", "Clavier et fuseau horaire", "Teclado y zona horaria"),
  ("k_kb_label", "Tastaturlayout", "Disposition du clavier", "Distribución del teclado"),
  ("k_tz_label", "Zeitzone", "Fuseau horaire", "Zona horaria"),

  ("n_title", "Netzwerkverbindung", "Connexion réseau", "Conexión de red"),
  ("n_body",
    "Der Installer verwendet zpm, um Pakete herunterzuladen -- stellen Sie " &
    "sicher, dass eine Internetverbindung (WLAN/Ethernet) über " &
    "NetworkManager in dieser Live-Sitzung eingerichtet ist.",
    "L'installateur utilise zpm pour récupérer les paquets -- assurez-vous " &
    "d'avoir une connexion internet (Wi-Fi/Ethernet) configurée via " &
    "NetworkManager dans cette session live.",
    "El instalador usa zpm para descargar paquetes -- asegúrese de tener " &
    "una conexión a internet (Wi-Fi/Ethernet) configurada mediante " &
    "NetworkManager en esta sesión live."),
  ("n_result_ok", "Verbindung funktioniert.", "La connexion fonctionne.", "La conexión funciona."),
  ("n_result_fail",
    "Keine Verbindung -- die Paketinstallation über zpm könnte fehlschlagen.",
    "Pas de connexion -- l'installation des paquets via zpm pourrait échouer.",
    "Sin conexión -- la instalación de paquetes vía zpm podría fallar."),
  ("n_continue_anyway", "Ohne bestätigte Verbindung fortfahren?",
    "Continuer sans connexion confirmée ?", "¿Continuar sin conexión confirmada?"),

  ("d_title", "Zieldatenträger wählen", "Choisissez le disque cible", "Elija el disco de destino"),
  ("d_empty", "Keine Laufwerke gefunden (lsblk fehlt oder kein Medium vorhanden).",
    "Aucun disque détecté (lsblk indisponible ou aucun support présent).",
    "No se detectaron discos (lsblk no disponible o sin soporte presente)."),
  ("d_dualboot",
    "Andere Betriebssysteme erkannt -- werden zum GRUB-Menü hinzugefügt: $1",
    "D'autres systèmes d'exploitation détectés -- ils seront ajoutés au menu GRUB : $1",
    "Se detectaron otros sistemas operativos -- se añadirán al menú de GRUB: $1"),
  ("d_too_small", "Das gewählte Laufwerk ist zu klein (Minimum $1).",
    "Le disque choisi est trop petit (minimum $1).", "El disco elegido es demasiado pequeño (mínimo $1)."),
  ("d_live_warning",
    "WARNUNG: Dies scheint das Medium zu sein, von dem diese Live-Sitzung " &
    "läuft. Es als Installationsziel zu wählen wird die aktuelle Sitzung " &
    "vermutlich beschädigen.",
    "ATTENTION : ceci ressemble au support depuis lequel cette session " &
    "live fonctionne. Le choisir comme cible d'installation cassera " &
    "probablement la session en cours.",
    "ADVERTENCIA: esto parece ser el medio desde el que se ejecuta esta " &
    "sesión live. Elegirlo como destino probablemente romperá la sesión actual."),
  ("d_live_confirm", "Ich verstehe das Risiko, das ist das richtige Laufwerk",
    "Je comprends le risque, c'est le bon disque", "Entiendo el riesgo, este es el disco correcto"),
  ("tag_removable", " [Wechseldatenträger]", " [amovible]", " [extraíble]"),
  ("tag_live", " [LIVE-MEDIUM]", " [SUPPORT LIVE]", " [MEDIO LIVE]"),

  ("p_title", "Partitionierung", "Partitionnement", "Particionado"),
  ("p_disk", "Laufwerk: $1", "Disque : $1", "Disco: $1"),
  ("p_mode_label", "Partitionierungsmodus", "Mode de partitionnement", "Modo de particionado"),
  ("p_mode_erase", "Gesamtes Laufwerk löschen", "Effacer tout le disque", "Borrar todo el disco"),
  ("p_mode_manual", "Manuell (vorhandene Partitionen)", "Manuel (partitions existantes)", "Manual (particiones existentes)"),
  ("p_mode_freespace", "freier Speicherplatz", "espace libre", "espacio libre"),
  ("p_boot_label", "Boot-Modus", "Mode de démarrage", "Modo de arranque"),
  ("p_boot_uefi", "UEFI", "UEFI", "UEFI"),
  ("p_boot_bios", "BIOS / Legacy", "BIOS / Legacy", "BIOS / Legacy"),
  ("p_warn", "WARNUNG: das gesamte Laufwerk $1 wird GELÖSCHT und formatiert.",
    "ATTENTION : le disque entier $1 sera EFFACÉ et formaté.",
    "ADVERTENCIA: el disco completo $1 será BORRADO y formateado."),
  ("p_confirm", "Verstanden, gesamtes Laufwerk löschen", "J'ai compris, effacer tout le disque", "Entendido, borrar todo el disco"),
  ("p_fs_label", "Dateisystem", "Système de fichiers", "Sistema de archivos"),
  ("p_swap_label", "Auslagerungsspeicher (Swap)", "Espace d'échange (swap)", "Memoria de intercambio (swap)"),
  ("p_swap_none", "Keiner", "Aucun", "Ninguno"),
  ("p_swap_partition", "Partition", "Partition", "Partición"),
  ("p_swap_file", "Datei (im Root)", "Fichier (dans root)", "Archivo (dentro de root)"),
  ("p_manual_info",
    "Auf dem nächsten Bildschirm weisen Sie vorhandenen Partitionen Rollen " &
    "zu (root, ESP oder bios_grub, optional home und swap). Der Installer " &
    "erstellt oder verändert sie nicht.",
    "Sur l'écran suivant, vous attribuerez des rôles à des partitions " &
    "existantes (root, ESP ou bios_grub, éventuellement home et swap). " &
    "L'installateur ne les crée ni ne les redimensionne jamais.",
    "En la siguiente pantalla asignará roles a particiones existentes " &
    "(root, ESP o bios_grub, opcionalmente home y swap). El instalador " &
    "nunca las crea ni las redimensiona."),
  ("p_encrypt", "Root-Partition verschlüsseln (LUKS)", "Chiffrer la partition root (LUKS)", "Cifrar la partición raíz (LUKS)"),
  ("p_luks_warn",
    "Notieren Sie sich diese Passphrase an einem sicheren Ort -- ohne sie " &
    "ist das Laufwerk UNWIEDERBRINGLICH verloren.",
    "Notez cette phrase secrète en lieu sûr -- sans elle, le disque est " &
    "IRRÉCUPÉRABLE.",
    "Anote esta frase de contraseña en un lugar seguro -- sin ella, el " &
    "disco es IRRECUPERABLE."),
  ("p_luks_pass", "Verschlüsselungs-Passphrase", "Phrase de chiffrement", "Frase de cifrado"),
  ("p_luks_pass2", "Passphrase wiederholen", "Répéter la phrase de chiffrement", "Repita la frase de cifrado"),
  ("p_luks_mismatch", "Die Passphrasen stimmen nicht überein.", "Les phrases de chiffrement ne correspondent pas.",
    "Las frases de cifrado no coinciden."),

  ("mp_title", "Vorhandene Partitionen zuweisen", "Assigner des partitions existantes", "Asignar particiones existentes"),
  ("mp_empty", "Keine Partitionen auf diesem Laufwerk gefunden.",
    "Aucune partition détectée sur ce disque.", "No se detectaron particiones en este disco."),
  ("mp_esp", "ESP-Partition (FAT32, unter /boot/efi eingehängt)",
    "Partition ESP (FAT32, montée sur /boot/efi)", "Partición ESP (FAT32, montada en /boot/efi)"),
  ("mp_bg", "bios_grub-Partition (roh, nie formatiert)",
    "Partition bios_grub (brute, jamais formatée)", "Partición bios_grub (sin formatear nunca)"),
  ("mp_root", "Root-Partition (wird formatiert)", "Partition root (sera formatée)", "Partición raíz (se formateará)"),
  ("mp_home", "/home-Partition (optional)", "Partition /home (facultatif)", "Partición /home (opcional)"),
  ("mp_swap", "Swap-Partition (optional)", "Partition swap (facultatif)", "Partición swap (opcional)"),
  ("mp_none", "(keine)", "(aucune)", "(ninguna)"),
  ("mp_swapfile", "Stattdessen eine Swap-Datei im Root verwenden",
    "Utiliser un fichier swap dans root à la place", "Usar un archivo swap dentro de root en su lugar"),
  ("mp_duplicate", "Dieselbe Partition ist mehreren Rollen zugewiesen -- korrigieren Sie die Auswahl.",
    "La même partition est assignée à plusieurs rôles -- corrigez la sélection.",
    "La misma partición está asignada a más de un rol -- corrija la selección."),
  ("mp_too_small", "Die Root-Partition ist zu klein (Minimum $1).",
    "La partition root est trop petite (minimum $1).", "La partición raíz es demasiado pequeña (mínimo $1)."),

  ("a_title", "Benutzerkonto erstellen", "Créer un compte utilisateur", "Crear una cuenta de usuario"),
  ("a_fullname", "Vollständiger Name", "Nom complet", "Nombre completo"),
  ("a_username", "Benutzername", "Nom d'utilisateur", "Nombre de usuario"),
  ("a_username_hint",
    "Kleinbuchstaben, Ziffern, _ und -, beginnend mit einem Buchstaben oder _",
    "minuscules, chiffres, _ et -, commençant par une lettre ou _",
    "minúsculas, dígitos, _ y -, empezando por una letra o _"),
  ("a_hostname", "Rechnername", "Nom de l'ordinateur", "Nombre del equipo"),
  ("a_hostname_hint", "Buchstaben, Ziffern und -, kein - am Anfang/Ende",
    "lettres, chiffres et -, sans - au début/à la fin", "letras, dígitos y -, sin - al inicio/final"),
  ("a_password", "Passwort", "Mot de passe", "Contraseña"),
  ("a_password2", "Passwort wiederholen", "Répéter le mot de passe", "Repita la contraseña"),
  ("a_password_mismatch", "Die Passwörter stimmen nicht überein.", "Les mots de passe ne correspondent pas.",
    "Las contraseñas no coinciden."),
  ("a_autologin", "Automatische Anmeldung", "Connexion automatique", "Inicio de sesión automático"),
  ("a_pkg_label", "Zusätzliche Software (installiert über zpm):",
    "Logiciels supplémentaires (installés via zpm) :", "Software adicional (instalado mediante zpm):"),

  ("s_title", "Zusammenfassung", "Résumé", "Resumen"),
  ("s_disk", "Laufwerk: $1 ($2), Modus: $3, Dateisystem: $4, Boot: $5",
    "Disque : $1 ($2), mode : $3, système de fichiers : $4, démarrage : $5",
    "Disco: $1 ($2), modo: $3, sistema de archivos: $4, arranque: $5"),
  ("s_security", "LUKS-Verschlüsselung: $1, Swap: $2", "Chiffrement LUKS : $1, swap : $2",
    "Cifrado LUKS: $1, swap: $2"),
  ("s_user", "Benutzer: $1 ($2), Rechner: $3", "Utilisateur : $1 ($2), hôte : $3", "Usuario: $1 ($2), host: $3"),
  ("s_locale", "Sprache: $1, Tastatur: $2, Zeitzone: $3", "Langue : $1, clavier : $2, fuseau horaire : $3",
    "Idioma: $1, teclado: $2, zona horaria: $3"),
  ("s_dualboot",
    "Von os-prober erkannte andere Systeme (werden zum GRUB-Menü hinzugefügt): $1",
    "Autres systèmes détectés par os-prober (ajoutés au menu GRUB) : $1",
    "Otros sistemas detectados por os-prober (se añadirán al menú de GRUB): $1"),
  ("s_pkgs",
    "Basissystem-Pakete und ausgewählte Extras werden ausschließlich über " &
    "zpm installiert -- kein curl.",
    "Les paquets du système de base et les extras sélectionnés sont " &
    "installés uniquement via zpm -- zéro curl.",
    "Los paquetes del sistema base y los extras seleccionados se instalan " &
    "únicamente mediante zpm -- cero curl."),
  ("val_on", "aktiviert", "activé", "activado"),
  ("val_off", "deaktiviert", "désactivé", "desactivado"),
  ("val_none", "keiner", "aucun", "ninguno"),
  ("val_swap_new_partition", "neue Partition", "nouvelle partition", "partición nueva"),
  ("val_swap_existing", "vorhandene Partition", "partition existante", "partición existente"),
  ("val_swap_file", "Swap-Datei", "fichier swap", "archivo swap"),

  ("i_title", "$1 wird installiert...", "Installation de $1...", "Instalando $1..."),
  ("done_title", "Installation abgeschlossen!", "Installation terminée !", "¡Instalación completa!"),
  ("done_body", "Sie können den Computer jetzt neu starten und $1 von der Festplatte starten.",
    "Vous pouvez maintenant redémarrer et lancer $1 depuis le disque.",
    "Ahora puede reiniciar e iniciar $1 desde el disco."),
  ("err_title", "Installation fehlgeschlagen", "L'installation a échoué", "La instalación ha fallado"),
]

var deDict = initTable[string, string]()
var frDict = initTable[string, string]()
var esDict = initTable[string, string]()
for e in extraTranslations:
  deDict[e[0]] = e[1]
  frDict[e[0]] = e[2]
  esDict[e[0]] = e[3]

proc t*(key: string, args: varargs[string]): string {.gcsafe.} =
  ## Tłumaczy `key` na aktualny `currentLang`. Dla de/fr/es brakujący klucz
  ## spada na angielski (a nie na sam klucz) -- patrz wyjaśnienie zakresu
  ## tłumaczeń na górze pliku. `args` podstawiane są pod $1/$2/... (patrz
  ## std/strutils `%`).
  ##
  ## `{.cast(gcsafe).}` niżej: plDict/enDict/deDict/frDict/esDict/currentLang
  ## są globalnymi `var` (GC'owana pamięć), więc domyślny analizator
  ## gcsafe Nima nie potrafi udowodnić, że dostęp do nich jest bezpieczny --
  ## a musi to udowodnić, bo `t` jest wołane m.in. z `onProgress` w
  ## cliapp.nim, które z kolei musi być `{.gcsafe.}`, żeby pasować do typu
  ## `ProgressCallback` (patrz types.nim). W praktyce JEST to bezpieczne:
  ## wszystkie te słowniki są wypełniane raz, przy starcie modułu (patrz
  ## pętle `for e in entries/extraTranslations` wyżej), i tylko odczytywane
  ## później -- nigdy nie mutowane w trakcie działania poza `currentLang`
  ## (który zmienia jedynie `setUiLanguage`, wołane z głównego wątku, nigdy
  ## z wątku instalacyjnego z executor.nim). `cast(gcsafe)` to jawne
  ## zapewnienie kompilatora o tym, a nie obejście/ukrycie prawdziwego
  ## problemu wielowątkowości.
  let raw = block:
    var r: string
    {.cast(gcsafe).}:
      r = case currentLang
          of langPl: plDict.getOrDefault(key, key)
          of langEn: enDict.getOrDefault(key, key)
          of langDe: deDict.getOrDefault(key, enDict.getOrDefault(key, key))
          of langFr: frDict.getOrDefault(key, enDict.getOrDefault(key, key))
          of langEs: esDict.getOrDefault(key, enDict.getOrDefault(key, key))
    r
  if args.len == 0: raw else: raw % @args

proc setUiLanguage*(languageTag: string) {.gcsafe.} =
  ## `languageTag` to kod locale wybrany dla INSTALOWANEGO systemu (np.
  ## "pl_PL.UTF-8") -- interfejs instalatora przełącza się na odpowiedni
  ## język dla pl/en/de/fr/es, w każdym innym przypadku na angielski.
  ## `{.cast(gcsafe).}` -- patrz wyjaśnienie w komentarzu `t()` wyżej;
  ## dotyczy tu tylko przypisania do `currentLang`.
  {.cast(gcsafe).}:
    currentLang =
      case languageTag
      of "pl_PL.UTF-8": langPl
      of "de_DE.UTF-8": langDe
      of "fr_FR.UTF-8": langFr
      of "es_ES.UTF-8": langEs
      else: langEn
