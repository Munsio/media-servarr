# SABnzbd Helm Chart

This Helm chart installs SABnzbd, a program to download binary files from Usenet servers.

This README covers the basics of customising and installation

![SABnzbd](./icon.png)

<!-- vim-md-toc format=bullets ignore=^TODO$ -->
* [Installation](#installation)
* [Configuration](#configuration)
  * [A note on values structure](#a-note-on-values-structure)
  * [Secrets](#secrets)
  * [Application Configuration](#application-configuration)
  * [Volumes](#volumes)
  * [Ingress](#ingress)
  * [Metrics](#metrics)
  * [Advanced](#advanced)
* [Migrating from v0.x to v1.0.0](#migrating-from-v0x-to-v100)
* [Upgrading](#upgrading)
* [Uninstallation](#uninstallation)
* [Support](#support)
<!-- vim-md-toc END -->

## Installation

Install this helm chart using the following command:

```bash
helm repo add mediar-servarr https://media-servarr.shw.al/charts

helm install sabnzbd media-servarr/sabnzbd
```

Pointing the host `media-servarr.local` to your kubernetes cluster will then allow you to access the application at the default location of `http://media-servarr.local/sabnzbd/`

## Configuration

Here is some example of some configuration you may want to override (and include in installation with `-f myvalues.yaml`

### A note on values structure

This chart depends on [bjw-s's app-template](https://bjw-s-labs.github.io/helm-charts/docs/app-template/) as a subchart rather than being that chart directly. Because of that, every app-template value — in this chart's own `values.yaml` and in any override file you write — must be nested under a top-level `app-template:` key, as shown in every example below.

### Secrets

To set up secrets, like API keys, use the following format. Use `openssl rand -hex 16` to generate a key and replace the default value.

```yaml
app-template:
  secrets:
    sabnzbd:
      stringData:
        apiKey: 'your-api-key-here'
        nzbKey: 'your-nzb-key-here'
        newsreaderServerPassword: 'your-newsreader-password-here'
```

Unlike some of the other charts in this collection, SABnzbd needs all three of these substituted into its config: an `apiKey` and `nzbKey` for the web UI/API, plus a `newsreaderServerPassword` for the commented-out example `[servers]` block below.

### Application Configuration

The base `sabnzbd.ini` is defined as a ConfigMap in `app-template.configMaps.config.data` in `./values.yaml`. Note this is an INI file, not XML or YAML. You can override the contents in your own values file, for example to configure a newsreader server:

```yaml
app-template:
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
          [servers]
          [[yournewsreader.example.org]]
          name = yournewsreader.example.org
          displayname = yourNewsReader
          host = yournewsreader.example.org
          port = 563
          username = username
          password = $newsreaderServerPassword
          connections = 8
          ssl = 1
          ssl_verify = 2
          enable = 1
          priority = 0
```

The rendered config is regenerated from this ConfigMap (with `$apiKey`, `$nzbKey`, and `$newsreaderServerPassword` all substituted from the Secret above) on every pod start via an init container — it is not stored on the persistent `config` volume.

### Volumes

Two user-facing persistence items are defined:

- **config** - General config data (where `sabnzbd.ini` and SABnzbd's own state live), backed by a PersistentVolumeClaim named `sabnzbd-config`
- **downloads** - Downloads folder for monitoring (plain `emptyDir` by default), mounted at `/config/Downloads` — nested under `/config` intentionally, matching SABnzbd's own expected directory layout (see `download_dir`/`complete_dir` in the config above, both relative to `Downloads/`)

(`values.yaml` also defines `raw-config` and `processed-config`, two additional internal entries used purely to render `sabnzbd.ini` via the init container described above — they aren't meant to be configured directly.)

```yaml
app-template:
  persistence:
    config:
      type: persistentVolumeClaim
      forceRename: sabnzbd-config
      accessMode: ReadWriteOnce
      size: 1Gi
      storageClass: your-storage-class
    downloads:
      type: custom
      volumeSpec:
        nfs:
          server: fileserver.local
          path: /srv/downloads/
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
            - path: /sabnzbd
              pathType: Prefix
              service:
                identifier: main
                port: http
      tls:
        - hosts: ['example.com']
          secretName: example-com-tls
```

### Metrics

Unlike every other chart in this collection, metrics are **enabled by default** here (matching this chart's existing behaviour) — attaching a sidecar container for [exportarr](https://github.com/onedr0p/exportarr/) and a ServiceMonitor CRD consumed by [kube-prometheus](https://github.com/prometheus-operator/kube-prometheus), out of the box with no extra configuration.

If you'd rather disable metrics, all three of the following toggles need to be set to `false`:

```yaml
app-template:
  controllers:
    main:
      containers:
        metrics:
          enabled: false
  service:
    main:
      ports:
        monitoring:
          enabled: false
  serviceMonitor:
    main:
      enabled: false
```

It is recommended to install the [kube-prometheus chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) first for the CRD to be supported. It is not included as a dependency by default in this package!

Metrics are served on port `9707`.

### Advanced

See the [bjw-s app-template documentation](https://bjw-s-labs.github.io/helm-charts/docs/app-template/) for the full set of available configuration, including `app-template.controllers.main.pod.nodeSelector`, `app-template.controllers.main.pod.tolerations`, `app-template.controllers.main.pod.affinity`, container ports, environment variables, and `serviceAccount`.

## Migrating from v0.x to v1.0.0

Version 1.0.0 replaces the chart's internal templating with [bjw-s's app-template](https://bjw-s-labs.github.io/helm-charts/docs/app-template/). The values schema is completely different — see the Configuration section above for the new shape.

**Your existing data is safe.** The `config` PersistentVolumeClaim keeps its exact original name (`sabnzbd-config`) by default, so a normal `helm upgrade` re-adopts the same PVC and bound volume without recreating it — no manual steps needed for a stock install.

If you previously renamed the config PVC away from the default (e.g. via a custom `persistentVolumeClaims` key), set `app-template.persistence.config.forceRename` to your actual PVC name after upgrading, or switch it to a `type: custom` entry (see Volumes above) if you'd rather the chart never manage that PVC's lifecycle at all.

If you configured custom `application.config` entries beyond the default `sabnzbd.ini` (e.g. additional files mounted at other paths), you'll need to translate them manually to `app-template.configMaps.config.data` plus a corresponding `app-template.controllers.main.initContainers.prepare-config` `sed` line for each file that references a secret — see the Application Configuration section above for the pattern.

Note also that every value in this chart now lives one level deeper than before, under a top-level `app-template:` key — see "A note on values structure" above.

Metrics were already enabled by default in the previous chart version, and remain enabled by default here — but disabling them now requires three separate toggles instead of one — see the Metrics section above.

## Upgrading

To upgrade the deployment:

```bash
helm upgrade sabnzbd media-servarr/sabnzbd -f myvalues.yaml
```

## Uninstallation

To uninstall/delete the `sabnzbd` deployment:

```bash
helm uninstall sabnzbd
```

## Support

For support, issues, or feature requests, please file an issue on the chart's repository issue tracker.
