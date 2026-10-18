#!/usr/bin/env bash
set -Eeuo pipefail

# Installerer whisper.cpp (seneste udgivelse) med CoreML og Metal, henter
# modellerne og laver CoreML-encoderen. Se README.md for detaljer.
#
# Usage:
#   ./install_whisper.sh
#
# Notes:
# - Kræver Apple Silicon, fuld Xcode og Homebrew
# - Kan køres igen: trin der allerede er gjort springes over
# - Spørger efter dit password til "sudo cmake --install"
# - Stier kan ændres med miljøvariablerne WHISPER_DIR, MODELS_DIR, COREML_VENV og MODEL

WHISPER_DIR="${WHISPER_DIR:-$HOME/Downloads/whisper.cpp}"
MODELS_DIR="${MODELS_DIR:-$HOME/models/whisper}"
COREML_VENV="${COREML_VENV:-$HOME/whisper-coreml311}"
MODEL="${MODEL:-large-v3-turbo}"
VAD_MODEL="silero-v6.2.0"

step() {
  echo
  echo "==> $*"
}

fail() {
  echo "Fejl: $*" >&2
  exit 1
}

latest_release_tag() {
  git -C "$WHISPER_DIR" tag --sort=-v:refname | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' | head -1
}

step "Tjekker forudsætninger"

[[ "$(uname -m)" == "arm64" ]] || fail "kræver en Mac med Apple Silicon (M1 eller nyere)"

xcrun --find coremlc >/dev/null 2>&1 || fail "coremlc ikke fundet. Installer Xcode fra App Store, åbn den én gang, og kør:
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer"

command -v brew >/dev/null 2>&1 || fail "Homebrew ikke fundet. Installer det fra https://brew.sh"

for formula in git cmake ffmpeg python@3.11; do
  if brew list --versions "$formula" >/dev/null 2>&1; then
    echo "$formula er installeret"
  else
    echo "Installerer $formula..."
    brew install "$formula"
  fi
done

PYTHON311="$(brew --prefix python@3.11)/bin/python3.11"

step "Henter whisper.cpp til $WHISPER_DIR"

if [[ -d "$WHISPER_DIR/.git" ]]; then
  echo "Findes allerede"
else
  git clone https://github.com/ggml-org/whisper.cpp.git "$WHISPER_DIR"
fi

git -C "$WHISPER_DIR" fetch --tags --quiet
TAG="$(latest_release_tag)"
[[ -n "$TAG" ]] || fail "kunne ikke finde en udgivelse (vX.Y.Z)"
echo "Seneste udgivelse: $TAG"
git -C "$WHISPER_DIR" -c advice.detachedHead=false checkout --quiet "$TAG"

step "Bygger whisper.cpp $TAG"

cd "$WHISPER_DIR"
cmake -B build \
  -DWHISPER_COREML=1 \
  -DWHISPER_BUILD_IS_DEV=OFF \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr/local \
  -DCMAKE_INSTALL_RPATH=/usr/local/lib
cmake --build build -j --config Release

step "Installerer i /usr/local (kræver dit password)"

sudo cmake --install build

step "Henter modeller til $MODELS_DIR"

mkdir -p "$MODELS_DIR"
./models/download-ggml-model.sh "$MODEL" "$MODELS_DIR"
./models/download-vad-model.sh "$VAD_MODEL" "$MODELS_DIR"

step "Laver CoreML-encoder til $MODEL"

ENCODER="ggml-${MODEL}-encoder.mlmodelc"

if [[ -d "$MODELS_DIR/$ENCODER" ]]; then
  echo "Findes allerede i $MODELS_DIR"
else
  if [[ ! -d "models/$ENCODER" ]]; then
    if [[ ! -x "$COREML_VENV/bin/python3" ]]; then
      echo "Opretter Python-miljø i $COREML_VENV..."
      "$PYTHON311" -m venv "$COREML_VENV"
      "$COREML_VENV/bin/pip" install --upgrade pip
      "$COREML_VENV/bin/pip" install ane_transformers openai-whisper coremltools
    fi
    echo "Genererer encoder (det tager et stykke tid)..."
    PATH="$COREML_VENV/bin:$PATH" ./models/generate-coreml-model.sh "$MODEL"
  fi
  cp -R "models/$ENCODER" "$MODELS_DIR/"
fi

step "Færdig"

echo "$(whisper-cli --version 2>&1 | head -1)"
echo "Modeller i $MODELS_DIR:"
ls -1 "$MODELS_DIR"
echo
echo "Første transskribering kan tage flere minutter at starte, mens macOS kompilerer CoreML-modellen."
echo "Kom i gang:"
echo "  ./transcribe_chunks.sh <lydfil> <output.txt> $MODELS_DIR/ggml-${MODEL}.bin 300 da \"<prompt>\""
