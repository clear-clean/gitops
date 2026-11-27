#!/usr/bin/env python3
"""Legt in Gitea an, was sich nicht per Helm-Chart beschreiben laesst.

Laeuft als Kubernetes-Job nach jedem Ausrollen dieses Skripts und ist
idempotent: vorhandene Objekte bleiben, fehlende werden angelegt, abweichende
Einstellungen der unten genannten Objekte werden angeglichen.

Angelegt wird fuer die Anbindung des Otter Wikis:
  - Organisation und (leeres, privates) Repository fuer das Wiki
  - Deploy-Key des Wikis mit Schreibrecht
  - Benutzer fuer Agenten, mit Schreibrecht auf das Repository
  - Schutz von main: direkt pushen darf nur der Deploy-Key, mergen nur der Admin
  - Webhook, der das Wiki nach einem Push auf main zum Abholen anstoesst

Tokens werden bewusst NICHT erzeugt: ein Token legt an, wer einen Agenten
einrichtet (Gitea: Einstellungen -> Anwendungen).

Nur Standardbibliothek, damit das Image ohne Nachinstallieren auskommt.
"""
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request

BASE = os.environ.get("GITEA_URL", "http://gitea-http.gitea.svc.cluster.local:3000")
ADMIN_USER = os.environ["ADMIN_USERNAME"]
ADMIN_PASSWORD = os.environ["ADMIN_PASSWORD"]

ORG = os.environ.get("WIKI_ORG", "wiki")
REPO = os.environ.get("WIKI_REPO", "otterwiki")
BRANCH = "main"
DEPLOY_KEY_TITLE = "otterwiki"
DEPLOY_KEY = open(os.environ.get("DEPLOY_KEY_FILE", "/bootstrap/wiki-deploy-key.pub")).read().strip()

AGENT_USER = os.environ.get("AGENT_USERNAME", "agentsmith")
AGENT_EMAIL = os.environ["AGENT_EMAIL"]
AGENT_PASSWORD = os.environ["AGENT_PASSWORD"]

WEBHOOK_URL = os.environ["WEBHOOK_URL"]

_AUTH = "Basic " + base64.b64encode(f"{ADMIN_USER}:{ADMIN_PASSWORD}".encode()).decode()


def api(method, path, body=None):
    """Ruft die Gitea-API auf. Gibt (Status, JSON oder None) zurueck."""
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(f"{BASE}/api/v1{path}", data=data, method=method)
    req.add_header("Authorization", _AUTH)
    req.add_header("Accept", "application/json")
    if data is not None:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            raw = resp.read()
            return resp.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as err:
        raw = err.read()
        try:
            return err.code, json.loads(raw)
        except ValueError:
            return err.code, None


def must(status, payload, what, ok=(200, 201, 204)):
    if status not in ok:
        # Antworten der API enthalten keine Geheimnisse, die Meldung hilft beim Debuggen.
        message = payload.get("message") if isinstance(payload, dict) else payload
        sys.exit(f"FEHLER: {what}: HTTP {status}: {message}")


def wait_for_gitea(timeout=600):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(f"{BASE}/api/healthz", timeout=5) as resp:
                if resp.status == 200:
                    return
        except (urllib.error.URLError, OSError):
            pass
        time.sleep(5)
    sys.exit("FEHLER: Gitea ist nicht erreichbar")


def ensure_org():
    status, _ = api("GET", f"/orgs/{ORG}")
    if status == 200:
        print(f"ok        Organisation {ORG}")
        return
    status, payload = api("POST", "/orgs", {
        "username": ORG,
        "full_name": "Wiki",
        "description": "Inhalte der Wikis",
        "visibility": "private",
    })
    must(status, payload, "Organisation anlegen")
    print(f"angelegt  Organisation {ORG}")


def ensure_repo():
    status, _ = api("GET", f"/repos/{ORG}/{REPO}")
    if status == 200:
        print(f"ok        Repository {ORG}/{REPO}")
        return
    # Leer anlegen (kein auto_init): den ersten Stand liefert das Wiki per Push.
    status, payload = api("POST", f"/orgs/{ORG}/repos", {
        "name": REPO,
        "description": "Seiten des Otter Wikis. Wird vom Wiki abgeglichen.",
        "private": True,
        "auto_init": False,
        "default_branch": BRANCH,
    })
    must(status, payload, "Repository anlegen")
    print(f"angelegt  Repository {ORG}/{REPO}")


