#!/usr/bin/env bash
# One-command setup on Apple Silicon: the Mac counterpart of pipeline/cuda/setup-drive.sh.
# Produces the same layout the runner expects (.venv, envs/stitch, envs/genfill, third_party/, the Ceres solvers,
# the two C++ helpers, the chase tool and the viewer) under the checkout, which is RS_INSTALL by default.
#
#   bash pipeline/run/setup-mac.sh            # everything except model weights
#   bash pipeline/run/setup-mac.sh --models   # also download the pinned weights (about 12 GB, licences printed)
#
# Idempotent: rerun after a failure. It does not provide calib/rig.json or calib/masks/ (see pipeline/calib).
set -euo pipefail
cd "$(dirname "$0")/../.."
MODELS=0
for a in "$@"; do
  case "$a" in
    --models) MODELS=1 ;;
    -h|--help) sed -n 2,9p "$0"; exit 0 ;;
    *) echo "unknown option: $a" >&2; exit 2 ;;
  esac
done

[[ $(uname -s) == Darwin && $(uname -m) == arm64 ]] || { echo "Apple Silicon macOS only; on Linux use pipeline/cuda/setup-drive.sh" >&2; exit 1; }
command -v brew >/dev/null || { echo "Install Homebrew first: https://brew.sh" >&2; exit 1; }
xcode-select -p >/dev/null 2>&1 || { echo "Install the Xcode command-line tools first: xcode-select --install" >&2; exit 1; }

export RS_INSTALL="$PWD" HF_HOME="$PWD/third_party/hf" TORCH_HOME="$PWD/third_party/torch"

step() { printf '\n== %s\n' "$*"; }

step "System packages"
# Install only what is missing (same list as Brewfile); never upgrade or duplicate existing tools.
need() { command -v "$1" >/dev/null || { echo "installing $2"; brew install "$2"; }; }
need cmake cmake; need ninja ninja; need ffmpeg ffmpeg; need uv uv; need bun oven-sh/bun/bun
for f in ceres-solver eigen; do brew list --formula "$f" >/dev/null 2>&1 || { echo "installing $f"; brew install "$f"; }; done

mkdir -p tools/run-chase envs third_party work/road/build work/ibr/m2 maps/object-v3 scene

step "Pinned upstream sources"
clone() {
  if ! test -d "$3/.git"; then git init -q "$3"; git -C "$3" fetch -q --depth 1 "$1" "$2"; git -C "$3" checkout -q --detach FETCH_HEAD; fi
  test "$(git -C "$3" rev-parse HEAD)" = "$2" || { echo "$3 is not at $2" >&2; exit 1; }
}
clone https://github.com/ByteDance-Seed/Depth-Anything-3 3d835ec1a5802d64a8b8b15f817a1ab54809bfe4 third_party/Depth-Anything-3
clone https://github.com/tchauffi/metalsplat 84e8c3a433f71c107e9387d3f72a765436c11f6e third_party/metalsplat
clone https://github.com/nv-tlabs/Difix3D c76edc595586e16732c91ddee82f3a6d83a8a9cc third_party/Difix3D

step "Python environments (uv, Python 3.12, torch with MPS)"
# full.py reads envs/stitch/lib/python3.12/site-packages literally, so 3.12 is required.
TORCH=('torch==2.15.0' 'torchvision==0.29.2')
test -x .venv/bin/python || uv venv -q --python 3.12 .venv
grep -v '^torchvision==' pipeline/cuda/constraints-depth.txt >envs/depth-constraints.txt
uv pip install -q --python .venv/bin/python -c envs/depth-constraints.txt "${TORCH[@]}" \
  'numpy==1.26.4' 'opencv-python-headless==4.10.0.84' 'transformers==4.57.6' 'huggingface-hub<1' scipy pillow av \
  einops timm hydra-core orjson natsort python-box plyfile trimesh e3nn evo pycolmap addict jaxtyping imageio \
  sentencepiece protobuf matplotlib safetensors ninja
uv pip install -q --python .venv/bin/python --no-deps -e third_party/Depth-Anything-3

