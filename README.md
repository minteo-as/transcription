# Transskribering af optagelser med whisper.cpp på Mac

Scripts og en guide til at transskribere lange lydoptagelser (forelæsninger, møder, interviews) lokalt på en Mac med Apple Silicon. Alt kører på din egen maskine med [whisper.cpp](https://github.com/ggml-org/whisper.cpp), så ingen lyd forlader computeren.

Repoet indeholder tre scripts:

| Script | Gør |
| --- | --- |
| `install_whisper.sh` | Bygger og installerer whisper.cpp, henter modellerne og laver CoreML-encoderen. |
| `update_whisper.sh` | Opdaterer whisper.cpp til nyeste udgivelse, når der kommer en. |
| `transcribe_chunks.sh` | Transskriberer en lydfil til en tekstfil med tidsstempler. |

## Sådan virker det

- **whisper.cpp** bygges fra kildekoden med CoreML (Apple Neural Engine) og Metal (GPU) og installeres i `/usr/local`.
- **Modellen** er `large-v3-turbo`, som er hurtig og giver gode resultater på dansk og andre europæiske sprog.
- **VAD** (Silero voice activity detection) springer stilhed over, så Whisper ikke "hallucinerer" tekst i pauser.
- **`transcribe_chunks.sh`** deler lydfilen op i bidder på 5 minutter, transskriberer dem én ad gangen og samler resultatet i én tekstfil. Opdelingen gør, at en lang optagelse ikke fylder hele hukommelsen, og at du kan følge med i fremdriften undervejs.

## Forudsætninger

- En Mac med Apple Silicon (M1 eller nyere).
- **Xcode** fra App Store. Den fulde Xcode er nødvendig, fordi Command Line Tools ikke indeholder `coremlc`, som bruges til at lave CoreML-encoderen. Åbn Xcode én gang og accepter licensen, og kør derefter:

  ```sh
  sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
  xcrun --find coremlc   # skal udskrive en sti
  ```

- **Homebrew** fra [brew.sh](https://brew.sh). Installationsscriptet henter selv `git`, `cmake`, `ffmpeg` og `python@3.11` via Homebrew.

## Hurtig start

```sh
git clone https://github.com/minteo-as/transcription.git
cd transcription
./install_whisper.sh
```

Scriptet spørger efter dit password én gang, når whisper.cpp installeres i `/usr/local`. Første kørsel tager typisk 15–30 minutter, mest fordi modellen på ca. 1,6 GB skal hentes og CoreML-encoderen skal genereres.

Scriptet kan køres igen uden problemer. Trin, der allerede er gjort, springes over.

Transskriber derefter en optagelse:

```sh
./transcribe_chunks.sh optagelse.m4a optagelse.txt ~/models/whisper/ggml-large-v3-turbo.bin 300 da "Kort beskrivelse af optagelsen med centrale fagudtryk og navne."
```

## Transskribering

```sh
./transcribe_chunks.sh <lydfil> <output.txt> <model.bin> [sekunder_pr_bid] [sprog] [prompt]
```

| Argument | Standard | Beskrivelse |
| --- | --- | --- |
| `lydfil` | | Alle formater, som `ffmpeg` kan læse: m4a, mp3, wav, mp4 osv. |
| `output.txt` | | Den færdige transskription. Overskrives, hvis den findes. |
| `model.bin` | | Stien til ggml-modellen, fx `~/models/whisper/ggml-large-v3-turbo.bin`. |
| `sekunder_pr_bid` | `300` | Længden på hver bid. 5 minutter er et godt kompromis. |
| `sprog` | `auto` | Sprogkode som `da`, `en` eller `de`. Angiv altid sproget, hvis du kender det. Med `auto` ignoreres prompten. |
| `prompt` | tom | En kort tekst, der hjælper modellen med stavning af fagudtryk og navne. Se nedenfor. |

Output ser sådan ud, med en overskrift for hver bid:

```
===== CHUNK 1 | 00:00:00 -> 00:05:00 =====
...tekst...

===== CHUNK 2 | 00:05:00 -> 00:10:00 =====
...tekst...
```

Mellemfilerne (wav-bidder og tekst pr. bid) gemmes i `<lydfil>_chunks_work/` ved siden af lydfilen og kan slettes bagefter.

### Lyd fra en video

Scriptet kan læse videofiler direkte (mp4, mov, mkv osv.), fordi `ffmpeg` selv trækker lydsporet ud. Du behøver altså ikke konvertere først. Vil du alligevel have en ren lydfil, fx fordi videoen fylder mange gigabyte eller skal deles, er der to veje:

**Med QuickTime Player** (følger med macOS):

1. Åbn videoen i QuickTime Player.
2. Vælg **Fil → Eksporter som → Kun lyd**.
3. Gem filen. Resultatet er en `.m4a`-fil, som scriptet kan bruge direkte.

**Med ffmpeg** i Terminal, som kopierer lydsporet uden at genkode det og derfor er færdig på få sekunder:

```sh
ffmpeg -i video.mp4 -vn -c:a copy lyd.m4a
```

Brokker `ffmpeg` sig over formatet, fx ved en `.mkv`-fil med et lydspor, som ikke kan ligge i `.m4a`, så lad den genkode i stedet:

```sh
ffmpeg -i video.mkv -vn -c:a aac -b:a 128k lyd.m4a
```

Skærmoptagelser fra QuickTime, Zoom og Teams gemmes typisk som `.mov` eller `.mp4` og kan bruges på samme måde.

### Skriv en god prompt

Whisper bruger prompten som kontekst for, hvad der sandsynligvis bliver sagt. Det forbedrer stavningen af specialiserede ord markant, især ord, der sjældent optræder i almindelig tale. En god prompt er en eller to sætninger, der nævner:

- emnet for optagelsen
- fagudtryk, forkortelser og navne, der sandsynligvis bliver sagt
- hvordan optagelsen foregår, fx at der stilles spørgsmål undervejs

Eksempel fra en forelæsning:

```
Forelæsning i rekonstruktions- og insolvensprocesret. Emner omfatter konkursloven, rekonstruktionsbehandling, tvangsakkord, omstødelse og fristdagen. Studerende stiller spørgsmål undervejs.
```

Eksempel fra et møde:

```
Statusmøde i udviklingsteamet om release 2.4. Deltagere: Mette, Jonas og Sara. Der tales om Kubernetes, PostgreSQL og CI-pipelinen.
```

Skriv en ny prompt til hver optagelse. Har du slides eller en dagsorden, er det et godt udgangspunkt.

### Lad en AI skrive prompten ud fra slides

Det hurtigste er at lade Claude, ChatGPT eller en anden AI-assistent trække fagudtrykkene ud af slides, en dagsorden eller et pensum. Sådan gør du:

1. Vedhæft slides til samtalen (PowerPoint og PDF kan uploades direkte), eller kopier teksten ind.
2. Indsæt instruktionen nedenfor.
3. Kopier svaret ind som sidste argument til `transcribe_chunks.sh`.

Instruktion til AI-assistenten:

```
Jeg skal transskribere en optagelse med Whisper og har brug for en kontekstprompt, der hjælper modellen med at stave fagudtryk og navne rigtigt. Vedhæftet er slides fra optagelsen.

Skriv en prompt på dansk på højst 3-4 sætninger og under 150 ord, som:
- starter med en sætning om, hvad optagelsen handler om
- nævner de 10-20 vigtigste fagudtryk, forkortelser og egennavne fra slides, stavet præcis som de skal stå i transskriptionen
- slutter med en sætning om formen, fx at det er en forelæsning med spørgsmål fra salen

Skriv prompten som almindelig løbende tekst uden punktopstilling, overskrifter eller forklaringer. Svar kun med selve prompten.
```

Tjek svaret, før du bruger det:

- **Hold den kort.** Whisper læser kun de sidste ca. 220 tokens af prompten, hvilket svarer til omkring 150 danske ord. Alt derudover ignoreres.
- **Fjern det, der ikke bliver sagt.** Sidetal, kildehenvisninger og lange lovcitater fylder uden at hjælpe.
- **Tilføj det, AI'en ikke kan vide.** Navne på underviser og deltagere, øgenavne for begreber, og ord der ofte bliver stavet forkert.

Bruger du samme AI-samtale til flere optagelser i samme fag, kan du bede den genbruge de faste fagudtryk og kun tilføje de nye emner.

## Fra transskription til noter

Transskriptionen er rå tale med fyldord, gentagelser og enkelte stavefejl. Sammen med slides er den til gengæld et godt grundlag for, at en AI-assistent kan skrive strukturerede noter. Slides giver strukturen og de korrekte begreber, transskriptionen giver forklaringerne, eksemplerne og det, der blev sagt mellem linjerne.

1. Vedhæft både `output.txt` og slides til samtalen.
2. Indsæt instruktionen nedenfor, og tilpas listen over, hvad noterne skal indeholde.
3. Læs noterne igennem med slides ved siden af, og bed om rettelser, hvor noget mangler eller er forkert.

Instruktion til AI-assistenten:

```
Vedhæftet er en transskription af en optagelse og de slides, der blev brugt. Transskriptionen er automatisk genereret og kan indeholde stavefejl og fyldord. Slides er den pålidelige kilde til begreber og struktur.

Skriv noter på dansk, der følger slides' rækkefølge og overskrifter. For hvert emne:
- forklar begrebet med egne ord, som det blev forklaret i optagelsen
- medtag de eksempler, der blev givet mundtligt, også dem der ikke står på slides
- noter, hvad underviseren fremhævede som vigtigt, eller som ofte misforstås
- medtag spørgsmål fra deltagerne og svarene på dem, hvis de tilføjer noget

Markér med [uklart] de steder, hvor transskriptionen er for utydelig til at være sikker. Tilføj ikke viden, som hverken findes i slides eller transskriptionen. Afslut med en liste over begreber, der blev nævnt i optagelsen, men ikke står på slides.
```

Tips:

- **Hold tidsstemplerne.** Hver bid i `output.txt` starter med `===== CHUNK n | 00:10:00 -> 00:15:00 =====`. Bed AI'en henvise til dem, så du hurtigt kan finde stedet i optagelsen, hvis noget skal tjekkes.
- **Del lange optagelser op.** En optagelse på tre timer giver typisk 20.000–30.000 ord, hvilket kan være mere, end én samtale håndterer godt. Del `output.txt` ved chunk-overskrifterne, fx én time ad gangen, og bed til sidst om en samlet oversigt.
- **Bed om flere formater.** Når noterne er på plads, kan samme samtale lave et resumé på en side, flashcards med spørgsmål og svar, eller en liste over øvelsesspørgsmål.
- **Brug samme samtale gennem et forløb.** Vedhæfter du noterne fra forrige gang, kan AI'en henvise tilbage til dem og markere, hvor de nye emner bygger videre på de gamle.
- **Stol på slides ved uenighed.** Ser du en forskel mellem noterne og slides, er transskriptionen oftest skyld i det. Slå efter i optagelsen ved tidsstemplet, før du retter.

## Hvor filerne ligger

Scriptene bruger disse stier som standard. Alle kan ændres med en miljøvariabel, fx `MODELS_DIR=/Volumes/Data/whisper ./install_whisper.sh`.

| Variabel | Standard | Indhold |
| --- | --- | --- |
| `WHISPER_DIR` | `~/Downloads/whisper.cpp` | Kildekoden til whisper.cpp. Bruges af install og update. |
| `MODELS_DIR` | `~/models/whisper` | Modeller og CoreML-encoder. |
| `COREML_VENV` | `~/whisper-coreml311` | Python-miljøet, der bruges til at generere CoreML-encoderen. |
| `MODEL` | `large-v3-turbo` | Hvilken Whisper-model der hentes. |
| `VAD_MODEL` | `<samme mappe som model.bin>/ggml-silero-v6.2.0.bin` | VAD-modellen, som `transcribe_chunks.sh` bruger. |

Efter installationen indeholder `~/models/whisper/`:

```
ggml-large-v3-turbo.bin              # selve modellen (ca. 1,6 GB)
ggml-large-v3-turbo-encoder.mlmodelc/  # CoreML-encoder til Neural Engine
ggml-silero-v6.2.0.bin               # VAD-model
```

## Opdatering

```sh
./update_whisper.sh
```

Scriptet sammenligner den installerede version med den seneste udgivelse på GitHub og bygger kun, hvis der er en nyere. Med `--force` bygges og installeres der igen uanset version. Modellerne og CoreML-encoderen genbruges.

## Fejlfinding

**Første transskribering hænger i flere minutter.** Det er normalt. macOS kompilerer CoreML-modellen til Neural Engine første gang, den bruges. Efterfølgende kørsler starter på få sekunder.

**`failed to load Core ML model`.** whisper.cpp er bygget med CoreML og kræver derfor, at encoderen `ggml-<model>-encoder.mlmodelc/` ligger ved siden af modelfilen. Kør `./install_whisper.sh` igen, så laver den encoderen, hvis den mangler.

**`coremlc ikke fundet`.** Command Line Tools er ikke nok. Installer den fulde Xcode, åbn den én gang, og kør kommandoen under Forudsætninger.

**Python-fejl ved generering af CoreML-encoderen.** Encoderen laves med `torch` og `coremltools`, som ofte ikke virker med de nyeste Python-versioner. Scriptet bruger derfor Python 3.11 fra Homebrew i et separat miljø, som ikke påvirker din øvrige Python-installation.

**Tekst i pauser eller gentagne sætninger.** Tjek, at VAD-modellen findes, og at sproget er angivet. Prøv eventuelt kortere bidder, fx `120` sekunder.

## Manuel opsætning

Det her er, hvad `install_whisper.sh` gør, hvis du hellere vil gøre det selv.

### 1. Hent og byg whisper.cpp

```sh
git clone https://github.com/ggml-org/whisper.cpp.git
cd whisper.cpp
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
whisper-cli --version   # fx "whisper.cpp version: 1.9.5"
```

Vil du springe CoreML over, så fjern `-DWHISPER_COREML=1` og spring trin 3 over. Transskriberingen bliver lidt langsommere, men kører stadig på GPU'en via Metal.

### 2. Hent modellerne

Fra `whisper.cpp`-mappen:

```sh
mkdir -p ~/models/whisper
./models/download-ggml-model.sh large-v3-turbo ~/models/whisper
./models/download-vad-model.sh silero-v6.2.0 ~/models/whisper
```

### 3. Lav CoreML-encoderen

Encoderen skal laves én gang pr. model. Opret et Python 3.11-miljø med konverteringsværktøjerne:

```sh
brew install python@3.11
python3.11 -m venv ~/whisper-coreml311
source ~/whisper-coreml311/bin/activate
pip install -r models/requirements-coreml.txt   # fra whisper.cpp-mappen
```

Generer encoderen fra `whisper.cpp`-mappen, og kopier den over til modellen:

```sh
./models/generate-coreml-model.sh large-v3-turbo
cp -R models/ggml-large-v3-turbo-encoder.mlmodelc ~/models/whisper/
deactivate
```

### 4. Opdater manuelt

Fra `whisper.cpp`-mappen:

```sh
git fetch --tags
git checkout v1.9.6   # erstat med den nyeste
cmake --build build -j --config Release
sudo cmake --install build
```

Indstillingerne huskes i `build`-mappen, så `cmake -B build …` behøver ikke køres igen. Modellerne og CoreML-encoderen skal heller ikke laves igen.
