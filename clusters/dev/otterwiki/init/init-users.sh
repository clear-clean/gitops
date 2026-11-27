#!/bin/sh
# Legt die Benutzer an, die es von Anfang an geben soll (Init-Container, vor
# dem Wiki). Ersetzt die Selbstregistrierung, bei der sonst der erste
# Anmelder Administrator wuerde.
#
# Nur was fehlt, wird angelegt. Bestehende Benutzer, ihre Passwoerter und
# Rechte werden nie veraendert; das geschieht danach im Wiki.
#
# Erwartet: ADMIN_EMAIL, ADMIN_PASSWORD, AGENT_EMAIL, AGENT_PASSWORD
# (aus dem Secret otterwiki-users).
set -eu
cd /app

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

ensure_user "$ADMIN_EMAIL" "Admin"       "read,write,upload,admin" "$ADMIN_PASSWORD"
ensure_user "$AGENT_EMAIL" "Agent Smith" "read,write,upload"       "$AGENT_PASSWORD"
