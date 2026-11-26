<?php
/**
 * Aus dem gitops-Repo (clusters/dev/dokuwiki/config), per ConfigMap eingehaengt.
 * Diese Werte ueberstimmen die Admin-Oberflaeche und sind dort gesperrt.
 * Alles, was hier nicht steht, bleibt im Wiki aenderbar (conf/local.php im Volume).
 */
$conf['title']   = 'ClearClean Wiki (dev)';
$conf['lang']    = 'de';
$conf['baseurl'] = 'https://dokuwiki.dev.cloud.clearclean.local';

// Zugriffskontrolle immer an, Mitglieder der Gruppe "admin" sind Administratoren
$conf['useacl']    = 1;
$conf['superuser'] = '@admin';

// Konten legt nur ein Administrator an, keine Selbstregistrierung
$conf['disableactions'] = 'register';

// internes Wiki: keine Inhaltslizenz anzeigen
$conf['license'] = '';

// Remote-API fuer das MCP-Plugin: nur Mitglieder der Gruppe "mcp"
$conf['remote']     = 1;
$conf['remoteuser'] = '@mcp';
