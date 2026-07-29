#!/usr/bin/env bash
# Download the latest CI-built emacs-plus@32 bottle from this fork's fixed
# "emacs-plus-32-nightly" GitHub release and (re)install it.
#
# The bottle is built by .github/workflows/build-bottle.yml (nightly cron
# or manual `gh workflow run build-bottle.yml`).
set -euo pipefail

REPO="ryankask/homebrew-emacs-plus"
TAG="emacs-plus-32-nightly"
PATTERN="emacs-plus@32--*.bottle*.tar.gz"

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

echo "Downloading latest bottle from $REPO release '$TAG'..."
gh release download "$TAG" --repo "$REPO" --pattern "$PATTERN" --dir "$tmpdir" --clobber

bottle="$(echo "$tmpdir"/emacs-plus@32--*.bottle*.tar.gz)"
echo "Installing $bottle..."
if brew list --versions emacs-plus@32 >/dev/null 2>&1; then
  brew reinstall "$bottle"
else
  brew install "$bottle"
fi

echo "Verifying..."
"$(brew --prefix)/bin/emacs" --batch --eval='(print (emacs-version))'
