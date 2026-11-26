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
- Traefik on prod uses host ports 80/443 on a single node; its `updateStrategy` must keep `maxSurge: 0`, otherwise upgrades deadlock.

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
