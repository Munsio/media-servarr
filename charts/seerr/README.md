# Seerr Helm Chart

This Helm chart installs [Seerr](https://github.com/seerr-team/seerr), a request management application for your media library and the unified successor to Overseerr and Jellyseerr.

This README covers the basics of customising and installation

![Seerr](./icon.png)

<!-- vim-md-toc format=bullets ignore=^TODO$ -->
* [Installation](#installation)
* [Configuration](#configuration)
  * [A note on values structure](#a-note-on-values-structure)
  * [A note on the container user](#a-note-on-the-container-user)
  * [No subpath support](#no-subpath-support)
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

helm install seerr media-servarr/seerr
```

Pointing the host `seerr.media-servarr.local` to your kubernetes cluster will then allow you to access the application at `http://seerr.media-servarr.local/`. All other one-time setup (connecting Plex/Jellyfin/Emby and Sonarr/Radarr) is done through Seerr's own onboarding wizard on first visit — there's no API key or config file to seed up front.

## Configuration

Here is some example of some configuration you may want to override (and include in installation with `-f myvalues.yaml`

### A note on values structure

This chart depends on [bjw-s's app-template](https://bjw-s-labs.github.io/helm-charts/docs/app-template/) as a subchart rather than being that chart directly. Because of that, every app-template value — in this chart's own `values.yaml` and in any override file you write — must be nested under a top-level `app-template:` key, as shown in every example below.

### A note on the container user

Unlike the linuxserver-based images used elsewhere in this repository, Seerr's official image runs as a fixed non-root user (uid/gid `1000`) and does not support `PUID`/`PGID` environment variables. `values.yaml` sets `app-template.controllers.main.pod.securityContext.fsGroup` and `app-template.controllers.main.containers.main.securityContext.runAsUser`/`runAsGroup` to `1000` accordingly, so the `config` volume is writable. If you need a different uid/gid, override all three consistently.

### No subpath support

Seerr does not yet support being served from a subpath behind a reverse proxy (see [seerr-team/seerr#97](https://github.com/seerr-team/seerr/issues/97)), so — unlike the other charts in this repository — the default ingress here uses its own host (`seerr.media-servarr.local`) at path `/` rather than a path under a shared host.

### Volumes

One user-facing persistence item is defined:

- **config** - General config data (where the sqlite database lives), backed by a PersistentVolumeClaim named `seerr-config`

```yaml
app-template:
  persistence:
    config:
      type: persistentVolumeClaim
      forceRename: seerr-config
      accessMode: ReadWriteOnce
      size: 1Gi
      storageClass: your-storage-class
```

To point at a PVC that already exists and that this chart should never create or manage, use a `type: custom` entry with a raw `volumeSpec` instead:

```yaml
app-template:
  persistence:
    config:
      type: custom
      volumeSpec:
        persistentVolumeClaim:
          claimName: my-existing-pvc
      globalMounts:
        - path: /app/config
```

### Ingress

Ingress can be enabled, and you can customise the default host, path, and TLS settings:

```yaml
app-template:
  ingress:
    main:
      enabled: true
      hosts:
        - host: requests.example.com
          paths:
            - path: /
              pathType: Prefix
              service:
                identifier: main
                port: http
      tls:
        - hosts: ['requests.example.com']
          secretName: requests-example-com-tls
```

### Advanced

See the [bjw-s app-template documentation](https://bjw-s-labs.github.io/helm-charts/docs/app-template/) for the full set of available configuration, including `app-template.controllers.main.pod.nodeSelector`, `app-template.controllers.main.pod.tolerations`, `app-template.controllers.main.pod.affinity`, container ports, environment variables, and `serviceAccount`.

## Upgrading

To upgrade the deployment:

```bash
helm upgrade seerr media-servarr/seerr -f myvalues.yaml
```

## Uninstallation

To uninstall/delete the `seerr` deployment:

```bash
helm uninstall seerr
```

## Support

For support, issues, or feature requests, please file an issue on the chart's repository issue tracker.
