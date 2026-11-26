# acl.auth.php
# <?php exit()?>
# Don't modify the lines above
#
# Access Control Lists
#
# Anfangsstand aus dem gitops-Repo (clusters/dev/dokuwiki/init), wird nur
# kopiert, solange die Datei im Volume fehlt. Danach gilt, was im Wiki
# eingestellt wird.
#
# Geschlossenes Wiki: nur angemeldete Benutzer duerfen lesen, schreiben, hochladen.
*               @ALL          0
*               @user         8
