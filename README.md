# media-servarr helm charts

[![Lint](https://github.com/Munsio/media-servarr/actions/workflows/lint.yaml/badge.svg)](https://github.com/Munsio/media-servarr/actions/workflows/lint.yaml)
[![Chart page](https://github.com/Munsio/media-servarr/actions/workflows/chart-page.yaml/badge.svg)](https://github.com/Munsio/media-servarr/actions/workflows/chart-page.yaml)

![media-servarr](./icon.png)

This repository contains a collection of similar applications under the [servarr](https://wiki.servarr.com/) family, and some other useful related applications.

The aim of this repository is to be featureful, use repeatable code, and to be a testbed for me to play with a kubernetes helm chart.

<!-- vim-md-toc format=bullets ignore=^TODO$ -->
* [Usage](#usage)
* [The Charts](#the-charts)
* [Acknowledgements](#acknowledgements)
<!-- vim-md-toc END -->

## Usage

Add the repository using:

```bash
helm repo add media-servarr https://munsio.github.io/media-servarr/
```

And then view all available charts with

```bash
helm search repo media-servarr
```

## The Charts

There are a number of charts available under the [./charts](./charts) - each with indiviual README instructions to help you get started.

- Audiobookshelf - [audiobookshelf.org](https://audiobookshelf.org/)
- Bazarr - [bazarr.media](https://www.bazarr.media/)
- Jellyfin - [jellyfin.org](https://jellyfin.org/)
- Prowlarr - [prowlarr.com](https://prowlarr.com/)
- Radarr - [radarr.video](https://radarr.video/)
- Readarr [DEPRECATED] - [readarr.com](https://readarr.com/)
- Sabnzbd - [sabnzbd.org](https://sabnzbd.org/)
- Sonarr - [sonarr.tv](https://sonarr.tv/)

## Acknowledgements

This repository is a fork of [drinkataco/media-servarr](https://github.com/drinkataco/media-servarr), created by [@drinkataco](https://github.com/drinkataco). The original project laid the groundwork for every chart here - the app-template conventions, the per-app structure, and a lot of the design decisions this fork still builds on. Thank you for the great starting point.

Since forking, this repository has diverged quite a bit (different default branch, Dependabot-driven updates, some charts dropped, others reworked), so it's maintained here as its own thing rather than staying in sync with upstream. If you're looking for the actively maintained original, or a wider set of charts, go check it out:

- Repo: [github.com/drinkataco/media-servarr](https://github.com/drinkataco/media-servarr)
- Charts: [drinkataco.github.io/media-servarr](https://drinkataco.github.io/media-servarr/)
