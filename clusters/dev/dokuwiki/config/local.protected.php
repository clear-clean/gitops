<?php
/**
 * Aus dem gitops-Repo (clusters/dev/dokuwiki/config), per ConfigMap eingehaengt.
 * Diese Werte ueberstimmen die Admin-Oberflaeche und sind dort gesperrt.
 * Alles, was hier nicht steht, bleibt im Wiki aenderbar (conf/local.php im Volume).
 */
$conf['title']   = 'ClearClean Wiki (dev)';
$conf['lang']    = 'de';
$conf['baseurl'] = 'https://dokuwiki.dev.cloud.clearclean.local';

// Zugriffskontrolle immer an
$conf['useacl'] = 1;

// Remote-API fuer das MCP-Plugin: nur Mitglieder der Gruppe "mcp"
$conf['remote']     = 1;
$conf['remoteuser'] = '@mcp';
