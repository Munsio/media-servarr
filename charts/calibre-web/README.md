# Calibre-Web Helm Chart

This Helm chart installs Calibre-Web, a web app for browsing, reading, and downloading eBooks stored in a Calibre database, in a Kubernetes cluster.

This README covers the basics of customising and installation

![Calibre-Web](./icon.png)

<!-- vim-md-toc format=bullets ignore=^TODO$ -->
* [Installation](#installation)
* [Configuration](#configuration)
  * [A note on values structure](#a-note-on-values-structure)
  * [Environment Variables](#environment-variables)
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

helm install calibre-web media-servarr/calibre-web
```

Pointing the host `media-servarr.local` to your kubernetes cluster will then allow you to access the application at the default location of `http://media-servarr.local/calibre-web/`

On first login, Calibre-Web needs the path to a Calibre library *inside the container* (see [Volumes](#volumes)) — point it at `/books` and, if the directory is empty, let it create a new library there.

## Configuration

Here is some example of some configuration you may want to override (and include in installation with `-f myvalues.yaml`

### A note on values structure

This chart depends on [bjw-s's app-template](https://bjw-s-labs.github.io/helm-charts/docs/app-template/) as a subchart rather than being that chart directly. Because of that, every app-template value — in this chart's own `values.yaml` and in any override file you write — must be nested under a top-level `app-template:` key, as shown in every example below.

### Environment Variables

`PUID`/`PGID` are set by default (see `app-template.controllers.main.containers.main.env` in `./values.yaml`). Two optional upstream variables are not set by default and can be added the same way if you need them:

```yaml
app-template:
  controllers:
    main:
      containers:
        main:
          env:
            PUID: "1000"
            PGID: "1000"
            # Adds ebook-conversion support (x86-64 only)
            DOCKER_MODS: linuxserver/mods:universal-calibre
            # Allows Google OAuth to work
            OAUTHLIB_RELAX_TOKEN_SCOPE: "1"
```

### Volumes

Two user-facing persistence items are defined:

- **config** - Calibre-Web's own settings and app database, backed by a PersistentVolumeClaim named `calibre-web-config`
- **books** - Your Calibre library (plain `emptyDir` by default — override this, it isn't meant to be left as-is)

```yaml
app-template:
  persistence:
    config:
      type: persistentVolumeClaim
      forceRename: calibre-web-config
      accessMode: ReadWriteOnce
      size: 1Gi
      storageClass: your-storage-class
    books:
      type: custom
      volumeSpec:
        nfs:
          server: fileserver.local
          path: /srv/media/books/
```

To point at a PVC that already exists and that this chart should never create or manage (e.g. a large shared media volume provisioned elsewhere), use a `type: custom` entry with a raw `volumeSpec` instead:

```yaml
app-template:
  persistence:
    books:
      type: custom
      volumeSpec:
        persistentVolumeClaim:
          claimName: my-existing-pvc
      globalMounts:
        - path: /books
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
            - path: /calibre-web
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
helm upgrade calibre-web media-servarr/calibre-web -f myvalues.yaml
```

## Uninstallation

To uninstall/delete the `calibre-web` deployment:

```bash
helm uninstall calibre-web
```

## Support

For support, issues, or feature requests, please file an issue on the chart's repository issue tracker.
