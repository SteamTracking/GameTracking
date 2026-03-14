## Game Tracker

Tracking things, so you don't have to.

This repository contains shared tooling and scripts used by the individual game tracking repositories. Game updates are processed entirely via GitHub Actions using a [reusable workflow](/.github/workflows/gametracking.yml).

### How it works

Each game has its own repository (e.g. [GameTracking-Dota2](https://github.com/SteamTracking/GameTracking-Dota2), [GameTracking-CS2](https://github.com/SteamTracking/GameTracking-CS2)) which contains:
- `.github/workflows/update.yml` - workflow that calls the reusable workflow in this repository.
- `files.json` - a mapping of depot ids and which files to download from them.
- `update.sh` - the script that runs when the game is updated.

When a game update is detected, the game repository's workflow calls the reusable workflow in this repository, which checks out both repos, builds the tools, downloads the relevant game files using [SteamFileDownloader](https://github.com/SteamTracking/SteamFileDownloader) based on the game's `files.json`, and runs the game's `update.sh`.

SteamFileDownloader is a lightweight depot downloader that downloads files normally, but for pak01 VPKs it only downloads the chunks actually needed to export the requested file extensions.

### Shared tooling

- [`common.sh`](/common.sh) - common functions for dumping protobufs, processing VPKs, fixing encodings, and creating commits.
- [`tools/build.sh`](/tools/build.sh) - builds the required tools (available as submodules). Requires .NET, Go, and CMake.

Supports both Linux and Windows runners.

### Legacy games

Some older games (hl2, portal, l4d, etc.) still have their `update.sh` scripts directly in this repository.
