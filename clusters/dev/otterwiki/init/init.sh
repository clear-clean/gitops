#!/bin/sh
# Bereitet das Volume vor, bevor das Wiki startet (Init-Container). Der
# Entrypoint des Images hat zu diesem Zeitpunkt Repository und settings.cfg
# bereits angelegt.
#
#   1. Git-Einstellungen fuer den Abgleich mit Gitea
#   2. Administrator anlegen, falls er fehlt
set -eu
cd /app

# --- 1. Abgleich mit Gitea ---------------------------------------------------
# Das Wiki holt nach einem Merge in Gitea per "git pull" ab. Hat inzwischen
# jemand im Wiki geaendert, laufen beide Staende auseinander; ohne diese
# Einstellung bricht git pull dann ab. So werden sie zusammengefuehrt, solange
# nicht dieselbe Stelle betroffen ist.
git -C "${OTTERWIKI_REPOSITORY:-/app-data/repository}" config pull.rebase false

# --- 2. Administrator ---------------------------------------------------------
# Ersetzt die Selbstregistrierung, bei der sonst der erste Anmelder
# Administrator wuerde. Nur was fehlt, wird angelegt; bestehende Benutzer,
# ihre Passwoerter und Rechte werden nie veraendert.
#
# Agenten bekommen keinen Benutzer im Wiki: sie arbeiten ueber das
# Repository wiki/otterwiki in Gitea (siehe clusters/dev/gitea/bootstrap).
#
# Erwartet: ADMIN_EMAIL, ADMIN_PASSWORD (aus dem Secret otterwiki-users).

ensure_user() {
  email="$1"; name="$2"; permissions="$3"; password="$4"

  if out="$(flask user create "$email" "$name" \
              --flags=email_confirmed,approved \
              --permissions="$permissions" 2>&1)"; then
    # Neu angelegt: Passwort setzen. Die Eingabeaufforderung liest zweimal.
    if printf '%s\n%s\n' "$password" "$password" \
         | flask user password "$email" --interactive >/dev/null 2>&1; then
      echo "angelegt  $name ($permissions)"
    else
      # Ohne Passwort waere der Benutzer unbrauchbar und wuerde beim
      # naechsten Start uebersprungen: wieder entfernen und abbrechen.
      flask user delete "$email" --confirm >/dev/null 2>&1 || true
      echo "FEHLER: Passwort fuer $name konnte nicht gesetzt werden" >&2
      exit 1
    fi
  elif printf '%s' "$out" | grep -q 'already exists'; then
    echo "ok        $name (bereits vorhanden)"
  else
    echo "FEHLER: $name konnte nicht angelegt werden:" >&2
    printf '%s\n' "$out" | grep -v 'Starting An Otter Wiki' >&2
    exit 1
  fi
}

ensure_user "$ADMIN_EMAIL" "Admin" "read,write,upload,admin" "$ADMIN_PASSWORD"
