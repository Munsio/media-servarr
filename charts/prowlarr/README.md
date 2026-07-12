# Prowlarr Helm Chart

This Helm chart installs Prowlarr, an indexer manager, in a Kubernetes cluster.

This README covers the basics of customising and installation

![Prowlarr](./icon.png)

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
* [Migrating from v1.0.x to v1.1.0](#migrating-from-v10x-to-v110)
* [Upgrading](#upgrading)
* [Uninstallation](#uninstallation)
* [Support](#support)
<!-- vim-md-toc END -->

## Installation

Install this helm chart using the following command:

```bash
helm repo add media-servarr https://munsio.github.io/media-servarr/

helm install prowlarr media-servarr/prowlarr
```

Pointing the host `media-servarr.local` to your kubernetes cluster will then allow you to access the application at the default location of `http://media-servarr.local/prowlarr/`

## Configuration

Here is some example of some configuration you may want to override (and include in installation with `-f myvalues.yaml`

### A note on values structure

This chart depends on [bjw-s's app-template](https://bjw-s-labs.github.io/helm-charts/docs/app-template/) as a subchart rather than being that chart directly. Because of that, every app-template value — in this chart's own `values.yaml` and in any override file you write — must be nested under a top-level `app-template:` key, as shown in every example below.

### Secrets

To set up secrets, like API keys, use the following format. Use `openssl rand -hex 16` to generate a key and replace the default value.

```yaml
app-template:
  secrets:
    prowlarr:
      stringData:
        apiKey: 'your-api-key-here'
```

By not setting this value, and leaving it blank, Prowlarr will automatically generate a key on start.

### Application Configuration

The base `config.xml` is defined as a ConfigMap in `app-template.configMaps.config.data` in `./values.yaml`. You can override the contents in your own values file, for example to change the URL base:

```yaml
app-template:
  configMaps:
    config:
      data:
        config.xml: |
          <Config>
            ...
            <UrlBase>prowlarr</UrlBase>
            <ApiKey>$apiKey</ApiKey>
            <Port>9696</Port>
            ...
          </Config>
```

The rendered config is regenerated from this ConfigMap (with `$apiKey` substituted from the Secret above) on every pod start via an init container — it is not stored on the persistent `config` volume.

### Volumes

One user-facing persistence item is defined:

- **config** - General config data (where the sqlite database lives), backed by a PersistentVolumeClaim named `prowlarr-config`

(`values.yaml` also defines `raw-config` and `processed-config`, two additional internal entries used purely to render `config.xml` via the init container described above — they aren't meant to be configured directly.)

```yaml
app-template:
  persistence:
    config:
      type: persistentVolumeClaim
      forceRename: prowlarr-config
      accessMode: ReadWriteOnce
      size: 1Gi
      storageClass: your-storage-class
```

To point at a PVC that already exists and that this chart should never create or manage (e.g. a large shared volume provisioned elsewhere), use a `type: custom` entry with a raw `volumeSpec` instead:

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
            - path: /prowlarr
              pathType: Prefix
              service:
                identifier: main
                port: http
      tls:
        - hosts: ['example.com']
          secretName: example-com-tls
```

### Metrics

Enabling metrics attaches a sidecar container for [exportarr](https://github.com/onedr0p/exportarr/) and a ServiceMonitor CRD consumed by [kube-prometheus](https://github.com/prometheus-operator/kube-prometheus). Unlike the previous chart version, this now needs three separate toggles:

```yaml
app-template:
  controllers:
    main:
      containers:
        metrics:
          enabled: true
  service:
    main:
      ports:
        monitoring:
          enabled: true
  serviceMonitor:
    main:
      enabled: true
```

It is recommended to install the [kube-prometheus chart](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack) first for the CRD to be supported. It is not included as a dependency by default in this package!

Metrics are served on port `9703`.

### Advanced

See the [bjw-s app-template documentation](https://bjw-s-labs.github.io/helm-charts/docs/app-template/) for the full set of available configuration, including `app-template.controllers.main.pod.nodeSelector`, `app-template.controllers.main.pod.tolerations`, `app-template.controllers.main.pod.affinity`, container ports, environment variables, and `serviceAccount`.

## Migrating from v0.x to v1.0.0

Version 1.0.0 replaces the chart's internal templating with [bjw-s's app-template](https://bjw-s-labs.github.io/helm-charts/docs/app-template/). The values schema is completely different — see the Configuration section above for the new shape.

**Your existing data is safe.** The `config` PersistentVolumeClaim keeps its exact original name (`prowlarr-config`) by default, so a normal `helm upgrade` re-adopts the same PVC and bound volume without recreating it — no manual steps needed for a stock install.

If you previously renamed the config PVC away from the default (e.g. via a custom `persistentVolumeClaims` key), set `app-template.persistence.config.forceRename` to your actual PVC name after upgrading, or switch it to a `type: custom` entry (see Volumes above) if you'd rather the chart never manage that PVC's lifecycle at all.

If you configured custom `application.config` entries beyond the default `config.xml` (e.g. additional files mounted at other paths), you'll need to translate them manually to `app-template.configMaps.config.data` plus a corresponding `app-template.controllers.main.initContainers.prepare-config` `sed` line for each file that references a secret — see the Application Configuration section above for the pattern.

Note also that every value in this chart now lives one level deeper than before, under a top-level `app-template:` key — see "A note on values structure" above.

Enabling metrics now requires three separate toggles instead of one — see the Metrics section above.

## Migrating from v1.0.x to v1.1.0

This version switches the underlying controller from a Deployment to a StatefulSet, to structurally eliminate a `Multi-Attach` error some users hit on the `config` PersistentVolumeClaim during upgrades (a Deployment's rolling update briefly runs the old and new pod at the same time, which conflicts with a `ReadWriteOnce` volume — see [drinkataco/media-servarr#136](https://github.com/drinkataco/media-servarr/issues/136)).

**Your data is unaffected.** The `prowlarr-config` PVC keeps its exact name and is mounted the same way — this change only affects how the pod is managed, not storage. Since Deployment and StatefulSet are different Kubernetes resource kinds, `helm upgrade` will delete the old Deployment and create a new StatefulSet, causing one extra pod restart during this specific upgrade — no different in effect from any routine version bump.

## Upgrading

To upgrade the deployment:

```bash
helm upgrade prowlarr media-servarr/prowlarr -f myvalues.yaml
```

## Uninstallation

To uninstall/delete the `prowlarr` deployment:

```bash
helm uninstall prowlarr
```

## Support

For support, issues, or feature requests, please file an issue on the chart's repository issue tracker.
