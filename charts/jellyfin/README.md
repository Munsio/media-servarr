# Jellyfin Helm Chart

This Helm chart installs Jellyfin, a web media system, in a Kubernetes cluster.

This README covers the basics of customising and installation

![Jellyfin](./icon.png)

<!-- vim-md-toc format=bullets ignore=^TODO$ -->
* [Installation](#installation)
* [Configuration](#configuration)
  * [A note on values structure](#a-note-on-values-structure)
  * [Application Configuration](#application-configuration)
  * [Volumes](#volumes)
  * [Ingress](#ingress)
  * [Advanced](#advanced)
* [Migrating from v0.x to v1.0.0](#migrating-from-v0x-to-v100)
* [Migrating from v1.0.x to v1.1.0](#migrating-from-v10x-to-v110)
* [Upgrading](#upgrading)
* [Uninstallation](#uninstallation)
* [Support](#support)
<!-- vim-md-toc END -->

## Installation

Install this helm chart using the following command:

```bash
helm repo add mediar-servarr https://media-servarr.shw.al/charts

helm install jellyfin media-servarr/jellyfin
```

Pointing the host `media-servarr.local` to your kubernetes cluster will then allow you to access the application at the default location of `http://media-servarr.local/jellyfin/`

## Configuration

Here is some example of some configuration you may want to override (and include in installation with `-f myvalues.yaml`

### A note on values structure

This chart depends on [bjw-s's app-template](https://bjw-s-labs.github.io/helm-charts/docs/app-template/) as a subchart rather than being that chart directly. Because of that, every app-template value — in this chart's own `values.yaml` and in any override file you write — must be nested under a top-level `app-template:` key, as shown in every example below.

### Application Configuration

The base `network.xml` is defined as a ConfigMap in `app-template.configMaps.config.data` in `./values.yaml`. You can override the contents in your own values file, for example to change the URL base:

```yaml
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
```

Unlike some of the other charts in this repository, Jellyfin's config has no `$placeholder` secret values to substitute, so this ConfigMap is mounted directly at `/config/config/network.xml` — there is no init container regenerating it on pod start.

### Volumes

Five user-facing persistence items are defined:

- **config** - General config data (where the sqlite database lives), backed by a PersistentVolumeClaim named `jellyfin-config`
- **ebooks** - Location of ebooks (plain `emptyDir` by default)
- **film** - Location of movies (plain `emptyDir` by default)
- **music** - Location of music (plain `emptyDir` by default)
- **television** - Location of TV shows (plain `emptyDir` by default)

(`values.yaml` also defines `raw-config`, an additional internal entry used purely to mount `network.xml` from the ConfigMap described above — it isn't meant to be configured directly.)

```yaml
app-template:
  persistence:
    config:
      type: persistentVolumeClaim
      forceRename: jellyfin-config
      accessMode: ReadWriteOnce
      size: 1Gi
      storageClass: your-storage-class
    ebooks:
      type: custom
      volumeSpec:
        nfs:
          server: fileserver.local
          path: /srv/media/ebooks/
    film:
      type: custom
      volumeSpec:
        nfs:
          server: fileserver.local
          path: /srv/media/film/
    music:
      type: custom
      volumeSpec:
        nfs:
          server: fileserver.local
          path: /srv/media/music/
    television:
      type: custom
      volumeSpec:
        nfs:
          server: fileserver.local
          path: /srv/media/tv/
```

To point at a PVC that already exists and that this chart should never create or manage (e.g. a large shared media volume provisioned elsewhere), use a `type: custom` entry with a raw `volumeSpec` instead:

```yaml
app-template:
  persistence:
    media:
      type: custom
      volumeSpec:
        persistentVolumeClaim:
          claimName: my-existing-pvc
      globalMounts:
        - path: /data
```

### Ingress

Ingress can be enabled, and you can customise the default host, path, and TLS settings:

```yaml
app-template:
  ingress:
    main:
      enabled: true
      hosts:
        - host: example.com
          paths:
            - path: /jellyfin
              pathType: Prefix
              service:
                identifier: main
                port: http
      tls:
        - hosts: ['example.com']
          secretName: example-com-tls
```

### Advanced

See the [bjw-s app-template documentation](https://bjw-s-labs.github.io/helm-charts/docs/app-template/) for the full set of available configuration, including `app-template.controllers.main.pod.nodeSelector`, `app-template.controllers.main.pod.tolerations`, `app-template.controllers.main.pod.affinity`, container ports, environment variables, and `serviceAccount`.

Jellyfin's own Prometheus metrics toggle (`<EnableMetrics>true</EnableMetrics>` in `system.xml`) is unrelated to this chart's schema and out of scope here — see the [official documentation](https://jellyfin.org/docs/general/networking/monitoring/) if you want to enable it.

## Migrating from v0.x to v1.0.0

Version 1.0.0 replaces the chart's internal templating with [bjw-s's app-template](https://bjw-s-labs.github.io/helm-charts/docs/app-template/). The values schema is completely different — see the Configuration section above for the new shape.

**Your existing data is safe.** The `config` PersistentVolumeClaim keeps its exact original name (`jellyfin-config`) by default, so a normal `helm upgrade` re-adopts the same PVC and bound volume without recreating it — no manual steps needed for a stock install.

If you previously renamed the config PVC away from the default (e.g. via a custom `persistentVolumeClaims` key), set `app-template.persistence.config.forceRename` to your actual PVC name after upgrading, or switch it to a `type: custom` entry (see Volumes above) if you'd rather the chart never manage that PVC's lifecycle at all.

If you configured custom `application.config` entries beyond the default `network.xml` (e.g. `system.xml` or `encoding.xml`), you'll need to translate them manually to `app-template.configMaps.config.data` plus a corresponding mount under `app-template.persistence.raw-config.advancedMounts` — see the Application Configuration section above for the pattern.

Note also that every value in this chart now lives one level deeper than before, under a top-level `app-template:` key — see "A note on values structure" above.

## Migrating from v1.0.x to v1.1.0

This version switches the underlying controller from a Deployment to a StatefulSet, to structurally eliminate a `Multi-Attach` error some users hit on the `config` PersistentVolumeClaim during upgrades (a Deployment's rolling update briefly runs the old and new pod at the same time, which conflicts with a `ReadWriteOnce` volume — see [drinkataco/media-servarr#136](https://github.com/drinkataco/media-servarr/issues/136)).

**Your data is unaffected.** The `jellyfin-config` PVC keeps its exact name and is mounted the same way — this change only affects how the pod is managed, not storage. Since Deployment and StatefulSet are different Kubernetes resource kinds, `helm upgrade` will delete the old Deployment and create a new StatefulSet, causing one extra pod restart during this specific upgrade — no different in effect from any routine version bump.

## Upgrading

To upgrade the deployment:

```bash
helm upgrade jellyfin media-servarr/jellyfin -f myvalues.yaml
```

## Uninstallation

To uninstall/delete the `jellyfin` deployment:

```bash
helm uninstall jellyfin
```

## Support

For support, issues, or feature requests, please file an issue on the chart's repository issue tracker.
