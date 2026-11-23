# dashsplat

dashsplat rebuilds the world around a car as an orbitable 3D scene from the six dashcam cameras of a Tesla: it
calibrates the cameras from the footage, fits Gaussian splats and a 1 cm road texture to the photographs, tracks the
other vehicles, and redraws the view from behind the car with a one-step image model. It was built in one day and
one night by a team of AI coding agents directed by Ryan Vogel, from one drive of his own Model 3 (HW4), and it is
slow, rough and tuned to that one car.

![The generated chase view at 112 s of the test drive in the web viewer](viewer/report-night/stills/112-generative.jpg)

*The test drive at 112 s in the web viewer, with the generated chase view. The same moment drawn from the splats
alone: [112-splat.jpg](viewer/report-night/stills/112-splat.jpg). The on-screen HUD imitates Tesla's display; see
[docs/NAMING.md](docs/NAMING.md).*

This is an independent hobby project. It is not affiliated with, endorsed by or sponsored by Tesla, Inc. The footage
it was built from is the author's own, recorded by his own car.

## Status

Work in progress, one day old. It has run on exactly one recording: a 6-minute, 3.3 km drive at dawn under
overcast sky (361.44 s, of which 249.53 s moving). Every number below comes from a report in this repository,
linked beside it. Those reports were written as the work happened, so they use the working name "Reality Splat",
refer to the author's machines ("the Studio" is his Mac Studio with an M5 Ultra, "basebook" his working Mac), and some
link to large videos and private folders (`out/`, `scratch/`) that are not included. [TIMELINE.md](TIMELINE.md)
lists every commit of the original history.

## What it does

| Stage | What it does | Result on the test drive |
|---|---|---|
| Ingest ([pipeline/ingest](pipeline/ingest/ingest.py)) | Decodes all six cameras and reads the telemetry Tesla embeds in every frame (speed, heading, GPS, steering, pedals, blinkers, driver-assist state); dead-reckons a trajectory | The dead-reckoned track ends 7.5 m from GPS after 3.3 km. The telemetry has no height, pitch or roll ([PLAN.md](PLAN.md)) |
| Calibration ([pipeline/calib](pipeline/calib/README.md)) | Solves each lens, its position on the car, clock offset and rolling shutter from the footage itself, with no factory data | Inlier reprojection error 0.81 to 0.97 px per lens; a held-out scale check came out 2.14 % off the telemetry, missing the 1 % goal ([report](pipeline/calib/REPORT.md)) |
| Poses ([pipeline/poses](pipeline/poses/README.md)) | A 6-degree-of-freedom trajectory for the whole drive from telemetry plus images | All 12,927 front-camera timestamps; whole-drive reprojection error 1.5 to 1.8 px. Points seen far ahead land tens of pixels off when the car arrives ([report](pipeline/poses/REPORT.md)) |
| Road ([pipeline/road](pipeline/road/README.md)) | Road-relative attitude and a bird's-eye mosaic, the base of the ground layer | 0 of 41 measured cells met their centimetre targets; final offline medians 9 to 14 cm ([report](pipeline/road/REPORT.md)) |
| Depth and masks ([pipeline/depth](pipeline/depth/README.md), [pipeline/masks](pipeline/masks/README.md)) | Metric depth from pose-conditioned models (Depth Anything 3, MapAnything) and sky, road and vehicle masks (Mask2Former) | Front camera: scale within 4 to 5 %, temporal error 1.8 % over 1 m of travel. Every monocular "metric" model tried was off by 15 to 70 % ([report](pipeline/depth/REPORT.md)) |
| Ground atlas ([pipeline/groundtex](pipeline/groundtex/README.md)) | The road as a photographic texture on a height mesh, one photograph per texel, every texel labelled observed or predicted | Road at 1 to 2 cm per texel, verges at 4 cm out to 40 m; 53.1 % of the ground within 40 m is predicted, not photographed ([report](pipeline/groundtex/REPORT-V6.md)) |
| Splat scenes ([pipeline/livemap](pipeline/livemap/README.md), [pipeline/stitch](pipeline/stitch/README.md)) | Trees, poles and buildings as Gaussian splats, fitted to the photographs and to "teacher" views re-projected from them | Published, "not ready for a side-by-side with Tesla's screen": crowns smear, traffic lights hang without arms, two named office buildings do not read as buildings. 4.08 million object splats in 85 to 140 s ([report](pipeline/stitch/REPORT-v5.md)) |
| Movers ([pipeline/movers](pipeline/movers/README.md)) | Each tracked vehicle as a rigid splat model moving along a smoothed track; the viewer draws clean stand-in models by default | 23 moving episodes and nine fixed models in the published scene; a bus passing behind trees is not readable ([report](pipeline/movers/report4/README.md)) |
| Generated chase view ([pipeline/genfill](pipeline/genfill/README.md)) | Renders the chase camera, then NVIDIA's Difix-ref redraws each frame from the render plus the nearest real photograph in one diffusion step; observed road paint is put back exactly and every pixel is labelled | 3,183 frames over 93 to 140, 190 to 215 and 296 to 330 s. Flicker below the real camera's; sky invented in about a quarter of each frame; signs come out as garbled text ([report](pipeline/genfill/REPORT.md), sections 11 to 13) |
| Viewer ([viewer](viewer/README.md)) | three.js and Spark in the browser: streams tiles, plays the drive back, Live, Stitched, Memory and Generative modes | 60 fps at 3200x2000 in Chrome on an Apple M5 Max ([viewer/README.md](viewer/README.md)) |
| One command ([pipeline/run](pipeline/run/README.md)) | Raw clips to a published scene, resumable, every stage checked | Preview tier for the whole drive, no manual step; full tier on a 30 s window and part of the whole drive |
| NVIDIA port ([pipeline/cuda](pipeline/cuda/README.md)) | The same command on Linux with CUDA, replacing the two Apple-only stages | Ran end to end on one rented L40S; not at parity with the Mac result (below) |

