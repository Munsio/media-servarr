# bjw-s app-template Conversion — Remaining 6 Charts Rollout Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the already-validated `charts/radarr` → bjw-s/app-template conversion pattern to the 6 remaining charts: bazarr, jellyfin, prowlarr, readarr, sabnzbd, sonarr.

**Architecture:** Identical to the radarr pilot (see `docs/superpowers/specs/2026-07-12-bjw-s-conversion-design.md` and `charts/radarr` as the reference implementation): each chart drops its dependency on `media-servarr-base` and depends on `bjw-s/app-template` v5.0.1 instead. All values live under a top-level `app-template:` key (required because app-template is a Helm *dependency*, not the installed chart itself — confirmed during the radarr pilot). Each chart's `config` PersistentVolumeClaim keeps its exact literal name via `forceRename`, so `helm upgrade` on a live install re-adopts the existing PVC. Config-file secret substitution is a static per-chart `initContainers.prepare-config` entry (no shared generic templating layer) — for charts whose config has no `$secret`-style placeholders (jellyfin), this init container is unnecessary and omitted entirely, mounting the ConfigMap directly instead.

**Tech Stack:** Helm 3, bjw-s/app-template v5.0.1, Nix flake devShell (`nix develop`) providing `helm`/`kubectl`/`dasel`, `scripts/diff-chart-render.sh` (added during the pilot) for render-diff validation.

## Global Constraints

- Every command needing `helm`/`kubectl`/`dasel` MUST run inside the Nix devShell: `nix develop /home/martin/Documents/projects/media-servarr/.claude/worktrees/bjw-s-conversion --command bash -c '...'`.
- Every chart's new `values.yaml` nests ALL app-template configuration under a top-level `app-template:` key. This is not optional — flat top-level values silently fail to reach app-template's templates (Helm subchart value-scoping). Verify by rendering and confirming more than a bare ServiceAccount comes out.
- Every chart's `persistence.config` block uses `forceRename: '<chart>-config'` (the literal PVC name each chart already hardcodes today), `accessMode: ReadWriteOnce`, `size: 1Gi` — unchanged from today's behavior. This is the non-negotiable data-safety requirement; do not alter these three fields.
- Every chart's `Chart.yaml`: bump `version` to `1.0.0`, change `kubeversion` (lowercase, ignored by Helm) to `kubeVersion: ">=1.28.0-0"` (app-template's own stated minimum), replace the `media-servarr-base` dependency with:
  ```yaml
  dependencies:
    - name: 'app-template'
      version: '5.0.1'
      repository: 'https://bjw-s-labs.github.io/helm-charts'
  ```
  Leave `appVersion`, `description`, `keywords`, `home`, `icon`, `maintainers`, `sources` unchanged. `readarr`'s `deprecated: true` field must be preserved.
