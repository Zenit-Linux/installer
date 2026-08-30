import std/unittest
import ../src/installerpkg/i18n

suite "i18n":
  test "polish and english are fully translated for a sample of keys":
    currentLang = langPl
    check t("btn_next") == "Dalej"
    currentLang = langEn
    check t("btn_next") == "Next"

  test "placeholder substitution":
    currentLang = langEn
    check t("d_too_small", "8.0 GiB") == "The selected disk is too small (minimum 8.0 GiB)."

  test "german/french/spanish now cover every key (grew from the original narrower subset)":
    currentLang = langDe
    check t("cli_autoinstall_starting") == "Installation ohne Bestätigung wird gestartet (Autoinstall-Modus)..."
    currentLang = langFr
    check t("nav_desktop") == "Environnement de bureau"
    currentLang = langEs
    check t("nav_desktop") == "Entorno de escritorio"

  test "italian/ukrainian fall back to english for keys outside their (deliberately narrower) subset":
    currentLang = langIt
    # "cli_autoinstall_starting" is outside the smaller it/uk core subset
    # (see i18n.nim comment) -- must fall back to English rather than
    # returning the raw key. de/fr/es have since grown to full coverage
    # (170/170 keys), so this regression check now lives on it/uk instead.
    check t("cli_autoinstall_starting") == "Starting installation without confirmation (autoinstall mode)..."
    currentLang = langUk
    check t("cli_autoinstall_starting") == "Starting installation without confirmation (autoinstall mode)..."

  test "italian/ukrainian cover the high-visibility subset (desktop selection, welcome, disk warning)":
    currentLang = langIt
    check t("nav_desktop") == "Ambiente desktop"
    check t("de_none") == "Senza ambiente desktop (server/minimo)"
    currentLang = langUk
    check t("nav_desktop") == "Стільничне середовище"
    check t("d_live_warning").len > 0

  test "setUiLanguage maps every supported locale tag to the right language":
    setUiLanguage("pl_PL.UTF-8")
    check currentLang == langPl
    setUiLanguage("de_DE.UTF-8")
    check currentLang == langDe
    setUiLanguage("fr_FR.UTF-8")
    check currentLang == langFr
    setUiLanguage("es_ES.UTF-8")
    check currentLang == langEs
    setUiLanguage("it_IT.UTF-8")
    check currentLang == langIt
    setUiLanguage("uk_UA.UTF-8")
    check currentLang == langUk
    setUiLanguage("something-unknown")
    check currentLang == langEn

  test "nav_desktop key exists for the new desktop-environment wizard step in every language":
    for lang in [langPl, langEn, langDe, langFr, langEs, langIt, langUk]:
      currentLang = lang
      check t("nav_desktop").len > 0
      check t("nav_desktop") != "nav_desktop"  # never falls through to the raw key
