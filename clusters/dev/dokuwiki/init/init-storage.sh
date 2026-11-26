#!/bin/bash
# Bereitet das Volume vor, bevor das Wiki startet (Init-Container):
#
#   1. conf/ anlegen
#   2. Ersteinrichtung, falls das Wiki noch nicht eingerichtet ist
#      (ersetzt den Web-Installer install.php)
#   3. lib/plugins mit plugins.txt abgleichen
set -euo pipefail

GITOPS="${GITOPS_DIR:-/gitops}"
LIST="${PLUGIN_LIST:-$GITOPS/plugins.txt}"
DEST="${PLUGIN_DIR:-/storage/lib/plugins}"
CONF="${CONF_DIR:-/storage/conf}"
ADMIN_SECRET="${ADMIN_SECRET_DIR:-/admin}"
ADMIN_USER="${ADMIN_USER:-admin}"
ADMIN_NAME="${ADMIN_NAME:-Admin}"
MARKER=".gitops-sha256"

# --- 1. conf/ ---------------------------------------------------------------

# conf/ muss existieren und dem Wiki-Benutzer gehoeren, BEVOR Kubernetes die
# Dateien aus der ConfigMap dort einhaengt. Sonst legt Kubernetes das
# Verzeichnis als root an und das Wiki kann nicht hineinschreiben.
mkdir -p "$CONF"

# --- 2. Ersteinrichtung -----------------------------------------------------
# Nur was fehlt, wird angelegt. Benutzer und Rechte aendern sich spaeter im
# Wiki und werden hier nie ueberschrieben.

if [[ ! -e "$CONF/acl.auth.php" ]]; then
  echo "setup     acl.auth.php (Anfangsrechte: geschlossenes Wiki)"
  cp "$GITOPS/acl.auth.php" "$CONF/acl.auth.php"
fi

if [[ ! -e "$CONF/users.auth.php" ]]; then
  if [[ ! -r "$ADMIN_SECRET/password-hash" ]]; then
    echo "FEHLER: Secret dokuwiki-admin (Schluessel password-hash) fehlt" >&2
    exit 1
  fi
  hash="$(tr -d '[:space:]' < "$ADMIN_SECRET/password-hash")"
  if [[ ! "$hash" =~ ^\$2[aby]\$[0-9]{2}\$[./A-Za-z0-9]{53}$ ]]; then
    echo "FEHLER: password-hash im Secret dokuwiki-admin ist kein bcrypt-Hash" >&2
    exit 1
  fi
  email=""
  [[ -r "$ADMIN_SECRET/email" ]] && email="$(tr -d '[:space:]' < "$ADMIN_SECRET/email")"
  if [[ "$email" == *:* ]]; then
    echo "FEHLER: email im Secret dokuwiki-admin enthaelt einen Doppelpunkt" >&2
    exit 1
  fi
  echo "setup     users.auth.php (Benutzer $ADMIN_USER, Gruppen admin,user)"
  umask 077
  { cat "$GITOPS/users.auth.php.head"
    printf '%s:%s:%s:%s:%s\n' "$ADMIN_USER" "$hash" "$ADMIN_NAME" "$email" "admin,user"
  } > "$CONF/users.auth.php.tmp"
  mv "$CONF/users.auth.php.tmp" "$CONF/users.auth.php"
  umask 022
fi

# install.php verweigert den Dienst, sobald local.php existiert. Die Datei
# gehoert danach dem Wiki (Konfigurationsmanager).
if [[ ! -e "$CONF/local.php" ]]; then
  echo "setup     local.php"
  printf '<?php\n// Angelegt bei der Ersteinrichtung. Einstellungen aus der Admin-Oberflaeche landen hier.\n' > "$CONF/local.php"
fi

# --- 3. Plugins -------------------------------------------------------------
# Bereits installierte Staende (gleiche Pruefsumme) werden nicht erneut
# geladen, ein normaler Neustart braucht also keinen Internetzugang.

mkdir -p "$DEST"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

declare -A wanted=()

while read -r name url sha _; do
  [[ -z "${name:-}" || "$name" == \#* ]] && continue
  if [[ ! "$name" =~ ^[a-z0-9_]+$ || -z "${url:-}" || ! "${sha:-}" =~ ^[0-9a-f]{64}$ ]]; then
    echo "FEHLER: ungueltige Zeile in $LIST: $name" >&2
    exit 1
  fi
  wanted[$name]=1

  if [[ -f "$DEST/$name/$MARKER" && "$(cat "$DEST/$name/$MARKER")" == "$sha" ]]; then
    echo "ok        $name (bereits installiert)"
    continue
  fi

  echo "install   $name <- $url"
  curl -fsSL --retry 3 --max-time 120 -o "$tmp/$name.tar.gz" "$url"
  echo "$sha  $tmp/$name.tar.gz" | sha256sum -c - >/dev/null
  mkdir "$tmp/$name"
  tar -xzf "$tmp/$name.tar.gz" -C "$tmp/$name" --strip-components=1
  echo "$sha" > "$tmp/$name/$MARKER"
  rm -rf "${DEST:?}/$name"
  cp -r "$tmp/$name" "$DEST/$name"
done < "$LIST"

# Alles entfernen, was nicht in der Liste steht. Symlinks sind die mit dem
# Image gelieferten Plugins und bleiben unangetastet.
for dir in "$DEST"/*; do
  [[ -L "$dir" || ! -d "$dir" ]] && continue
  name="$(basename "$dir")"
  if [[ -z "${wanted[$name]:-}" ]]; then
    echo "entferne  $name (nicht in $LIST)"
    rm -rf "$dir"
  fi
done
