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

### Tools

Built by [`tools/build.sh`](/tools/build.sh). When a commit is pushed to this repository, CI builds the tools and uploads them to GitHub Releases. Game repositories download the pre-built tools from there.

Some tools live directly in this repo, others are included as submodules. Tools do not self-update. When a submodule tool is modified, its reference in this repository must be updated manually by running `git submodule update --remote` and pushing the result.

### Manually re-running a game update

Each game repository's update workflow can be triggered manually via [workflow dispatch](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/manually-run-a-workflow) in the GitHub UI. This is useful for re-processing a game update after fixing a tool. Note that the reusable workflow (`gametracking.yml`) in this repository is only called by game repos, it does not run directly here.

### Shared scripts

- [`common.sh`](/common.sh) - common functions for dumping protobufs, processing VPKs, fixing encodings, and creating commits.
- [`tools/build.sh`](/tools/build.sh) - builds the required tools (available as submodules). Requires .NET, Go, and CMake.
- [`.github/actions/commit-summary`](/.github/actions/commit-summary) - summarises each new game commit and posts it as a commit comment. It only runs when the `CLAUDE_CODE_OAUTH_TOKEN` secret is set.

Supports both Linux and Windows runners.
