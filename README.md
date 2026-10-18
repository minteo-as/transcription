# Transskribering af juraforelæsninger med whisper.cpp

Denne guide beskriver, hvordan du sætter [whisper.cpp](https://github.com/ggml-org/whisper.cpp) op på din egen Mac og transskriberer optagelser af forelæsninger med `transcribe_chunks.sh`.

Opsætningen:

- **whisper.cpp** bygges fra kildekoden med CoreML (Apple Neural Engine) og Metal (GPU) og installeres i `/usr/local`.
- **Modellen** er `large-v3-turbo`, som er hurtig og god til dansk.
- **VAD** (Silero) springer stilhed over, så Whisper ikke "hallucinerer" tekst i pauser.
- **`transcribe_chunks.sh`** deler lydfilen op i bidder på 5 minutter, transskriberer dem én ad gangen og samler resultatet i én tekstfil med tidsstempler.

Alle modeller lægges i `~/models/whisper/`.

## Hurtig start

Når forudsætningerne i trin 1 er på plads, klarer `install_whisper.sh` trin 2–4:

```sh
./install_whisper.sh
```

Opdater senere til en ny udgivelse med:

```sh
./update_whisper.sh
```

Begge scripts kan køres igen uden problemer, og trin, der allerede er gjort, springes over. Resten af guiden beskriver, hvad scripts gør, hvis du vil gøre det manuelt.

---

## 1. Forudsætninger

Du skal bruge en Mac med Apple Silicon (M1 eller nyere).

1. **Xcode** fra App Store. Den fulde Xcode er nødvendig, fordi Command Line Tools ikke indeholder `coremlc`, som skal bruges i trin 4. Åbn Xcode én gang, og accepter licensen. Kør derefter:

   ```sh
   sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
   xcrun --find coremlc   # skal udskrive en sti
   ```

2. **Homebrew** fra [brew.sh](https://brew.sh), og derefter værktøjerne:

   ```sh
   brew install git cmake ffmpeg python@3.11
   ```

   Python 3.11 bruges kun til at lave CoreML-modellen i trin 4. Nyere Python-versioner virker ofte ikke med `torch` og `coremltools`.

---

## 2. Hent og byg whisper.cpp

```sh
cd ~/Downloads
git clone https://github.com/ggml-org/whisper.cpp.git
cd whisper.cpp
```

Skift til den nyeste udgivelse i stedet for udviklingsgrenen `master`:

```sh
git fetch --tags
git tag --sort=-v:refname | head -3   # vis de nyeste udgivelser
git checkout v1.9.5                   # erstat med den nyeste
```

Konfigurer, byg og installer:

```sh
cmake -B build \
  -DWHISPER_COREML=1 \
  -DWHISPER_BUILD_IS_DEV=OFF \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr/local \
  -DCMAKE_INSTALL_RPATH=/usr/local/lib

cmake --build build -j --config Release
sudo cmake --install build
```

Tjek, at det virker:

```sh
whisper-cli --version   # fx "whisper.cpp version: 1.9.5"
```

---

## 3. Hent modellerne

Kør fra `whisper.cpp`-mappen:

```sh
mkdir -p ~/models/whisper
./models/download-ggml-model.sh large-v3-turbo ~/models/whisper
./models/download-vad-model.sh silero-v6.2.0 ~/models/whisper
```

Resultatet er `ggml-large-v3-turbo.bin` (ca. 1,6 GB) og `ggml-silero-v6.2.0.bin` i `~/models/whisper/`.

---

## 4. Lav CoreML-encoderen

whisper.cpp er bygget med CoreML. Derfor **skal** der ligge en CoreML-encoder ved siden af modellen, ellers stopper `whisper-cli` med fejlen `failed to load Core ML model`. Encoderen skal laves én gang pr. model.

Opret et separat Python-miljø, og installer konverteringsværktøjerne:

```sh
python3.11 -m venv ~/whisper-coreml311
source ~/whisper-coreml311/bin/activate
pip install ane_transformers openai-whisper coremltools
```

Generer encoderen fra `whisper.cpp`-mappen, og kopier den over til modellen. Det tager et stykke tid:

```sh
./models/generate-coreml-model.sh large-v3-turbo
cp -R models/ggml-large-v3-turbo-encoder.mlmodelc ~/models/whisper/
deactivate
```

`~/models/whisper/` skal nu indeholde:

```
ggml-large-v3-turbo.bin
ggml-large-v3-turbo-encoder.mlmodelc/
ggml-silero-v6.2.0.bin
```

> Den første transskribering efter opsætningen kan tage flere minutter at gå i gang, fordi macOS kompilerer CoreML-modellen til Neural Engine. Efterfølgende kørsler starter hurtigt.

> Vil du springe CoreML over, så fjern `-DWHISPER_COREML=1` i trin 2 og spring dette trin over. Transskriberingen bliver lidt langsommere, men kører stadig på GPU'en via Metal.

---

## 5. Transskriber en forelæsning

Kør scriptet fra `JuraLyd`-mappen. Læg hver forelæsning i sin egen mappe (fx `26-09-2026/`).

```sh
./transcribe_chunks.sh <lydfil> <output.txt> <model.bin> [sekunder_pr_bid] [sprog] [prompt]
```

Eksempel:

```sh
./transcribe_chunks.sh \
  "26-09-2026/26-09.26 Rekonstruktions og Insolvensprocesret.m4a" \
  26-09-2026/output.txt \
  ~/models/whisper/ggml-large-v3-turbo.bin \
  300 da \
  "Forelæsning i rekonstruktions- og insolvensprocesret ved SDU. Emner omfatter konkursloven, rekonstruktionsbehandling, tvangsakkord, omstødelse og fristdagen."
```

- **`sekunder_pr_bid`** er som standard `300`, altså 5 minutter.
- **`sprog`**: angiv altid `da`. Standarden `auto` ignorerer prompten.
- **`prompt`** er en kort beskrivelse af forelæsningen med fagbegreber, lovforkortelser (KL, TL, KSL …) og navne på undervisere. Det forbedrer stavningen af juridiske termer markant. Skriv en ny prompt til hver forelæsning, fx ud fra slides.

Scriptet kræver, at `ffmpeg` og `whisper-cli` ligger i `PATH`. VAD-modellen skal ligge på stien `~/models/whisper/ggml-silero-v6.2.0.bin`.

Den færdige transskription skrives til `output.txt` med en overskrift for hver bid (`===== CHUNK 3 | 00:10:00 -> 00:15:00 =====`). Mellemfilerne (wav-bidder og tekst pr. bid) gemmes i `<filnavn>_chunks_work/` ved siden af lydfilen og kan slettes bagefter.

---

## Opdatering af whisper.cpp

Kør `./update_whisper.sh`. Scriptet sammenligner den installerede version med den seneste udgivelse og opdaterer kun, hvis der er en nyere. Med `--force` bygges og installeres der igen uanset version.

Manuelt fra `~/Downloads/whisper.cpp`:

```sh
git fetch --tags
git tag --sort=-v:refname | head -3   # find den nyeste udgivelse
git checkout v1.9.6                   # erstat med den nyeste
cmake --build build -j --config Release
sudo cmake --install build
whisper-cli --version
```

Indstillingerne fra trin 2 huskes i `build`-mappen, så du behøver ikke køre `cmake -B build …` igen. Modellerne og CoreML-encoderen skal heller ikke laves igen.
