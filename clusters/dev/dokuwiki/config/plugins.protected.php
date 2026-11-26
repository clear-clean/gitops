<?php
/**
 * Aus dem gitops-Repo, per ConfigMap eingehaengt.
 * Plugins werden ausschliesslich ueber init/plugins.txt installiert.
 */

// Erweiterungsmanager aus: keine Installation ueber die Admin-Oberflaeche
$plugins['extension'] = 0;

// per Init-Container installierte Plugins
$plugins['mcp'] = 1;