![Left: the first ground splats. Middle: the ground atlas at 1 cm. Right: one camera photograph](pipeline/groundtex/report/detail-lane.jpg)

*A lane line in the first ground splats, in the ground atlas, and in one front-camera photograph
([pipeline/groundtex/REPORT.md](pipeline/groundtex/REPORT.md)).*

Things that did not work are kept with their reports: showing re-projected photographs directly fails when depth is
wrong ([pipeline/ibr/REPORT.md](pipeline/ibr/REPORT.md); it became the teacher for the splats instead), a driving
video model (StreetNVS) moves the lane paint, with 9 of 73 checks within 3 px
([pipeline/genvideo/REPORT.md](pipeline/genvideo/REPORT.md)), and a sky map from the six cameras is 78 % invented
because no camera looks up ([pipeline/envmap/report/REPORT.md](pipeline/envmap/report/REPORT.md)).

## How long it takes

Stage time per minute of moving footage, from [pipeline/run/README.md](pipeline/run/README.md) (Mac Studio, M5
Ultra) and [pipeline/cuda/README.md](pipeline/cuda/README.md) (one NVIDIA L40S at $1.11 an hour with 13.6 CPU cores):

| Tier | M5 Ultra | L40S |
|---|---:|---:|
| Preview: ground splats, road atlas, automatic vehicle tracks | 13.6 min (whole drive) | 32.9 min, $0.61 |
| Full geometry: production depth and masks, vehicle removal, teacher views, splat fit | 51.9 min (first windows of the whole drive) | 82.9 min, $1.54 |
| Generated chase video, per minute of video | 85.7 to 102.1 min | 168.5 min, $3.12 |