- Delete each chart's `templates/application.yaml` and `templates/NOTES.txt` (stale, call the removed `media-servarr-base.*` helpers).
- Metrics sidecar (exportarr) pattern, where applicable: `controllers.main.containers.metrics` (image `ghcr.io/onedr0p/exportarr:v1.6.1`, `args: [<app>]`, env `PORT`/`URL`/`APIKEY`, `resources: {requests: {cpu: 100m, memory: 64Mi}, limits: {cpu: 500m, memory: 256Mi}}`, HTTP probes on `/healthz` via the `monitoring` port), a `service.main.ports.monitoring` entry, and a `serviceMonitor.main` entry — all three gated by their own `enabled` flag (no single meta-toggle exists in app-template; this is an accepted, already-documented behavior change from the pilot). The sidecar reaches the app via `http://localhost:<port>/<urlBase>` (same pod, no need for app-template's internal naming helpers).
- Each task's README rewrite should mirror `charts/radarr/README.md`'s current structure (already converted, at HEAD) — same section order (`### A note on values structure`, `### Secrets`, `### Application Configuration`, `### Volumes`, `### Ingress`, `### Metrics` where applicable, `### Advanced`, then a `## Migrating from v0.x to v1.0.0` section before `## Upgrading`) — substituting this chart's own specific values (secret names, config filename/content, persistence items, ports, ingress path). Read `charts/radarr/README.md` directly for the exact prose/wording pattern to follow; every concrete value to substitute is given in this chart's task below.
- Validate each conversion with `./scripts/diff-chart-render.sh <chart> <old-ref> HEAD <old-values-file> <new-values-file>` (added in the radarr pilot; the two-values-file form added after Task 1 of this rollout found that a single shared file only speaks one schema — the old chart silently ignores keys it doesn't recognize, e.g. the new schema's `app-template.persistence.config.storageClass` means nothing to a chart still on the old `persistentVolumeClaims.<chart>-config.storageClassName` shape, and vice versa). Confirm the rendered PersistentVolumeClaim's `metadata.name`, `metadata.namespace`, `spec.accessModes`, `spec.resources.requests.storage`, and `spec.storageClassName` are identical between old and new. `<old-ref>` is the commit immediately before this task's own conversion commit — since `diff-chart-render.sh` renders from committed trees via `git worktree add`, it cannot see uncommitted changes, so run this validation step *after* committing the conversion, using that commit as `HEAD`/`<new-ref>` and the prior commit as `<old-ref>`.
- The homelab GitOps repo at `~/Documents/projects/homelab/kubernetes/servarr` is a **read-only reference** — copy values out of it into scratch files, never edit files there. Never put a real secret value from that repo into a committed file in this repo (this repo is public) — use an obviously-fake placeholder string instead, exactly as was done for radarr's plan (`example-not-a-real-api-key`).

---

### Task 1: Convert `charts/bazarr`

**Files:**
- Modify: `charts/bazarr/Chart.yaml`, `charts/bazarr/values.yaml`, `charts/bazarr/README.md`
- Delete: `charts/bazarr/templates/application.yaml`, `charts/bazarr/templates/NOTES.txt`

**Context:** Bazarr's `config.yaml` (YAML, not XML) has one secret placeholder (`$apiKey`) and its processed-config mount path is nested one level deeper than radarr's: `/config/config/config.yaml`. It has no downloads/media volumes — config only. `appVersion` stays `1.5.3`.

- [ ] **Step 1: Rewrite `charts/bazarr/Chart.yaml`**

Apply the Global Constraints changes. Full file:

```yaml
apiVersion: 'v2'
name: 'bazarr'
description: 'Companion application to Sonarr and Radarr to manage and download subtitles'
home: 'https://github.com/drinkataco/media-servarr/tree/main/charts/bazarr'
keywords:
  - 'subtitles'
  - 'torrent'
  - 'bittorrent'
  - 'usenet'
  - 'manager'
  - 'radarr'
  - 'sonarr'
  - 'bazarr'
kubeVersion: ">=1.28.0-0"
type: 'application'
version: 1.0.0
appVersion: 1.5.3
icon: 'https://github.com/drinkataco/media-servarr/blob/main/charts/bazarr/icon.png'
dependencies:
  - name: 'app-template'
    version: '5.0.1'
    repository: 'https://bjw-s-labs.github.io/helm-charts'
maintainers:
  - name: 'media-servarr'
    email: 'git@jo.shw.al'
    url: 'https://github.com/drinkataco/media-servarr/'
sources:
  - 'https://github.com/morpheus65535/Bazarr'
  - 'https://github.com/linuxserver/docker-bazarr'
  - 'https://ghcr.io/onedr0p/exportarr'
  - 'https://github.com/drinkataco/media-servarr/tree/main/charts/bazarr'
```

- [ ] **Step 2: Rewrite `charts/bazarr/values.yaml`**

```yaml
# Default values for the bazarr chart. app-template is a Helm chart *dependency*
# here (see Chart.yaml), not the chart being installed directly — Helm only
# passes a subchart the slice of these values nested under a key matching the
# subchart's name. Everything below therefore lives under `app-template:`.
# See https://bjw-s-labs.github.io/helm-charts/docs/app-template/ for the full schema.

app-template:
  secrets:
    bazarr:
      stringData:
        apiKey: ''

  configMaps:
    config:
      data:
        config.yaml: |
          ---
          # We can set up a lot of extra settings, and providers, directly here
          # To get an example of an exhaustive list of of possible values you could add here see:
          #   ./config.example.yaml
          analytics:
            enabled: false
          auth:
            apiKey: '$apiKey'
          general:
            adaptive_searching: true
            auto_update: false
            base_url: '/bazarr'
            port: 6767
            use_radarr: false
            use_sonarr: false
            # radarr:
            #   apiKey: '$radarrApiKey'
            #   base_url: '/radarr'
            #   ip: 'radarr.media-servarr.svc.cluster.local'
            #   port: 7878
            # sonarr:
            #   apiKey: '$sonarrApiKey'
            #   base_url: '/sonarr'
            #   ip: 'sonarr.media-servarr.svc.cluster.local'
            #   port: 8989

  controllers:
    main:
      initContainers:
        prepare-config:
          image:
            repository: alpine
            tag: "3.20"
          command: ["/bin/sh"]
          args:
            - -c
            - |
              sed -e "s/\$apiKey/$apiKey/g" /config-map/config.yaml > /config-processed/config.yaml
          env:
            apiKey:
              valueFrom:
                secretKeyRef:
                  name: bazarr
                  key: apiKey
      containers:
        main:
          image:
            repository: lscr.io/linuxserver/bazarr
            tag: "1.5.3"
          env:
            PGID: "1000"
            PUID: "1000"
          ports:
            - name: http
              containerPort: 6767
          probes:
            liveness:
              enabled: true
              type: HTTP
              path: /bazarr/system/status
              port: http
              spec:
                initialDelaySeconds: 30
            readiness:
              enabled: true
              type: HTTP
              path: /bazarr/system/status
              port: http
              spec:
                initialDelaySeconds: 15
        metrics:
          enabled: false
          image:
            repository: ghcr.io/onedr0p/exportarr
            tag: v1.6.1
          args:
            - bazarr
          env:
            PORT: "9700"
            URL: "http://localhost:6767/bazarr"
            APIKEY:
              valueFrom:
                secretKeyRef:
                  name: bazarr
                  key: apiKey
          ports:
            - name: monitoring
              containerPort: 9700
          probes:
            liveness:
              enabled: true
              type: HTTP
              path: /healthz
              port: monitoring
            readiness:
              enabled: true
              type: HTTP
              path: /healthz
              port: monitoring
          resources:
            requests:
              cpu: 100m
              memory: 64Mi
            limits:
              cpu: 500m
              memory: 256Mi

  service:
    main:
      controller: main
      ports:
        http:
          port: 6767
        monitoring:
          enabled: false
          port: 9700

  serviceMonitor:
    main:
      enabled: false
      endpoints:
        - port: monitoring
          interval: 4m
          scrapeTimeout: 90s
          path: /metrics

  ingress:
    main:
      enabled: true
      className: ""
      annotations: {}
      hosts:
        - host: media-servarr.local
          paths:
            - path: /bazarr
              pathType: Prefix
              service:
                identifier: main
                port: http

  persistence:
    config:
      type: persistentVolumeClaim
      forceRename: bazarr-config
      accessMode: ReadWriteOnce
      size: 1Gi
      globalMounts:
        - path: /config
    raw-config:
      type: configMap
      identifier: config
      advancedMounts:
        main:
          prepare-config:
            - path: /config-map
    processed-config:
      type: emptyDir
      advancedMounts:
        main:
          prepare-config:
            - path: /config-processed
          main:
            - path: /config/config/config.yaml
              subPath: config.yaml
```

- [ ] **Step 3: Delete stale templates**

```bash
cd /home/martin/Documents/projects/media-servarr/.claude/worktrees/bjw-s-conversion
git rm -r charts/bazarr/templates
```

- [ ] **Step 4: Render and validate**

```bash
nix develop --command bash -c '
  helm dependency update charts/bazarr
  helm template bazarr charts/bazarr --namespace media-servarr
' > /dev/null && echo "RENDER OK"
```

Create two scratch values files for the diff validation — one per schema, since a single shared file only speaks one side's schema and the other side silently ignores keys it doesn't recognize (fake secret in both, mirrors the homelab's real `bazarr-values.yaml` shape read-only, without copying the real API key):

Old-schema (`.../scratchpad/bazarr-old-values.yaml`):

```yaml
secrets:
  - name: apiKey
    value: example-not-a-real-api-key
persistentVolumeClaims:
  bazarr-config:
    storageClassName: ceph-block
```

New-schema (`.../scratchpad/bazarr-new-values.yaml`):

```yaml
app-template:
  secrets:
    bazarr:
      stringData:
        apiKey: example-not-a-real-api-key
  persistence:
    config:
      storageClass: ceph-block
```

`diff-chart-render.sh` renders from committed trees, so run this *after* committing this task's conversion (Step 6), using the pre-conversion commit as `<old-ref>` (`git rev-parse HEAD` recorded before Step 1) and the new conversion commit as `<new-ref>`:

```bash
nix develop --command bash -c './scripts/diff-chart-render.sh bazarr <old-ref> <new-ref> /tmp/claude-1000/-home-martin-Documents-projects-media-servarr/6831eeb5-b965-48a0-9f0d-300bda72c578/scratchpad/bazarr-old-values.yaml /tmp/claude-1000/-home-martin-Documents-projects-media-servarr/6831eeb5-b965-48a0-9f0d-300bda72c578/scratchpad/bazarr-new-values.yaml'
```

Confirm in the diff (or the rich `lazygit`/`zeditor` view the script prints a path for) that the PersistentVolumeClaim's `metadata.name` (`bazarr-config`), `metadata.namespace`, `spec.accessModes`, `spec.resources.requests.storage` (`1Gi`), and `spec.storageClassName` (`ceph-block`) are identical between old and new. Clean up the scratch values files afterward.

- [ ] **Step 5: Rewrite `charts/bazarr/README.md`**

Follow `charts/radarr/README.md`'s structure and prose pattern (read it directly), substituting:
- Chart/app name: Bazarr / bazarr, port 6767, default ingress path `/bazarr`
- Secrets example: `app-template.secrets.bazarr.stringData.apiKey`
- Application Configuration example: `app-template.configMaps.config.data['config.yaml']` (note: single-quote the key or use the block form `config.yaml:` since it's a valid YAML key either way), with bazarr's actual config content from Step 2
- Volumes section: only one persistence item, **config** (PVC `bazarr-config`) — no downloads/media items for this chart
- Metrics section: three toggles as described in Global Constraints, port `9700`
- Migration section: same wording pattern as radarr's, PVC name `bazarr-config`, `app-template.persistence.config.forceRename`

- [ ] **Step 6: Commit**

```bash
git add charts/bazarr
git commit -m "$(cat <<'EOF'
Convert bazarr chart to bjw-s/app-template

Same pattern as the radarr pilot: app-template v5.0.1 dependency,
values nested under app-template:, config PVC keeps its literal name
(bazarr-config) via forceRename so helm upgrade preserves it.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Convert `charts/jellyfin`

**Files:**
- Modify: `charts/jellyfin/Chart.yaml`, `charts/jellyfin/values.yaml`, `charts/jellyfin/README.md`
- Delete: `charts/jellyfin/templates/application.yaml`, `charts/jellyfin/templates/NOTES.txt`

**Context:** Jellyfin is the simplest chart: no secrets at all, no `$placeholder` substitution in its config, and no metrics/exportarr sidecar (Jellyfin's own Prometheus metrics are toggled inside its own config, unrelated to this chart's schema — out of scope, same as before). Because there's no secret to inject, there's no need for a `prepare-config` init container at all — mount the ConfigMap directly at its final path. `appVersion` stays `10.11.0`.

- [ ] **Step 1: Rewrite `charts/jellyfin/Chart.yaml`**

```yaml
apiVersion: 'v2'
name: 'jellyfin'
description: 'A free software media system that puts you in control of managing and streaming your media'
home: 'https://github.com/drinkataco/media-servarr/tree/main/charts/jellyfin'
keywords:
  - 'music'
  - 'tv'
  - 'television'
  - 'film'
  - 'movie'
  - 'ebooks'
  - 'manager'
  - 'stream'
  - 'media'
  - 'jellyfin'
kubeVersion: ">=1.28.0-0"
type: 'application'
version: 1.0.0
appVersion: 10.11.0
icon: 'https://github.com/drinkataco/media-servarr/blob/main/charts/jellyfin/icon.png'
dependencies:
  - name: 'app-template'
    version: '5.0.1'
    repository: 'https://bjw-s-labs.github.io/helm-charts'
maintainers:
  - name: 'media-servarr'
    email: 'git@jo.shw.al'
    url: 'https://github.com/drinkataco/media-servarr/'
sources:
  - 'https://github.com/jellyfin/jellyfin'
  - 'https://github.com/drinkataco/media-servarr/tree/main/charts/jellyfin'
```

- [ ] **Step 2: Rewrite `charts/jellyfin/values.yaml`**

```yaml
# Default values for the jellyfin chart. app-template is a Helm chart
# *dependency* here (see Chart.yaml), not the chart being installed directly —
# Helm only passes a subchart the slice of these values nested under a key
# matching the subchart's name. Everything below therefore lives under
# `app-template:`.
# See https://bjw-s-labs.github.io/helm-charts/docs/app-template/ for the full schema.

app-template:
  configMaps:
    config:
      data:
        network.xml: |
          <?xml version="1.0" encoding="utf-8"?>
          <NetworkConfiguration xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
            <BaseUrl>jellyfin</BaseUrl>
            <HttpServerPortNumber>8096</HttpServerPortNumber>
            <EnableHttps>false</EnableHttps>
            <PublicPort>8096</PublicPort>
            <EnableRemoteAccess>true</EnableRemoteAccess>
          </NetworkConfiguration>

  controllers:
    main:
      containers:
        main:
          image:
            repository: jellyfin/jellyfin
            tag: "10.11.0"
          ports:
            - name: http
              containerPort: 8096

  service:
    main:
      controller: main
      ports:
        http:
          port: 8096

  ingress:
    main:
      enabled: true
      className: ""
      annotations: {}
      hosts:
        - host: media-servarr.local
          paths:
            - path: /jellyfin
              pathType: Prefix
              service:
                identifier: main
                port: http

  persistence:
    config:
      type: persistentVolumeClaim
      forceRename: jellyfin-config
      accessMode: ReadWriteOnce
      size: 1Gi
      globalMounts:
        - path: /config
    raw-config:
      type: configMap
      identifier: config
      advancedMounts:
        main:
          main:
            - path: /config/config/network.xml
              subPath: network.xml
    ebooks:
      type: emptyDir
      globalMounts:
        - path: /ebooks
    film:
      type: emptyDir
      globalMounts:
        - path: /film
    music:
      type: emptyDir
      globalMounts:
        - path: /music
    television:
      type: emptyDir
      globalMounts:
        - path: /tv
```

- [ ] **Step 3: Delete stale templates**

```bash
git rm -r charts/jellyfin/templates
```

- [ ] **Step 4: Render and validate**

```bash
nix develop --command bash -c '
  helm dependency update charts/jellyfin
  helm template jellyfin charts/jellyfin --namespace media-servarr
' > /dev/null && echo "RENDER OK"
```

Old-schema scratch values (`.../scratchpad/jellyfin-old-values.yaml`; no secrets to fake here — jellyfin has none):

```yaml
persistentVolumeClaims:
  jellyfin-config:
    storageClassName: ceph-block
```

New-schema scratch values (`.../scratchpad/jellyfin-new-values.yaml`):

```yaml
app-template:
  persistence:
    config:
      storageClass: ceph-block
```

```bash
nix develop --command bash -c './scripts/diff-chart-render.sh jellyfin <old-ref> HEAD /tmp/claude-1000/-home-martin-Documents-projects-media-servarr/6831eeb5-b965-48a0-9f0d-300bda72c578/scratchpad/jellyfin-old-values.yaml /tmp/claude-1000/-home-martin-Documents-projects-media-servarr/6831eeb5-b965-48a0-9f0d-300bda72c578/scratchpad/jellyfin-new-values.yaml'
```

Confirm PVC `metadata.name: jellyfin-config`, matching namespace, `ReadWriteOnce`, `1Gi`, `ceph-block` across old and new. Clean up the scratch file afterward.

- [ ] **Step 5: Rewrite `charts/jellyfin/README.md`**

Follow `charts/radarr/README.md`'s structure, but:
- Omit the Secrets section entirely (jellyfin has none)
- Application Configuration example uses `app-template.configMaps.config.data['network.xml']`, with jellyfin's actual content from Step 2, and note the config is mounted directly (no secret substitution/init container involved, unlike radarr)
- Volumes section lists five persistence items: **config** (PVC `jellyfin-config`), **ebooks**, **film**, **music**, **television** (all plain `emptyDir` by default)
- Omit the Metrics section (not applicable — note in a short line that Jellyfin's own internal metrics toggle in `system.xml` is unrelated to this chart's schema)
- Migration section: PVC name `jellyfin-config`

- [ ] **Step 6: Commit**

```bash
git add charts/jellyfin
git commit -m "$(cat <<'EOF'
Convert jellyfin chart to bjw-s/app-template

Same pattern as the radarr pilot, simplified: jellyfin has no secrets
and no $placeholder substitution in its config, so no prepare-config
init container is needed — the ConfigMap mounts directly. Config PVC
keeps its literal name (jellyfin-config) via forceRename.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Convert `charts/prowlarr`

**Files:**
- Modify: `charts/prowlarr/Chart.yaml`, `charts/prowlarr/values.yaml`, `charts/prowlarr/README.md`
- Delete: `charts/prowlarr/templates/application.yaml`, `charts/prowlarr/templates/NOTES.txt`

**Context:** Structurally identical to radarr (one XML config file, one apiKey secret, exportarr sidecar), just config-only (no downloads/media volumes). `appVersion` stays `2.0.5`.

- [ ] **Step 1: Rewrite `charts/prowlarr/Chart.yaml`**

```yaml
apiVersion: 'v2'
name: 'prowlarr'
description: 'BitTorrent indexer management'
home: 'https://github.com/drinkataco/media-servarr/tree/main/charts/prowlarr'
keywords:
  - 'bittorrent'
  - 'torrent'
  - 'download'
  - 'indexer'
  - 'prowlarr'
kubeVersion: ">=1.28.0-0"
type: 'application'
version: 1.0.0
appVersion: 2.0.5
icon: 'https://github.com/drinkataco/media-servarr/blob/main/charts/prowlarr/icon.png'
dependencies:
  - name: 'app-template'
    version: '5.0.1'
    repository: 'https://bjw-s-labs.github.io/helm-charts'
maintainers:
  - name: 'media-servarr'
    email: 'git@jo.shw.al'
    url: 'https://github.com/drinkataco/media-servarr/'
sources:
  - 'https://github.com/Prowlarr/Prowlarr'
  - 'https://github.com/linuxserver/docker-prowlarr'
  - 'https://ghcr.io/onedr0p/exportarr'
  - 'https://github.com/drinkataco/media-servarr/tree/main/charts/prowlarr'
```

- [ ] **Step 2: Rewrite `charts/prowlarr/values.yaml`**

```yaml
# Default values for the prowlarr chart. app-template is a Helm chart
# *dependency* here (see Chart.yaml), not the chart being installed directly —
# Helm only passes a subchart the slice of these values nested under a key
# matching the subchart's name. Everything below therefore lives under
# `app-template:`.
# See https://bjw-s-labs.github.io/helm-charts/docs/app-template/ for the full schema.

app-template:
  secrets:
    prowlarr:
      stringData:
        apiKey: ''

  configMaps:
    config:
      data:
        config.xml: |
          <Config>
            <LogLevel>info</LogLevel>
            <EnableSsl>False</EnableSsl>
            <Port>9696</Port>
            <UrlBase>prowlarr</UrlBase>
            <BindAddress>*</BindAddress>
            <ApiKey>$apiKey</ApiKey>
            <AnalyticsEnabled>False</AnalyticsEnabled>
            <AuthenticationMethod>External</AuthenticationMethod>
            <UpdateMechanism>Docker</UpdateMechanism>
            <Branch>main</Branch>
            <InstanceName>Prowlarr</InstanceName>
          </Config>

  controllers:
    main:
      initContainers:
        prepare-config:
          image:
            repository: alpine
            tag: "3.20"
          command: ["/bin/sh"]
          args:
            - -c
            - |
              sed -e "s/\$apiKey/$apiKey/g" /config-map/config.xml > /config-processed/config.xml
          env:
            apiKey:
              valueFrom:
                secretKeyRef:
                  name: prowlarr
                  key: apiKey
      containers:
        main:
          image:
            repository: lscr.io/linuxserver/prowlarr
            tag: "2.0.5"
          env:
            PGID: "1000"
            PUID: "1000"
          ports:
            - name: http
              containerPort: 9696
        metrics:
          enabled: false
          image:
            repository: ghcr.io/onedr0p/exportarr
            tag: v1.6.1
          args:
            - prowlarr
          env:
            PORT: "9703"
            URL: "http://localhost:9696/prowlarr"
            APIKEY:
              valueFrom:
                secretKeyRef:
                  name: prowlarr
                  key: apiKey
          ports:
            - name: monitoring
              containerPort: 9703
          probes:
            liveness:
              enabled: true
              type: HTTP
              path: /healthz
              port: monitoring
            readiness:
              enabled: true
              type: HTTP
              path: /healthz
              port: monitoring
          resources:
            requests:
              cpu: 100m
              memory: 64Mi
            limits:
              cpu: 500m
              memory: 256Mi

  service:
    main:
      controller: main
      ports:
        http:
          port: 9696
        monitoring:
          enabled: false
          port: 9703

  serviceMonitor:
    main:
      enabled: false
      endpoints:
        - port: monitoring
          interval: 4m
          scrapeTimeout: 90s
          path: /metrics

  ingress:
    main:
      enabled: true
      className: ""
      annotations: {}
      hosts:
        - host: media-servarr.local
          paths:
            - path: /prowlarr
              pathType: Prefix
              service:
                identifier: main
                port: http

  persistence:
    config:
      type: persistentVolumeClaim
      forceRename: prowlarr-config
      accessMode: ReadWriteOnce
      size: 1Gi
      globalMounts:
        - path: /config
    raw-config:
      type: configMap
      identifier: config
      advancedMounts:
        main:
          prepare-config:
            - path: /config-map
    processed-config:
      type: emptyDir
      advancedMounts:
        main:
          prepare-config:
            - path: /config-processed
          main:
            - path: /config/config.xml
              subPath: config.xml
```

- [ ] **Step 3: Delete stale templates**

```bash
git rm -r charts/prowlarr/templates
```

- [ ] **Step 4: Render and validate**

```bash
nix develop --command bash -c '
  helm dependency update charts/prowlarr
  helm template prowlarr charts/prowlarr --namespace media-servarr
' > /dev/null && echo "RENDER OK"
```

Old-schema scratch values (`.../scratchpad/prowlarr-old-values.yaml`):

```yaml
secrets:
  - name: apiKey
    value: example-not-a-real-api-key
persistentVolumeClaims:
  prowlarr-config:
    storageClassName: ceph-block
```

New-schema scratch values (`.../scratchpad/prowlarr-new-values.yaml`):

```yaml
app-template:
  secrets:
    prowlarr:
      stringData:
        apiKey: example-not-a-real-api-key
  persistence:
    config:
      storageClass: ceph-block
```

```bash
nix develop --command bash -c './scripts/diff-chart-render.sh prowlarr <old-ref> HEAD /tmp/claude-1000/-home-martin-Documents-projects-media-servarr/6831eeb5-b965-48a0-9f0d-300bda72c578/scratchpad/prowlarr-old-values.yaml /tmp/claude-1000/-home-martin-Documents-projects-media-servarr/6831eeb5-b965-48a0-9f0d-300bda72c578/scratchpad/prowlarr-new-values.yaml'
```

Confirm PVC `metadata.name: prowlarr-config`, matching namespace/accessModes/size/storageClass. Clean up the scratch file afterward.

- [ ] **Step 5: Rewrite `charts/prowlarr/README.md`**

Follow `charts/radarr/README.md`'s structure, substituting:
- Bazarr/Radarr → Prowlarr, port 9696, ingress path `/prowlarr`
- Secrets: `app-template.secrets.prowlarr.stringData.apiKey`
- Application Configuration: `app-template.configMaps.config.data['config.xml']` with prowlarr's content from Step 2
- Volumes: only **config** (PVC `prowlarr-config`)
- Metrics: port `9703`
- Migration: PVC name `prowlarr-config`

- [ ] **Step 6: Commit**

```bash
git add charts/prowlarr
git commit -m "$(cat <<'EOF'
Convert prowlarr chart to bjw-s/app-template

Same pattern as the radarr pilot. Config PVC keeps its literal name
(prowlarr-config) via forceRename.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Convert `charts/readarr`

**Files:**
- Modify: `charts/readarr/Chart.yaml`, `charts/readarr/values.yaml`, `charts/readarr/README.md`
- Delete: `charts/readarr/templates/application.yaml`, `charts/readarr/templates/NOTES.txt`

**Context:** Same shape as radarr/sonarr (one config file, one apiKey secret, exportarr sidecar, `downloads`+`ebooks` emptyDir volumes). **Preserve `deprecated: true`** in Chart.yaml — this chart is marked deprecated upstream and that field must not be dropped. `appVersion` stays `0.4.19-nightly`.

- [ ] **Step 1: Rewrite `charts/readarr/Chart.yaml`**

```yaml
apiVersion: 'v2'
name: 'readarr'
description: 'Ebook and audiobook collection manager for Usenet and BitTorrent users'
home: 'https://github.com/drinkataco/media-servarr/tree/main/charts/readarr'
keywords:
  - 'ebooks'
  - 'audiobooks'
  - 'torrent'
  - 'bittorrent'
  - 'usenet'
  - 'manager'
  - 'readarr'
kubeVersion: ">=1.28.0-0"
type: 'application'
version: 1.0.0
appVersion: 0.4.19-nightly
icon: 'https://github.com/drinkataco/media-servarr/blob/main/charts/readarr/icon.png'
deprecated: true
dependencies:
  - name: 'app-template'
    version: '5.0.1'
    repository: 'https://bjw-s-labs.github.io/helm-charts'
maintainers:
  - name: 'media-servarr'
    email: 'git@jo.shw.al'
    url: 'https://github.com/drinkataco/media-servarr/'
sources:
  - 'https://github.com/Readarr/Readarr'
  - 'https://github.com/linuxserver/docker-readarr'
  - 'https://ghcr.io/onedr0p/exportarr'
  - 'https://github.com/drinkataco/media-servarr/tree/main/charts/readarr'
```

- [ ] **Step 2: Rewrite `charts/readarr/values.yaml`**

```yaml
# Default values for the readarr chart. app-template is a Helm chart
# *dependency* here (see Chart.yaml), not the chart being installed directly —
# Helm only passes a subchart the slice of these values nested under a key
# matching the subchart's name. Everything below therefore lives under
# `app-template:`.
# See https://bjw-s-labs.github.io/helm-charts/docs/app-template/ for the full schema.

app-template:
  secrets:
    readarr:
      stringData:
        apiKey: ''

  configMaps:
    config:
      data:
        config.xml: |
          <Config>
            <LogLevel>info</LogLevel>
            <EnableSsl>False</EnableSsl>
            <Port>8787</Port>
            <UrlBase>readarr</UrlBase>
            <BindAddress>*</BindAddress>
            <ApiKey>$apiKey</ApiKey>
            <AnalyticsEnabled>False</AnalyticsEnabled>
            <AuthenticationMethod>External</AuthenticationMethod>
            <UpdateMechanism>Docker</UpdateMechanism>
            <Branch>develop</Branch>
            <InstanceName>Readarr</InstanceName>
          </Config>

  controllers:
    main:
      initContainers:
        prepare-config:
          image:
            repository: alpine
            tag: "3.20"
          command: ["/bin/sh"]
          args:
            - -c
            - |
              sed -e "s/\$apiKey/$apiKey/g" /config-map/config.xml > /config-processed/config.xml
          env:
            apiKey:
              valueFrom:
                secretKeyRef:
                  name: readarr
                  key: apiKey
      containers:
        main:
          image:
            repository: lscr.io/linuxserver/readarr
            tag: "0.4.19-nightly"
          env:
            PGID: "1000"
            PUID: "1000"
          ports:
            - name: http
              containerPort: 8787
        metrics:
          enabled: false
          image:
            repository: ghcr.io/onedr0p/exportarr
            tag: v1.6.1
          args:
            - readarr
          env:
            PORT: "9705"
            URL: "http://localhost:8787/readarr"
            APIKEY:
              valueFrom:
                secretKeyRef:
                  name: readarr
                  key: apiKey
          ports:
            - name: monitoring
              containerPort: 9705
          probes:
            liveness:
              enabled: true
              type: HTTP
              path: /healthz
              port: monitoring
            readiness:
              enabled: true
              type: HTTP
              path: /healthz
              port: monitoring
          resources:
            requests:
              cpu: 100m
              memory: 64Mi
            limits:
              cpu: 500m
              memory: 256Mi

  service:
    main:
      controller: main
      ports:
        http:
          port: 8787
        monitoring:
          enabled: false
          port: 9705

  serviceMonitor:
    main:
      enabled: false
      endpoints:
        - port: monitoring
          interval: 4m
          scrapeTimeout: 90s
          path: /metrics

  ingress:
    main:
      enabled: true
      className: ""
      annotations: {}
      hosts:
        - host: media-servarr.local
          paths:
            - path: /readarr
              pathType: Prefix
              service:
                identifier: main
                port: http

  persistence:
    config:
      type: persistentVolumeClaim
      forceRename: readarr-config
      accessMode: ReadWriteOnce
      size: 1Gi
      globalMounts:
        - path: /config
    raw-config:
      type: configMap
      identifier: config
      advancedMounts:
        main:
          prepare-config:
            - path: /config-map
    processed-config:
      type: emptyDir
      advancedMounts:
        main:
          prepare-config:
            - path: /config-processed
          main:
            - path: /config/config.xml
              subPath: config.xml
    downloads:
      type: emptyDir
      globalMounts:
        - path: /downloads
    ebooks:
      type: emptyDir
      globalMounts:
        - path: /ebooks
```

- [ ] **Step 3: Delete stale templates**

```bash
git rm -r charts/readarr/templates
```

- [ ] **Step 4: Render and validate**

```bash
nix develop --command bash -c '
  helm dependency update charts/readarr
  helm template readarr charts/readarr --namespace media-servarr
' > /dev/null && echo "RENDER OK"
```

Old-schema scratch values (`.../scratchpad/readarr-old-values.yaml`):

```yaml
secrets:
  - name: apiKey
    value: example-not-a-real-api-key
persistentVolumeClaims:
  readarr-config:
    storageClassName: ceph-block
```

New-schema scratch values (`.../scratchpad/readarr-new-values.yaml`):

```yaml
app-template:
  secrets:
    readarr:
      stringData:
        apiKey: example-not-a-real-api-key
  persistence:
    config:
      storageClass: ceph-block
    data-pv:
      type: custom
      volumeSpec:
        persistentVolumeClaim:
          claimName: data-pv
      globalMounts:
        - path: /data
```

```bash
nix develop --command bash -c './scripts/diff-chart-render.sh readarr <old-ref> HEAD /tmp/claude-1000/-home-martin-Documents-projects-media-servarr/6831eeb5-b965-48a0-9f0d-300bda72c578/scratchpad/readarr-old-values.yaml /tmp/claude-1000/-home-martin-Documents-projects-media-servarr/6831eeb5-b965-48a0-9f0d-300bda72c578/scratchpad/readarr-new-values.yaml'
```

Confirm PVC `metadata.name: readarr-config`, matching namespace/accessModes/size/storageClass. Clean up the scratch file afterward.

- [ ] **Step 5: Rewrite `charts/readarr/README.md`**

Follow `charts/radarr/README.md`'s structure, substituting:
- Radarr → Readarr, port 8787, ingress path `/readarr`
- Secrets: `app-template.secrets.readarr.stringData.apiKey`
- Application Configuration: `app-template.configMaps.config.data['config.xml']` with readarr's content from Step 2 (`Branch: develop`)
- Volumes: **config** (PVC `readarr-config`), **downloads**, **ebooks** (both plain `emptyDir`)
- Metrics: port `9705`
- Migration: PVC name `readarr-config`
- Keep any existing note in the README about this chart being deprecated upstream, if present — do not remove it

- [ ] **Step 6: Commit**

```bash
git add charts/readarr
git commit -m "$(cat <<'EOF'
Convert readarr chart to bjw-s/app-template

Same pattern as the radarr pilot. Config PVC keeps its literal name
(readarr-config) via forceRename. deprecated: true preserved in
Chart.yaml.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Convert `charts/sabnzbd`

**Files:**
- Modify: `charts/sabnzbd/Chart.yaml`, `charts/sabnzbd/values.yaml`, `charts/sabnzbd/README.md`
- Delete: `charts/sabnzbd/templates/application.yaml`, `charts/sabnzbd/templates/NOTES.txt`

**Context:** The one chart with **three** secrets (`apiKey`, `nzbKey`, `newsreaderServerPassword`) needing substitution in its config (an INI file, not XML/YAML), and the only chart whose `downloads` volume mounts at a non-default path (`/config/Downloads`, nested under `/config`, not `/downloads`). It's also the only chart whose metrics sidecar defaults to **enabled** (`metrics.enabled: true` in the current chart) — preserve that as the default for `containers.metrics.enabled`, `service.main.ports.monitoring.enabled`, and `serviceMonitor.main.enabled` (all three `true` by default here, unlike every other chart in this rollout). `appVersion` stays `4.5.3`. Note this chart's current `values.yaml` has no `nameOverride`/`fullnameOverride` lines at the top (harmless, unrelated to app-template) — no need to add them.

- [ ] **Step 1: Rewrite `charts/sabnzbd/Chart.yaml`**

```yaml
apiVersion: 'v2'
name: 'sabnzbd'
description: 'SABnzbd is a program to download binary files from Usenet servers'
home: 'https://github.com/drinkataco/media-servarr/tree/main/charts/sabnzbd'
keywords:
  - 'usenet'
  - 'newsreader'
  - 'sabnzbd'
kubeVersion: ">=1.28.0-0"
type: 'application'
version: 1.0.0
appVersion: 4.5.3
icon: 'https://github.com/drinkataco/media-servarr/blob/main/charts/sabnzbd/icon.png'
dependencies:
  - name: 'app-template'
    version: '5.0.1'
    repository: 'https://bjw-s-labs.github.io/helm-charts'
maintainers:
  - name: 'media-servarr'
    email: 'git@jo.shw.al'
    url: 'https://github.com/drinkataco/media-servarr/'
sources:
  - 'https://github.com/sabnzbd/sabnzbd'
  - 'https://hub.docker.com/r/linuxserver/sabnzbd'
  - 'https://ghcr.io/onedr0p/exportarr'
  - 'https://github.com/drinkataco/media-servarr/tree/main/charts/sabnzbd'
```

- [ ] **Step 2: Rewrite `charts/sabnzbd/values.yaml`**

```yaml
# Default values for the sabnzbd chart. app-template is a Helm chart
# *dependency* here (see Chart.yaml), not the chart being installed directly —
# Helm only passes a subchart the slice of these values nested under a key
# matching the subchart's name. Everything below therefore lives under
# `app-template:`.
# See https://bjw-s-labs.github.io/helm-charts/docs/app-template/ for the full schema.

app-template:
  secrets:
    sabnzbd:
      stringData:
        apiKey: apiKey
        nzbKey: nzbKey
        newsreaderServerPassword: password123

  configMaps:
    config:
      data:
        sabnzbd.ini: |
          [misc]
          language = en
          queue_limit = 20
          port = 8080
          api_key = $apiKey
          nzb_key = $nzbKey
          download_dir = Downloads/incomplete
          complete_dir = Downloads/complete
          host_whitelist =
          # [servers]
          # [[yournewsreader.example.org]]
          # name = yournewsreader.example.org
          # displayname = yourNewsReader
          # host = yournewsreader.example.org
          # port = 563
          # username = username
          # password = $newsreaderServerPassword
          # connections = 8
          # ssl = 1
          # ssl_verify = 2
          # enable = 1
          # priority = 0

  controllers:
    main:
      initContainers:
        prepare-config:
          image:
            repository: alpine
            tag: "3.20"
          command: ["/bin/sh"]
          args:
            - -c
            - |
              sed \
                -e "s/\$apiKey/$apiKey/g" \
                -e "s/\$nzbKey/$nzbKey/g" \
                -e "s/\$newsreaderServerPassword/$newsreaderServerPassword/g" \
                /config-map/sabnzbd.ini > /config-processed/sabnzbd.ini
          env:
            apiKey:
              valueFrom:
                secretKeyRef:
                  name: sabnzbd
                  key: apiKey
            nzbKey:
              valueFrom:
                secretKeyRef:
                  name: sabnzbd
                  key: nzbKey
            newsreaderServerPassword:
              valueFrom:
                secretKeyRef:
                  name: sabnzbd
                  key: newsreaderServerPassword
      containers:
        main:
          image:
            repository: lscr.io/linuxserver/sabnzbd
            tag: "4.5.3"
          env:
            PGID: "1000"
            PUID: "1000"
          ports:
            - name: http
              containerPort: 8080
        metrics:
          enabled: true
          image:
            repository: ghcr.io/onedr0p/exportarr
            tag: v1.6.1
          args:
            - sabnzbd
          env:
            PORT: "9707"
            URL: "http://localhost:8080/sabnzbd"
            APIKEY:
              valueFrom:
                secretKeyRef:
                  name: sabnzbd
                  key: apiKey
          ports:
            - name: monitoring
              containerPort: 9707
          probes:
            liveness:
              enabled: true
              type: HTTP
              path: /healthz
              port: monitoring
            readiness:
              enabled: true
              type: HTTP
              path: /healthz
              port: monitoring
          resources:
            requests:
              cpu: 100m
              memory: 64Mi
            limits:
              cpu: 500m
              memory: 256Mi

  service:
    main:
      controller: main
      ports:
        http:
          port: 8080
        monitoring:
          enabled: true
          port: 9707

  serviceMonitor:
    main:
      enabled: true
      endpoints:
        - port: monitoring
          interval: 4m
          scrapeTimeout: 90s
          path: /metrics

  ingress:
    main:
      enabled: true
      className: ""
      annotations: {}
      hosts:
        - host: media-servarr.local
          paths:
            - path: /sabnzbd
              pathType: Prefix
              service:
                identifier: main
                port: http

  persistence:
    config:
      type: persistentVolumeClaim
      forceRename: sabnzbd-config
      accessMode: ReadWriteOnce
      size: 1Gi
      globalMounts:
        - path: /config
    raw-config:
      type: configMap
      identifier: config
      advancedMounts:
        main:
          prepare-config:
            - path: /config-map
    processed-config:
      type: emptyDir
      advancedMounts:
        main:
          prepare-config:
            - path: /config-processed
          main:
            - path: /config/sabnzbd.ini
              subPath: sabnzbd.ini
    downloads:
      type: emptyDir
      globalMounts:
        - path: /config/Downloads
```

- [ ] **Step 3: Delete stale templates**

```bash
git rm -r charts/sabnzbd/templates
```

- [ ] **Step 4: Render and validate**

```bash
nix develop --command bash -c '
  helm dependency update charts/sabnzbd
  helm template sabnzbd charts/sabnzbd --namespace media-servarr
' > /dev/null && echo "RENDER OK"
```

Confirm the rendered manifests include the metrics container, the `monitoring` service port, and the ServiceMonitor **enabled by default** (unlike the other 5 charts in this rollout) — this is intentional, not a bug, per this chart's existing behavior.

Old-schema scratch values (`.../scratchpad/sabnzbd-old-values.yaml`):

```yaml
secrets:
  - name: apiKey
    value: example-not-a-real-api-key
  - name: nzbKey
    value: example-not-a-real-nzb-key
  - name: newsreaderServerPassword
    value: example-not-a-real-password
persistentVolumeClaims:
  sabnzbd-config:
    storageClassName: ceph-block
```

New-schema scratch values (`.../scratchpad/sabnzbd-new-values.yaml`):

```yaml
app-template:
  secrets:
    sabnzbd:
      stringData:
        apiKey: example-not-a-real-api-key
        nzbKey: example-not-a-real-nzb-key
        newsreaderServerPassword: example-not-a-real-password
  persistence:
    config:
      storageClass: ceph-block
    data-pv:
      type: custom
      volumeSpec:
        persistentVolumeClaim:
          claimName: data-pv
      globalMounts:
        - path: /data
```

```bash
nix develop --command bash -c './scripts/diff-chart-render.sh sabnzbd <old-ref> HEAD /tmp/claude-1000/-home-martin-Documents-projects-media-servarr/6831eeb5-b965-48a0-9f0d-300bda72c578/scratchpad/sabnzbd-old-values.yaml /tmp/claude-1000/-home-martin-Documents-projects-media-servarr/6831eeb5-b965-48a0-9f0d-300bda72c578/scratchpad/sabnzbd-new-values.yaml'
```

Confirm PVC `metadata.name: sabnzbd-config`, matching namespace/accessModes/size/storageClass. Clean up the scratch file afterward.

- [ ] **Step 5: Rewrite `charts/sabnzbd/README.md`**

Follow `charts/radarr/README.md`'s structure, substituting:
- Radarr → Sabnzbd, port 8080, ingress path `/sabnzbd`
- Secrets: **three** entries — `app-template.secrets.sabnzbd.stringData.{apiKey,nzbKey,newsreaderServerPassword}`
- Application Configuration: `app-template.configMaps.config.data['sabnzbd.ini']` with sabnzbd's content from Step 2 — note this is an INI file, not XML
- Volumes: **config** (PVC `sabnzbd-config`) and **downloads** (`emptyDir`, mounted at `/config/Downloads` — call out that this path is intentionally nested under `/config`, matching the app's own expected layout)
- Metrics section: note explicitly that metrics are **enabled by default** for this chart (unlike the others), still with the same three-toggle mechanism if a user wants to disable them
- Migration: PVC name `sabnzbd-config`

- [ ] **Step 6: Commit**

```bash
git add charts/sabnzbd
git commit -m "$(cat <<'EOF'
Convert sabnzbd chart to bjw-s/app-template

Same pattern as the radarr pilot, adapted for three secrets needing
substitution (apiKey, nzbKey, newsreaderServerPassword) and metrics
enabled by default (matching this chart's existing behavior, unlike
the other converted charts). Config PVC keeps its literal name
(sabnzbd-config) via forceRename.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 6: Convert `charts/sonarr`

**Files:**
- Modify: `charts/sonarr/Chart.yaml`, `charts/sonarr/values.yaml`, `charts/sonarr/README.md`
- Delete: `charts/sonarr/templates/application.yaml`, `charts/sonarr/templates/NOTES.txt`

**Context:** Structurally identical to radarr, with `downloads` and `tv` emptyDir volumes instead of `downloads`/`film`. `appVersion` stays `4.0.15`.

- [ ] **Step 1: Rewrite `charts/sonarr/Chart.yaml`**

```yaml
apiVersion: 'v2'
name: 'sonarr'
description: 'Television series manager for Usenet and BitTorrent users'
home: 'https://github.com/drinkataco/media-servarr/tree/main/charts/sonarr'
keywords:
  - 'tv'
  - 'television'
  - 'series'
  - 'torrent'
  - 'bittorrent'
  - 'usenet'
  - 'manager'
  - 'sonarr'
kubeVersion: ">=1.28.0-0"
type: 'application'
version: 1.0.0
appVersion: 4.0.15
icon: 'https://github.com/drinkataco/media-servarr/blob/main/charts/sonarr/icon.png'
dependencies:
  - name: 'app-template'
    version: '5.0.1'
    repository: 'https://bjw-s-labs.github.io/helm-charts'
maintainers:
  - name: 'media-servarr'
    email: 'git@jo.shw.al'
    url: 'https://github.com/drinkataco/media-servarr/'
sources:
  - 'https://github.com/Sonarr/Sonarr'
  - 'https://github.com/linuxserver/docker-sonarr'
  - 'https://ghcr.io/onedr0p/exportarr'
  - 'https://github.com/drinkataco/media-servarr/tree/main/charts/sonarr'
```

- [ ] **Step 2: Rewrite `charts/sonarr/values.yaml`**

```yaml
# Default values for the sonarr chart. app-template is a Helm chart
# *dependency* here (see Chart.yaml), not the chart being installed directly —
# Helm only passes a subchart the slice of these values nested under a key
# matching the subchart's name. Everything below therefore lives under
# `app-template:`.
# See https://bjw-s-labs.github.io/helm-charts/docs/app-template/ for the full schema.

app-template:
  secrets:
    sonarr:
      stringData:
        apiKey: ''

  configMaps:
    config:
      data:
        config.xml: |
          <Config>
              <LogLevel>info</LogLevel>
              <EnableSsl>False</EnableSsl>
              <Port>8989</Port>
              <UrlBase>sonarr</UrlBase>
              <BindAddress>*</BindAddress>
              <ApiKey>$apiKey</ApiKey>
              <AnalyticsEnabled>False</AnalyticsEnabled>
              <AuthenticationMethod>External</AuthenticationMethod>
              <UpdateMechanism>Docker</UpdateMechanism>
              <Branch>main</Branch>
              <InstanceName>Sonarr</InstanceName>
            </Config>

  controllers:
    main:
      initContainers:
        prepare-config:
          image:
            repository: alpine
            tag: "3.20"
          command: ["/bin/sh"]
          args:
            - -c
            - |
              sed -e "s/\$apiKey/$apiKey/g" /config-map/config.xml > /config-processed/config.xml
          env:
            apiKey:
              valueFrom:
                secretKeyRef:
                  name: sonarr
                  key: apiKey
      containers:
        main:
          image:
            repository: lscr.io/linuxserver/sonarr
            tag: "4.0.15"
          env:
            PGID: "1000"
            PUID: "1000"
          ports:
            - name: http
              containerPort: 8989
        metrics:
          enabled: false
          image:
            repository: ghcr.io/onedr0p/exportarr
            tag: v1.6.1
          args:
            - sonarr
          env:
            PORT: "9706"
            URL: "http://localhost:8989/sonarr"
            APIKEY:
              valueFrom:
                secretKeyRef:
                  name: sonarr
                  key: apiKey
          ports:
            - name: monitoring
              containerPort: 9706
          probes:
            liveness:
              enabled: true
              type: HTTP
              path: /healthz
              port: monitoring
            readiness:
              enabled: true
              type: HTTP
              path: /healthz
              port: monitoring
          resources:
            requests:
              cpu: 100m
              memory: 64Mi
            limits:
              cpu: 500m
              memory: 256Mi

  service:
    main:
      controller: main
      ports:
        http:
          port: 8989
        monitoring:
          enabled: false
          port: 9706

  serviceMonitor:
    main:
      enabled: false
      endpoints:
        - port: monitoring
          interval: 4m
          scrapeTimeout: 90s
          path: /metrics

  ingress:
    main:
      enabled: true
      className: ""
      annotations: {}
      hosts:
        - host: media-servarr.local
          paths:
            - path: /sonarr
              pathType: Prefix
              service:
                identifier: main
                port: http

  persistence:
    config:
      type: persistentVolumeClaim
      forceRename: sonarr-config
      accessMode: ReadWriteOnce
      size: 1Gi
      globalMounts:
        - path: /config
    raw-config:
      type: configMap
      identifier: config
      advancedMounts:
        main:
          prepare-config:
            - path: /config-map
    processed-config:
      type: emptyDir
      advancedMounts:
        main:
          prepare-config:
            - path: /config-processed
          main:
            - path: /config/config.xml
              subPath: config.xml
    downloads:
      type: emptyDir
      globalMounts:
        - path: /downloads
    tv:
      type: emptyDir
      globalMounts:
        - path: /tv
```

- [ ] **Step 3: Delete stale templates**

```bash
git rm -r charts/sonarr/templates
```

- [ ] **Step 4: Render and validate**

```bash
nix develop --command bash -c '
  helm dependency update charts/sonarr
  helm template sonarr charts/sonarr --namespace media-servarr
' > /dev/null && echo "RENDER OK"
```

Old-schema scratch values (`.../scratchpad/sonarr-old-values.yaml`):

```yaml
secrets:
  - name: apiKey
    value: example-not-a-real-api-key
persistentVolumeClaims:
  sonarr-config:
    storageClassName: ceph-block
```

New-schema scratch values (`.../scratchpad/sonarr-new-values.yaml`):

```yaml
app-template:
  secrets:
    sonarr:
      stringData:
        apiKey: example-not-a-real-api-key
  persistence:
    config:
      storageClass: ceph-block
    data-pv:
      type: custom
      volumeSpec:
        persistentVolumeClaim:
          claimName: data-pv
      globalMounts:
        - path: /data
```

```bash
nix develop --command bash -c './scripts/diff-chart-render.sh sonarr <old-ref> HEAD /tmp/claude-1000/-home-martin-Documents-projects-media-servarr/6831eeb5-b965-48a0-9f0d-300bda72c578/scratchpad/sonarr-old-values.yaml /tmp/claude-1000/-home-martin-Documents-projects-media-servarr/6831eeb5-b965-48a0-9f0d-300bda72c578/scratchpad/sonarr-new-values.yaml'
```

Confirm PVC `metadata.name: sonarr-config`, matching namespace/accessModes/size/storageClass. Clean up the scratch file afterward. Note: the homelab's real `sonarr-values.yaml` also sets `serviceAccount.create: true` with `imagePullSecrets: [{name: github-private}]` — this maps to `app-template.global.imagePullSecrets` on the new schema, not a per-chart default; no change needed in this chart's own `values.yaml` for that (it's a deployment-time override, out of scope for the chart's defaults, same as radarr's pilot).

- [ ] **Step 5: Rewrite `charts/sonarr/README.md`**

Follow `charts/radarr/README.md`'s structure, substituting:
- Radarr → Sonarr, port 8989, ingress path `/sonarr`
- Secrets: `app-template.secrets.sonarr.stringData.apiKey`
- Application Configuration: `app-template.configMaps.config.data['config.xml']` with sonarr's content from Step 2
- Volumes: **config** (PVC `sonarr-config`), **downloads**, **tv** (both `emptyDir`)
- Metrics: port `9706`
- Migration: PVC name `sonarr-config`

- [ ] **Step 6: Commit**

```bash
git add charts/sonarr
git commit -m "$(cat <<'EOF'
Convert sonarr chart to bjw-s/app-template

Same pattern as the radarr pilot. Config PVC keeps its literal name
(sonarr-config) via forceRename.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>
EOF
)"
```

---

## After this plan

All 7 charts (radarr + these 6) are now on bjw-s/app-template. Remaining rollout-plan steps from the design spec: retire `media-servarr-base`'s templates/dependency wiring (nothing depends on it anymore — confirm with `grep -rl media-servarr-base charts/`), then a final `helm lint`/`helm template` pass across every chart plus the root chart.
