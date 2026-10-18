#!/usr/bin/env bash
set -Eeuo pipefail

# Opdaterer whisper.cpp til seneste udgivelse, hvis der er en nyere end den
# installerede. Modeller og CoreML-encoder genbruges.
#
# Usage:
#   ./update_whisper.sh            # opdater hvis der er en nyere udgivelse
#   ./update_whisper.sh --force    # byg og installer igen uanset version
#
# Notes:
# - Forudsætter at install_whisper.sh er kørt
# - Spørger efter dit password til "sudo cmake --install"

WHISPER_DIR="${WHISPER_DIR:-$HOME/Downloads/whisper.cpp}"
FORCE="${1:-}"

fail() {
  echo "Fejl: $*" >&2
  exit 1
}

[[ -d "$WHISPER_DIR/.git" ]] || fail "whisper.cpp ikke fundet i $WHISPER_DIR. Kør install_whisper.sh først"

echo "Henter udgivelser..."
git -C "$WHISPER_DIR" fetch --tags --quiet
TAG="$(git -C "$WHISPER_DIR" tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1)"
[[ -n "$TAG" ]] || fail "kunne ikke finde en udgivelse (vX.Y.Z)"

INSTALLED="$(whisper-cli --version 2>/dev/null | sed -n 's/^whisper.cpp version: //p' || true)"

echo "Installeret:      ${INSTALLED:-ukendt}"
echo "Seneste udgivelse: ${TAG#v}"

if [[ "$INSTALLED" == "${TAG#v}" && "$FORCE" != "--force" ]]; then
  echo "Du har allerede den nyeste version."
  exit 0
fi

echo
echo "Opdaterer til $TAG..."
git -C "$WHISPER_DIR" -c advice.detachedHead=false checkout --quiet "$TAG"

cd "$WHISPER_DIR"
cmake -B build \
  -DWHISPER_COREML=1 \
  -DWHISPER_BUILD_IS_DEV=OFF \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr/local \
  -DCMAKE_INSTALL_RPATH=/usr/local/lib
cmake --build build -j --config Release

echo
echo "Installerer i /usr/local (kræver dit password)..."
sudo cmake --install build

echo
echo "Færdig: $(whisper-cli --version 2>&1 | head -1)"