def ensure_deploy_key():
    status, keys = api("GET", f"/repos/{ORG}/{REPO}/keys")
    must(status, keys, "Deploy-Keys lesen")
    wanted = " ".join(DEPLOY_KEY.split()[:2])
    for key in keys or []:
        if key.get("title") != DEPLOY_KEY_TITLE:
            continue
        same = " ".join(key.get("key", "").split()[:2]) == wanted
        if same and not key.get("read_only", True):
            print(f"ok        Deploy-Key {DEPLOY_KEY_TITLE}")
            return
        status, payload = api("DELETE", f"/repos/{ORG}/{REPO}/keys/{key['id']}")
        must(status, payload, "veralteten Deploy-Key entfernen")
    status, payload = api("POST", f"/repos/{ORG}/{REPO}/keys", {
        "title": DEPLOY_KEY_TITLE,
        "key": DEPLOY_KEY,
        "read_only": False,
    })
    must(status, payload, "Deploy-Key anlegen")
    print(f"angelegt  Deploy-Key {DEPLOY_KEY_TITLE} (Schreibrecht)")


def ensure_agent():
    status, _ = api("GET", f"/users/{AGENT_USER}")
    if status == 200:
        # Vorhandenen Benutzer nicht anfassen: Passwort und Tokens gehoeren ihm.
        print(f"ok        Benutzer {AGENT_USER}")
    else:
        status, payload = api("POST", "/admin/users", {
            "username": AGENT_USER,
            "full_name": "Agent Smith",
            "email": AGENT_EMAIL,
            "password": AGENT_PASSWORD,
            "must_change_password": False,
            "visibility": "private",
        })
        must(status, payload, "Benutzer fuer Agenten anlegen")
        print(f"angelegt  Benutzer {AGENT_USER}")
    # Schreibrecht: Branches pushen und Pull Requests stellen. main ist geschuetzt.
    status, payload = api("PUT", f"/repos/{ORG}/{REPO}/collaborators/{AGENT_USER}",
                          {"permission": "write"})
    must(status, payload, "Schreibrecht fuer Agenten setzen")
    print(f"ok        {AGENT_USER} hat Schreibrecht auf {ORG}/{REPO}")


def ensure_branch_protection():
    rule = {
        "rule_name": BRANCH,
        # Direkt auf main pushen darf nur der Deploy-Key des Wikis.
        "enable_push": True,
        "enable_push_whitelist": True,
        "push_whitelist_deploy_keys": True,
        "push_whitelist_usernames": [],
        "push_whitelist_teams": [],
        "enable_force_push": False,
        # Pull Requests mergen darf nur der Administrator, nicht der Agent.
        "enable_merge_whitelist": True,
        "merge_whitelist_usernames": [ADMIN_USER],
        "merge_whitelist_teams": [],
    }
    status, _ = api("GET", f"/repos/{ORG}/{REPO}/branch_protections/{BRANCH}")
    if status == 200:
        body = {k: v for k, v in rule.items() if k != "rule_name"}
        status, payload = api("PATCH", f"/repos/{ORG}/{REPO}/branch_protections/{BRANCH}", body)
        must(status, payload, "Branch-Schutz angleichen")
        print(f"ok        Branch-Schutz {BRANCH}")
        return
    status, payload = api("POST", f"/repos/{ORG}/{REPO}/branch_protections", rule)
    must(status, payload, "Branch-Schutz anlegen")
    print(f"angelegt  Branch-Schutz {BRANCH}")


def ensure_webhook():
    status, hooks = api("GET", f"/repos/{ORG}/{REPO}/hooks")
    must(status, hooks, "Webhooks lesen")
    body = {
        "type": "gitea",
        "active": True,
        "events": ["push"],
        "branch_filter": BRANCH,
        "config": {"url": WEBHOOK_URL, "content_type": "json", "http_method": "post"},
    }
    # Erkannt wird der Webhook am Host des Wikis; die Adresse selbst ist geheim.
    wiki_host = WEBHOOK_URL.split("/")[2]
    for hook in hooks or []:
        url = (hook.get("config") or {}).get("url", "")
        if len(url.split("/")) > 2 and url.split("/")[2] == wiki_host:
            patch = {k: v for k, v in body.items() if k != "type"}
            status, payload = api("PATCH", f"/repos/{ORG}/{REPO}/hooks/{hook['id']}", patch)
            must(status, payload, "Webhook angleichen")
            print("ok        Webhook zum Wiki")
            return
    status, payload = api("POST", f"/repos/{ORG}/{REPO}/hooks", body)
    must(status, payload, "Webhook anlegen")
    print("angelegt  Webhook zum Wiki")


def main():
    wait_for_gitea()
    ensure_org()
    ensure_repo()
    ensure_deploy_key()
    ensure_agent()
    ensure_branch_protection()
    ensure_webhook()
    print("fertig")


if __name__ == "__main__":
    main()