On the 30-second proof window, preview plus full took 71 min 45 s of stage time per minute of driving on the M5
Ultra, about 70 times slower than the drive itself, with only 4 s of generated video. Everything on the L40S came
to about 4.7 compute hours and $5.27 per minute of driving. The L40S scene is not equivalent to the Mac scene of the
same window: 390,260 static-object splats against 1,439,423, and 69 vehicle tracks against 36, 17 of them shorter
than a second ([pipeline/cuda/README.md](pipeline/cuda/README.md)). These rates come from short windows and are not
a quote for longer drives.

## What it does not do

- **It is not real time.** It takes hours of compute per minute of driving (see above).
- **The generated view exists only from the chase camera.** Orbit more than about 2.3 degrees or zoom 9 % and the
  viewer fades back to the splats ([viewer/README.md](viewer/README.md), Generative mode).
- **Sky and signs are made up.** The clouds in generated frames are invented, and large signs come out as
  plausible-looking garbled text ([pipeline/genfill/REPORT.md](pipeline/genfill/REPORT.md)).
- **It knows one car.** The calibration, its masks and the thresholds of the rig check all come from one Model 3
  with HW4 cameras. Other models, HW3's four cameras, the Cybertruck's seven, night and rain are untested.
- **It needs telemetry in the footage.** The pipeline reads the SEI metadata Tesla writes into dashcam video on
  firmware 2025.44.25 or later, and since 2026.20 Tesla encrypts dashcam clips by default in most markets: decrypt
  them in the car or at dashcam.tesla.com first ([research/06-hugging-face.md](research/06-hugging-face.md)).
- **Vehicles are approximate.** Untracked cars stay as blobs in the static splats, parked cars are baked into the
  scene, and tracks split or appear briefly.
- **Rough edges everywhere.** Many scripts still assume the author's machines; see
  [Known rough edges](#known-rough-edges).

## Try it

### What you need

- **Footage:** a folder of six-camera clips (front, back, left and right pillar, left and right repeater) from one
  continuous drive, unencrypted, H.264 with the SEI telemetry, at the HW4 sizes (front 2896x1876, others
  1448x938), with the car moving most of the time.
- **A calibrated rig:** `calib/rig.json` and `calib/masks/` under the installation root. **This repository does
  not include one yet.** `pipeline/calib` solves one from footage, but its time windows and body masks were chosen
  by hand for the author's drive, so expect to adapt it.
- **A Mac** with Apple Silicon (built on an M5 Ultra with 96 GB; the image model peaks at about 14 GB of GPU memory),
  Python 3.12 with PyTorch on MPS, Homebrew's `ceres-solver` and `cmake`, the Xcode command-line tools (the
  vehicle check calls Apple Vision through Swift), Bun and FFmpeg. **Or** an x86-64 Linux machine with an NVIDIA GPU
  (measured on 48 GB L40S and A40 cards) and root, starting from NVIDIA's `nvcr.io/nvidia/pytorch:25.03-py3` image.
- **Disk:** the 30-second window kept about 15 GB of working files ([pipeline/cuda/PORT.md](pipeline/cuda/PORT.md),
  disk table), plus about 12 GB of model weights.

### On a Mac

[pipeline/run/setup-mac.sh](pipeline/run/setup-mac.sh) builds the same layout as the Linux script: it installs any
missing Homebrew packages ([Brewfile](Brewfile)), creates `.venv`, `envs/stitch` and `envs/genfill` with uv, clones
the pinned upstream code, builds the solvers, helpers, viewer and chase tool, and checks that PyTorch sees the GPU.
Add `--models` to download the pinned weights (about 12 GB; several are non-commercial). It was tested on an M3 Max
with 128 GB; the author's own environment was built up stage by stage, as each stage README describes.

1. Run `bash pipeline/run/setup-mac.sh --models` and put the rig in `calib/`.
2. Leave a local host running for the built viewer (the runner checks every publication through it):

   ```sh
   mkdir -p scene
   bun deploy/serve.ts viewer/dist scene 8090 127.0.0.1
   ```
