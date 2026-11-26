#!/bin/bash
# Gleicht lib/plugins im Volume mit plugins.txt ab. Laeuft als Init-Container
# vor dem Wiki. Bereits installierte Staende (gleiche Pruefsumme) werden nicht
# erneut geladen, ein normaler Neustart braucht also keinen Internetzugang.
set -euo pipefail

LIST="${PLUGIN_LIST:-/gitops/plugins.txt}"
DEST="${PLUGIN_DIR:-/storage/lib/plugins}"
MARKER=".gitops-sha256"

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
