# Convert media-servarr charts to bjw-s app-template

## Context

Every chart under `charts/<app>/` currently depends on the in-repo
`media-servarr-base` library chart (root of this repo), which hand-rolls
Deployment/Service/Ingress/PersistentVolumeClaim/ConfigMap/Secret/
ServiceMonitor/ServiceAccount templates behind a single
`application`/`deployment`/`persistentVolumeClaims`/... values schema.

The maintainer runs these charts live today via a separate GitOps repo
(`~/Documents/projects/homelab/kubernetes/servarr`), as an umbrella `servarr`
chart depending on 8 of these app charts (sabnzbd, prowlarr, sonarr, radarr,
jellyfin, jellyseerr, bazarr, readarr), each with a values override supplying
real storage classes, a shared NFS-backed `data-pv` PVC, custom images, and
ingress/TLS config. That override repo is the reference used to validate this
migration, but is **not** modified as part of this work.

## Goals

- Replace the custom `media-servarr-base` templating layer with bjw-s's
  `app-template` chart as a direct dependency of every app chart.
- Preserve the existing per-app `values.yaml` *behavior* (config templating
  with secret substitution, PVC layout, ingress, metrics sidecar) as closely
  as the new schema allows.
- Guarantee that any existing installation — the maintainer's live cluster,
  or any other user of the published chart repo — can `helm upgrade` onto
  the new chart version without losing data bound to existing PVCs.
- Validate the migration concretely via `helm template` diffs against real
  production values, not by assertion.

## Non-goals

- Migrating the homelab GitOps repo's values files to the new schema (left
  to the maintainer as a documented follow-up).
- Changing application behavior, image sources, or adding new features
  beyond what's needed for the schema conversion.

## Architecture

Each `charts/<app>/Chart.yaml` drops its dependency on
`media-servarr-base` and instead depends on:

```yaml
dependencies:
  - name: app-template
    version: "5.0.1" # latest stable release as of this writing
    repository: "https://bjw-s-labs.github.io/helm-charts"
```

`charts/<app>/values.yaml` is rewritten to app-template's schema:
`controllers.main.containers.main.*`, `service.main.*`, `ingress.main.*`,
`persistence.*`, `serviceAccount.*`. No custom templates remain in the app
charts. The exportarr metrics sidecar (currently a second container in the
Deployment template) becomes a second entry under
`controllers.main.containers`; the ServiceMonitor is app-template's native
`serviceMonitor` block.

The root `media-servarr-base` chart's templates and dependency wiring are
removed once no app chart references it (final step, after all 13 charts are
converted).

## Config-file templating (secret substitution)

app-template has no built-in equivalent of the current
ConfigMap+Secret → `sed` → file pattern used to bake API keys (and, in
production, autofs mount files like `data-hdd.nfs`/`auto.master`) into
config files before the main container starts. This is reimplemented as a
custom `initContainers` entry under `controllers.main`, functionally
identical to today's `prepare-config` init container: mount the rendered
ConfigMap(s) and Secret env vars, `sed`-substitute, write to a shared
`emptyDir`, mount that into the main container via `advancedMounts` with
`subPath`.

The per-app values keep the same list-of-objects shape for config entries
(`filename`, `contents`, `secrets`, `mountPath`) so translating an existing
override file is close to mechanical.

## Persistence & data-safety strategy

This is the core constraint of the whole migration.

**Current behavior:** each app's `config` PVC is created with a literal,
hardcoded name in that app's own `values.yaml` (e.g. `radarr-config`,
`jellyfin-config`) — never derived from the Helm release name. This name is
stable and identical across any install of a given chart.

**New behavior:** set `persistence.config.forceRename: '<app>-config'` in
each app's default `values.yaml` (app-template v5's field for pinning a
resource's exact generated name, confirmed against the real v5.0.1 chart —
older docs call this `nameOverride`/`existingClaim`, which do not exist in
the current schema). This makes app-template create (or, on upgrade, patch
in place) a PVC with the **exact same literal name** the old chart used.
Because namespace+name are unchanged, `helm upgrade` treats it as the same
object — same bound PV, zero data loss — with no manual override required.
Fresh installs get the same familiar name as before.

Non-config volumes (downloads/film/tv/music/ebooks, or an external shared
claim like the homelab's `data-pv`, which the parent umbrella chart creates
and owns — not this chart) keep today's behavior: unset by default
(→ `emptyDir`), overridable per-deployment via a `type: custom` persistence
entry with a raw `volumeSpec`, e.g.:

```yaml
persistence:
  data-pv:
    type: custom
    volumeSpec:
      persistentVolumeClaim:
        claimName: data-pv
    globalMounts:
      - path: /data
```

This is the exact equivalent of today's
`deployment.volumes.<key>.persistentVolumeClaim.claimName` override — the
chart never creates or manages this PVC, it just mounts it by literal name.

**Edge case:** anyone who previously overrode a PVC's key/claim name away
from the chart default needs to set `persistence.config.forceRename`
explicitly to their actual PVC name after upgrading (or switch it to a
`type: custom` entry if they want the chart to never manage it at all).
This is called out in each chart's README migration note.

### Validation methodology (pilot chart)

For the radarr pilot: render the **old** chart with the homelab's real
`radarr-values.yaml` as override, render the **new** chart with the
translated-equivalent override, and diff the two manifest sets — specifically
confirming the PersistentVolumeClaim object's `kind`/`namespace`/`metadata.name`/
`spec` match (or that any difference is additive/non-breaking, e.g. labels).
This is done read-only against a copy of the homelab values; the homelab repo
itself is not modified.

## Versioning

Each converted chart gets a major version bump (breaking values-schema
change per semver). Each chart's README gets a short "Migrating from vN"
section covering the PVC-name edge case above.

## Tooling

This is a NixOS environment with no ambient `helm`/`kubectl`/`dasel`. A
`flake.nix` devShell is added at the repo root providing these three tools
for local linting, templating, and validation work (`nix develop`).

As a small, independent prerequisite: `scripts/update_base.sh` and
`scripts/update_appversion.sh` currently call `yq` (mikefarah syntax)
directly. These are ported to `dasel` so the flake doesn't need to carry
both YAML-processing tools. This is unrelated to the app-template migration
itself but is bundled in since it unblocks removing `yq` from the toolchain.

## Rollout plan

1. Add `flake.nix`; port `update_base.sh`/`update_appversion.sh` to `dasel`.
2. Convert `charts/radarr` fully to the app-template-based schema.
3. Run the `helm template` diff validation described above against the
   homelab's real `radarr-values.yaml`.
4. Review findings with the maintainer; adjust the pattern if needed.
5. Once the pattern is signed off, mechanically apply it to the remaining
   12 charts (bazarr, cleanuparr, flaresolverr, homarr, huntarr, jellyfin,
   lidarr, prowlarr, readarr, sabnzbd, sonarr, transmission).
6. Retire `media-servarr-base`'s templates/dependency wiring.
7. `helm lint` + `helm template` across all charts as a final pass (existing
   `Makefile` targets are schema-agnostic and need no changes).

## Out of scope / deferred

- Migrating `~/Documents/projects/homelab/kubernetes/servarr` values files
  to the new schema — the maintainer will do this separately, using the
  per-chart README migration notes as a guide.
