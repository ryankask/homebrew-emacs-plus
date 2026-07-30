# AGENTS.md

## What this repo is

Personal fork of [d12frosted/homebrew-emacs-plus](https://github.com/d12frosted/homebrew-emacs-plus)
(`ryankask/homebrew-emacs-plus`).

- Default branch is `nightly` — it carries the fork's bottle block and bot commits.
- `main` tracks upstream and stays free of bot commits so upstream merges stay clean.

## CI: only `build-bottle.yml` is used

The only active workflow is `.github/workflows/build-bottle.yml`. It builds the
`emacs-plus@32` (Emacs master) bottle on a nightly schedule and via
`workflow_dispatch`, uploads it to the fixed `emacs-plus-32-nightly` GitHub
release, and commits the updated bottle sha256 to the `nightly` branch.

All other workflows (e.g. `build-app.yml`, which produces per-run `cask-*`
releases) are unused inherited machinery — do not modify them or depend on
their outputs.

## The GitHub release is load-bearing

The formula's bottle block (in `Formula/emacs-plus@32.rb` on `nightly`) uses
the `emacs-plus-32-nightly` release as its `root_url`, and it is the only pour
channel (Workbrew blocks installing bottles from local files/URLs). Never
remove the release-upload steps from `build-bottle.yml`, and never delete the
`emacs-plus-32-nightly` release.

## Fork-only customizations

`Formula/emacs-plus@32.rb` carries fork-only patches, including the custom
`patches/emacs-32/ns-win.patch`, which removes Emacs's default Nextstep
super-key (`s-*`) bindings from `ns-win.el` so Command keys are free for user
configuration. If a patch file under `patches/` changes, its sha256 in the
formula's `local_patch` line must be updated to match.
