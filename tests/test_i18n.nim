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

  test "german/french/spanish fall back to english for keys outside their subset":
    currentLang = langDe
    # "cli_autoinstall_starting" is a --autoinstall-only string, deliberately
    # not in the de/fr/es subset (see i18n.nim comment) -- must fall back to
    # English rather than returning the raw key.
    check t("cli_autoinstall_starting") == "Starting installation without confirmation (autoinstall mode)..."
    currentLang = langFr
    check t("cli_autoinstall_starting") == "Starting installation without confirmation (autoinstall mode)..."
    currentLang = langEs
    check t("cli_autoinstall_starting") == "Starting installation without confirmation (autoinstall mode)..."

  test "german/french/spanish do cover the high-visibility subset":
    currentLang = langDe
    check t("btn_next") == "Weiter"
    currentLang = langFr
    check t("btn_next") == "Suivant"
    currentLang = langEs
    check t("btn_next") == "Siguiente"

  test "setUiLanguage maps locale tags to the right language":
    setUiLanguage("pl_PL.UTF-8")
    check currentLang == langPl
    setUiLanguage("de_DE.UTF-8")
    check currentLang == langDe
    setUiLanguage("fr_FR.UTF-8")
    check currentLang == langFr
    setUiLanguage("es_ES.UTF-8")
    check currentLang == langEs
    setUiLanguage("something-unknown")
    check currentLang == langEn
