# td-pregen

Headless, GPU-accelerated pre-gen rig for [Terrain Diffusion](https://github.com/xandergos/terrain-diffusion-mc)
worlds. Runs entirely in WSL on Lance's RTX 4080 via ONNX CUDA EP. Drives a Fabric 1.21.1
server with Chunky for unattended pre-generation.

Used to produce a Terrain Diffusion world for [pillowcreate](https://github.com/LPettay/pillowcreate)
(NeoForge 1.21.1) via the world-migration approach — see the companion stub mod at
[LPettay/terrain-diffusion-stub](https://github.com/LPettay/terrain-diffusion-stub) and the
long-term native port issue at
[LPettay/terrain-diffusion-mc#1](https://github.com/LPettay/terrain-diffusion-mc/issues/1).

## What's here

- `data/` — Fabric server runtime (mods, configs, world output)
- `run-pregen.sh` — orchestrator: launches the server, dispatches Chunky, monitors log,
  sends `stop` cleanly when "Task finished" appears.

## Prereqs

- WSL2 with NVIDIA GPU passthrough (verify via `nvidia-smi`)
- JDK 21 (Eclipse Temurin recommended)
- Conda (any flavor)
- Conda env named `td-pregen` containing CUDA 12.x runtime + cuDNN 9.x:

  ```bash
  conda create -n td-pregen -c conda-forge -y \
      cudnn=9.8 "cuda-cudart>=12,<13" \
      libcurand libcufft libcusparse libcusolver
  ```

## TD-MC CUDA jar

The Modrinth release of Terrain Diffusion ships only the DirectML (Windows-native)
variant. For Linux/CUDA we build from upstream:

```bash
git clone https://github.com/xandergos/terrain-diffusion-mc
cd terrain-diffusion-mc
git checkout 1.21.1
./gradlew build -PuseCuda=true
cp build/libs/terrain-diffusion-mc-*-cuda+1.21.1.jar /path/to/td-pregen/data/mods/
```

## Run

```bash
bash run-pregen.sh 2500          # 5000 x 5000 area (radius 2500)
bash run-pregen.sh 1500          # 3000 x 3000
bash run-pregen.sh 1              # smoke test, 9 chunks
```

The script:

1. Truncates `data/logs/latest.log` and clears persisted Chunky tasks
2. Sets `LD_LIBRARY_PATH` to the conda env's CUDA libs
3. Launches the server with stdin piped from a FIFO
4. Waits for `Done.*For help, type` in the log
5. Dispatches `chunky world / center / radius / start`
6. Polls log for `Task (finished|completed|done)` every 60s
7. Sends `stop`, waits for clean shutdown
8. Reports world ready at `data/world/`

Re-runnable: Chunky resumes interrupted tasks automatically when state is preserved.
This script clears state for a fresh start.

## First run notes

- ~2.2 GiB of ONNX model assets download from HuggingFace on first server boot, into
  `data/terrain-diffusion-models/`. Cached for subsequent runs.
- Server bootstrap downloads MC 1.21.1 + Fabric loader libs into `data/libraries/`.
- Expect ~30s before pre-gen begins on cold cache, ~10s when models are cached.

## Observed performance

On RTX 4080 + CUDA 12.9 + cuDNN 9.8 + ONNX Runtime 1.20.0 GPU:

- ~100-135 chunks/sec sustained during Chunky pre-gen
- 5000 x 5000 (~98k chunks) → ~12-16 min
- 1.89 GiB `base_model.onnx` is the dominant model; loaded once, cached in CPU RAM

## After pre-gen

The world at `data/world/` references the `terrain-diffusion-mc:terrain_diffusion`
BiomeSource and DensityFunction. Loading it on a NeoForge server requires the
[stub mod](https://github.com/LPettay/terrain-diffusion-stub) to register those codec
types — without it, dimension load fails on unknown BiomeSource type.

Then set worldborder to the pre-genned area before any player joins:

```
/worldborder center 0 0
/worldborder set 5000
```