3. Run the pipeline from the repository root:

   ```sh
   .venv/bin/python pipeline/run/drive.py run /path/to/clips --name my-drive                  # preview tier
   .venv/bin/python pipeline/run/drive.py run /path/to/clips --name my-drive --quality full   # everything
   .venv/bin/python pipeline/run/drive.py status --name my-drive
   ```

4. Open `http://127.0.0.1:8090/?scene=my-drive`.

Repeat the same command to resume after a crash or reboot. `--window T0 T1` limits the run to part of the drive,
`--clip none` skips generated video. The rest of the options are in [pipeline/run/README.md](pipeline/run/README.md).

### On an NVIDIA GPU

```sh
# in nvcr.io/nvidia/pytorch:25.03-py3, as root, from the repository root, with the rig in calib/ and clips in clips/
bash pipeline/cuda/setup-drive.sh
export RS_INSTALL=$PWD HF_HOME=$PWD/third_party/hf TORCH_HOME=$PWD/third_party/torch DIFIX_RENDER_ONLY_DECODE=1
.venv/bin/python pipeline/run/drive.py run clips --name my-drive --quality full
```

The setup script installs packages, builds the solvers, helpers and viewer, and downloads the models. On Linux the
runner starts its own private viewer on 127.0.0.1 to check its output; the scene is written to `scene/my-drive`.
Copy it to a machine running `deploy/serve.ts` to look at it.

### Where the models come from

From Hugging Face, at revisions pinned in the code. On Linux `pipeline/cuda/drive_models.py` prints each model's
licence line before it downloads anything. On a Mac each stage loads its models through its own loader or setup
script ([pipeline/depth](pipeline/depth/README.md), [pipeline/genfill/setup.sh](pipeline/genfill/setup.sh)); the
vehicle check uses Apple Vision, which ships with macOS. Nothing is uploaded anywhere: the whole pipeline runs on
your machine.

## Models and licences

The code in this repository is Apache-2.0. **That does not change the licence of any model it downloads, and
several of the default models are for non-commercial use only.** Using them, or the scenes and frames they help
make, is bound by their terms.