# The stitch stage adds this environment's site-packages on top of .venv (see pipeline/stitch/README.md).
test -x envs/stitch/bin/python || uv venv -q -p .venv/bin/python envs/stitch
uv pip install -q --python envs/stitch/bin/python --no-deps msplat==1.1.4 lpips==0.1.4

test -x envs/genfill/bin/python || uv venv -q --python 3.12 envs/genfill
uv pip install -q --python envs/genfill/bin/python -c pipeline/cuda/constraints-genfill.txt "${TORCH[@]}" \
  'numpy==1.26.4' 'opencv-python-headless==4.10.0.84' scipy av pillow diffusers transformers peft huggingface-hub \
  accelerate safetensors einops lpips

step "Native solvers and helpers"
# Ninja rather than make: make breaks when the active Xcode lives in a path with a space.
build() {
  if test -f "$2/CMakeCache.txt" && ! grep -q 'CMAKE_GENERATOR:INTERNAL=Ninja' "$2/CMakeCache.txt"; then rm -rf "$2"; fi
  cmake -G Ninja -S "$1" -B "$2" -DCMAKE_BUILD_TYPE=Release >/dev/null
  cmake --build "$2"
}
build pipeline/calib work/calib/build
build pipeline/poses work/poses/build
ln -sf ../../poses/build/trajectory_ba work/road/build/trajectory_ba
c++ -O3 -std=c++17 -dynamiclib pipeline/ibr/m2_surface.cpp -o work/ibr/m2/m2_surface.dylib
c++ -O3 -std=c++17 -dynamiclib pipeline/livemap/raster.cpp -o maps/object-v3/raster.dylib
# pipeline/movers/classifier.py compiles classify.swift itself on first use; check the compiler works now.
swiftc -O pipeline/movers/classify.swift -o work/classify-check && rm -f work/classify-check

step "Viewer and chase tool (Bun)"
# viewer/bun.lock needs Bun 1.4. An older Bun on PATH is left alone; a private 1.4.4 goes in third_party/bun.
BUN=bun
if [[ $(bun --version) != 1.4.* ]]; then
  BUN="$PWD/third_party/bun/bun"
  if [[ ! -x $BUN || $("$BUN" --version) != 1.4.4 ]]; then
    mkdir -p third_party/bun
    curl -fsSL --retry 2 https://github.com/oven-sh/bun/releases/download/bun-v1.4.4/bun-darwin-aarch64.zip -o third_party/bun/bun.zip
    unzip -op third_party/bun/bun.zip bun-darwin-aarch64/bun >"$BUN"; chmod 755 "$BUN"; rm third_party/bun/bun.zip
  fi
  echo "using $BUN ($("$BUN" --version)); put third_party/bun on PATH before running drive.py"
fi
(cd viewer && "$BUN" install --frozen-lockfile && "$BUN" --bun x vite build)
ln -sfn viewer viewer-cache-tool
"$BUN" build viewer/tools/chase-track.ts --target=bun --minify --outdir=tools/run-chase

if ((MODELS)); then
  step "Model weights (pinned revisions; several are non-commercial, read each licence line)"
  .venv/bin/python pipeline/cuda/drive_models.py
else
  echo; echo "Skipped model weights. Rerun with --models to download them (about 12 GB)."
fi

step "Checks"
.venv/bin/python - <<'PY'
import av, cv2, scipy, transformers, torch, depth_anything_3
assert torch.backends.mps.is_available(), "PyTorch cannot see the GPU (MPS)"
print(".venv", torch.__version__, "MPS ok")
PY
PYTHONPATH="$PWD/third_party/metalsplat/src:$PWD/envs/stitch/lib/python3.12/site-packages" .venv/bin/python -c 'import metalsplat, msplat, lpips; print("stitch ok")'
envs/genfill/bin/python -c 'import diffusers, torch; assert torch.backends.mps.is_available(); print("genfill", diffusers.__version__, "ok")'
for f in work/calib/build/rig_ba work/poses/build/trajectory_ba work/ibr/m2/m2_surface.dylib maps/object-v3/raster.dylib tools/run-chase/chase-track.js viewer/dist/index.html; do
  test -s "$f" || { echo "missing $f" >&2; exit 1; }
done
echo "setup done. Still needed before a run: calib/rig.json and calib/masks/ for your car, and six-camera clips."
