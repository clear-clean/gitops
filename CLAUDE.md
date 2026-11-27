# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This is a GitOps repository managing Kubernetes cluster configuration using **Flux CD**. Flux runs inside each cluster and continuously reconciles the desired state declared here against the actual cluster state.

## Architecture

The repo follows the Flux multi-cluster convention, one directory per cluster:

```
clusters/
  prod/                 # existing cluster (192.168.1.89), Flux v2.7.5
    flux-system/        # Flux bootstrap manifests + one <app>-sync.yaml per app
    <app>/              # manifests / HelmRelease of one app
  dev/                  # dev cluster (192.168.1.92), Flux v2.10.1
    flux-system/
    <app>/
.sops.yaml              # SOPS encryption rules (age)
```

Per cluster, `flux-system/` contains:

- **`gotk-components.yaml`** — Auto-generated Flux component manifests (source-controller, kustomize-controller, helm-controller, notification-controller). Written by `flux bootstrap`.
- **`gotk-sync.yaml`** — Defines the `GitRepository` (SSH, 1m interval) and root `Kustomization` (10m interval) that tell Flux to watch this repo at path `./clusters/<cluster>`.
- **`<app>-sync.yaml`** — A Flux `Kustomization` pointing at `./clusters/<cluster>/<app>`.
- **`kustomization.yaml`** — Kustomize resource list tying the above together. New `*-sync.yaml` files must be listed here.

## Key Conventions

- Application manifests and Helm releases go under `clusters/<cluster>/<app>/`, wired in through a `<app>-sync.yaml` in that cluster's `flux-system/`.
- Both clusters were set up with `flux bootstrap github --personal --path=clusters/<cluster>`. The repo is synced via SSH (`ssh://git@github.com/clear-clean/gitops`); each cluster holds its own read-only deploy key in the secret `flux-system/flux-system`.
- Do **not** hand-edit `gotk-components.yaml` — it is auto-generated. To upgrade Flux on a cluster, re-run `flux bootstrap github` with the same `--path` using the target CLI version.
- Both kubeconfigs use the context name `kubernetes-admin@cluster.local`. Always pass `--kubeconfig` explicitly and check the server address before running `flux` or `kubectl`.
- Traefik uses host ports 80/443 on a single node on both clusters; its `updateStrategy` must keep `maxSurge: 0`, otherwise upgrades deadlock.

## Secrets (SOPS with age)

The repo is public: never commit a secret in plain text.

- Secrets are stored as `*.sops.yaml` and encrypted with age. `.sops.yaml` in the repo root holds the rules (currently only `clusters/dev/`) and encrypts just `data`/`stringData`.
- Flux decrypts them with the Secret `flux-system/sops-age` (created by hand, holds the private key). A Flux `Kustomization` that contains encrypted files needs `spec.decryption` with `provider: sops` and `secretRef.name: sops-age` — see `clusters/dev/flux-system/gitea-sync.yaml`.
- The private key lives on the admin's machine at `~/Library/Application Support/sops/age/keys.txt`. Never print it or a decrypted value into the conversation; check key names and lengths only.
- Create: write the Secret manifest, then `sops --encrypt --in-place <file>.sops.yaml`. Edit: `sops <file>.sops.yaml`.

## Apps on dev

Routing on dev uses the Gateway API: the Gateway `traefik-gateway` (namespace `traefik`) has the listeners `web` (HTTP) and `websecure` (HTTPS, wildcard certificate for `*.dev.cloud.clearclean.local`). An app attaches an `HTTPRoute` to `websecure` plus a redirect route on `web`; see `clusters/dev/dokuwiki/httproute.yaml`.

- **Gateway API CRDs** come from upstream via `gateway-api-sync.yaml` (Traefik 3.8 needs >= v1.7.0); they are disabled in the Kubespray inventory.
- **PostgreSQL** is provided by the CloudNativePG operator (`clusters/dev/cnpg-operator`). Each app declares its own `Cluster` next to its manifests; the operator generates the Secret `<cluster>-app` (`dbname`, `username`, `password`, `host`, `port`) and the Service `<cluster>-rw`. Do not use Bitnami charts or subcharts.
- **DokuWiki** (`clusters/dev/dokuwiki`): plain manifests with Kustomize and the official image. Config comes from `config/` (hashed ConfigMap, read-only in the wiki), plugins from `init/plugins.txt` (pinned URL + sha256), first-time setup from `init/init-storage.sh`. The admin password hash is in the hand-made Secret `dokuwiki-admin`.
- **Gitea** (`clusters/dev/gitea`): official Helm chart via `OCIRepository`, rootless image, bundled Bitnami subcharts disabled, database `gitea-db` via CloudNativePG, admin credentials in `admin-secret.sops.yaml`. HTTPS only, SSH and self-registration are off.
- There are no backups on dev.

## Useful Flux CLI Commands

```bash
# Check Flux prerequisites on a cluster
flux check --pre

# Force reconciliation
flux reconcile source git flux-system
flux reconcile kustomization flux-system

# View sync status
flux get all -A
```
