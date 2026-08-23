# Audiobookshelf Helm Chart

This Helm chart installs Audiobookshelf, a self-hosted audiobook and podcast server, in a Kubernetes cluster.

This README covers the basics of customising and installation

![Audiobookshelf](./icon.png)

<!-- vim-md-toc format=bullets ignore=^TODO$ -->
* [Installation](#installation)
* [Configuration](#configuration)
  * [A note on values structure](#a-note-on-values-structure)
  * [Volumes](#volumes)
  * [Ingress](#ingress)
  * [Advanced](#advanced)
* [Upgrading](#upgrading)
* [Uninstallation](#uninstallation)
* [Support](#support)
<!-- vim-md-toc END -->

## Installation

Install this helm chart using the following command:

```bash
helm repo add media-servarr https://munsio.github.io/media-servarr/

helm install audiobookshelf media-servarr/audiobookshelf
```

Pointing the host `media-servarr.local` to your kubernetes cluster will then allow you to access the application at the default location of `http://media-servarr.local/audiobookshelf/`

## Configuration

Here is some example of some configuration you may want to override (and include in installation with `-f myvalues.yaml`

### A note on values structure

This chart depends on [bjw-s's app-template](https://bjw-s-labs.github.io/helm-charts/docs/app-template/) as a subchart rather than being that chart directly. Because of that, every app-template value — in this chart's own `values.yaml` and in any override file you write — must be nested under a top-level `app-template:` key, as shown in every example below.

Note that, unlike most other charts in this repository, the upstream Audiobookshelf image does not support `PUID`/`PGID` environment variables — [see the official docs](https://audiobookshelf.org/docs/documentation/install/docker/) if you need it to run as a specific user, via `app-template.controllers.main.pod.securityContext`.

### Volumes

Four user-facing persistence items are defined:

- **config** - Audiobookshelf's own settings and app database, backed by a PersistentVolumeClaim named `audiobookshelf-config`
- **metadata** - Downloaded covers, metadata, and cache, backed by a PersistentVolumeClaim named `audiobookshelf-metadata`
- **audiobooks** - Location of your audiobook library (plain `emptyDir` by default)
- **podcasts** - Location of your podcast library (plain `emptyDir` by default)

```yaml
app-template:
  persistence:
    config:
      type: persistentVolumeClaim
      forceRename: audiobookshelf-config
      accessMode: ReadWriteOnce
      size: 1Gi
      storageClass: your-storage-class
    metadata:
      type: persistentVolumeClaim
      forceRename: audiobookshelf-metadata
      accessMode: ReadWriteOnce
      size: 1Gi
      storageClass: your-storage-class
    audiobooks:
      type: custom
      volumeSpec:
        nfs:
          server: fileserver.local
          path: /srv/media/audiobooks/
    podcasts:
      type: custom
      volumeSpec:
        nfs:
          server: fileserver.local
          path: /srv/media/podcasts/
```

To point at a PVC that already exists and that this chart should never create or manage (e.g. a large shared media volume provisioned elsewhere), use a `type: custom` entry with a raw `volumeSpec` instead:

```yaml
app-template:
  persistence:
    audiobooks:
      type: custom
      volumeSpec:
        persistentVolumeClaim:
          claimName: my-existing-pvc
      globalMounts:
        - path: /audiobooks
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
            - path: /audiobookshelf
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

## Upgrading

To upgrade the deployment:

```bash
helm upgrade audiobookshelf media-servarr/audiobookshelf -f myvalues.yaml
```

## Uninstallation

To uninstall/delete the `audiobookshelf` deployment:

```bash
helm uninstall audiobookshelf
```

## Support

For support, issues, or feature requests, please file an issue on the chart's repository issue tracker.