| Stage | Model | Licence | Commercial use |
|---|---|---|---|
| Masks | Mask2Former Swin-L, Cityscapes panoptic | MIT code; Cityscapes training data is non-commercial | Treat as no |
| Depth, all cameras in the runner | Depth Anything 3, DA3-LARGE-1.1 | The model card says Apache-2.0, the official README CC BY-NC 4.0 | Treat as no |
| Depth fallback | DA3METRIC-LARGE | Apache-2.0 | Yes |
| Depth, side cameras (depth stage default) | MapAnything | CC BY-NC 4.0 | No |
| Vehicle check, macOS | Apple Vision | Part of macOS | Not redistributable |
| Vehicle check, Linux | SigLIP 2 base | Apache-2.0 | Yes |
| Generated chase view | NVIDIA Difix-ref (on SD-Turbo) | NVIDIA License, research and non-commercial; Stability AI Community License | No |
| Ego car in the viewer | "2024 Tesla Model 3" by RBLXSupercars (the credit embedded in the file; the project's notes also recorded "Tesla model 3 2024" by brandonleong28) | CC BY 4.0, attribution required | The model yes, with credit; Tesla's design and marks are not licensed |

Experimental models, assets, fonts and libraries are listed with sources and pinned revisions in
[THIRD_PARTY.md](THIRD_PARTY.md). Permissive replacements and their cost in quality are compared in
[research/06-hugging-face.md](research/06-hugging-face.md) section 3.6.

## Repository map

| Path | What |
|---|---|
| [PLAN.md](PLAN.md) | The plan and the data contract every stage and the viewer share |
| `pipeline/` | One folder per stage, each with a README and its reports: `ingest`, `calib`, `poses`, `road`, `photo` (exposure), `depth`, `masks`, `livemap`, `stitch`, `groundtex`, `movers`, `ibr` (photographic views and teachers), `genfill` (image model), `genvideo` and `envmap` (experiments), `scene`, `common` (camera geometry) |
| [pipeline/run](pipeline/run/README.md) | The one command |
| [pipeline/cuda](pipeline/cuda/README.md) | The NVIDIA port, its setup script and its measurements |
| [viewer](viewer/README.md) | The web viewer and its tools (tile cache, shot capture for the film) |
| `deploy/` | A static host for the built viewer and the scenes, and the author's deploy script |
| [research](research) | Research reports written before and during the build, including the [Hugging Face hosting study](research/06-hugging-face.md) |
| [film](film/README.md) | Source of a four-minute film about the process (fframes, Rust). It needs the author's capture library and licensed fonts to render; see [THIRD_PARTY.md](THIRD_PARTY.md) |
| `tools/demo` | The six-camera strip renderer used for demo videos |
| [docs](docs) | [How the project was run](docs/how-it-was-run.md) (the agents' rules, formerly `AGENTS.md`) and [naming and Tesla's marks](docs/NAMING.md) |
| [TIMELINE.md](TIMELINE.md) | The original commit history |

## Known rough edges

What still assumes the author's setup, in the entry points and beyond:

- No calibrated rig and no sample scene are included, so nothing runs out of the box.
- `pipeline/calib` uses time windows and hand-drawn body masks chosen for the author's drive.
  `pipeline/run/rig-baseline.json` holds rig-check thresholds measured on his car.
- No Mac installer or requirements file. The environments were built by hand on his Mac Studio.
- Many stage scripts outside `pipeline/run` default to `RS=~/dev/reality-splat` (set `RS` to your installation
  root; the runner does this for the stages it calls), and the stage READMEs give commands for his machines
  (`ferry`, `anomastudio`, `basebook`).
- Author-only helpers: `pipeline/run/install.sh`, `viewer/tools/cache-on-studio.sh`, `viewer/tools/offload.ts`,
  `film/studio.sh`, `film/conform.py`, the launchd example `deploy/dev.vogel.reality-splat-viewer.plist`, and the
  rental and verification scripts in `pipeline/cuda` (`run_pod.py`, `pack_window.py`, `drive_receipts.py`, which
  name his job and drive).
- The viewer's dev server reads `scenes/` while the pipeline publishes to `scene/`.
- Several reports and the film depend on media that stayed on the author's machines.
- The viewer imitates Tesla's screen and uses Tesla's product names ([docs/NAMING.md](docs/NAMING.md)).

## Licence

- **Code:** Apache License 2.0, [LICENSE](LICENSE) and [NOTICE](NOTICE).
- **The author's images, videos and documents** (reports, research notes, screenshots, renders, the film's notes):
  Creative Commons Attribution 4.0 (CC BY 4.0), except third-party content inside them. This is the author's choice
  and he may change it. Frames made by the generative models may also carry those models' terms.
- **Models and third-party assets:** their own licences, listed in [THIRD_PARTY.md](THIRD_PARTY.md).

## Credits

Directed by Ryan Vogel, who drove the car and recorded the footage; built by AI coding agents working to his
direction ([docs/how-it-was-run.md](docs/how-it-was-run.md)). It stands on Depth Anything 3 (ByteDance Seed),
MapAnything, Mask2Former and DINOv2 (Meta), Difix3D+ (NVIDIA), SigLIP 2 (Google), MetalSplat, Spark, three.js, Ceres
Solver and FFmpeg, among others. The car model is "2024 Tesla Model 3" by RBLXSupercars (the credit embedded in the file; the project's notes also recorded "Tesla model 3 2024" by brandonleong28) (CC BY 4.0); street names
come from OpenStreetMap contributors (ODbL).

Tesla, Model 3 and other Tesla names are trademarks of Tesla, Inc. The project uses them to describe the footage it
works with; the viewer also imitates Tesla's display and uses some of its product names, listed in
[docs/NAMING.md](docs/NAMING.md) for the owner to decide on.
