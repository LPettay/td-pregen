#!/bin/bash
# Integrate the pre-genned TD world into pillowcreate as a sister world.
# Keeps pillowcreate's existing data/world/ untouched. The TD world is
# placed at data/world-td/ and pillowcreate is reconfigured to load it.
#
# Idempotent: re-running overwrites data/world-td/ with fresh contents.

set -euo pipefail

PREGEN_DIR="$HOME/minecraft/td-pregen"
PILLOW_DIR="$HOME/minecraft/pillowcreate"
STUB_RELEASE_URL="https://github.com/LPettay/terrain-diffusion-stub/releases/download/v0.1.0/terrain-diffusion-stub-0.1.0.jar"

echo "[1/5] Verifying pre-gen output exists..."
if [ ! -d "$PREGEN_DIR/data/world" ]; then
  echo "ERROR: $PREGEN_DIR/data/world does not exist. Run pre-gen first."
  exit 1
fi
WORLD_SIZE=$(du -sh "$PREGEN_DIR/data/world" | cut -f1)
echo "      pre-gen world size: $WORLD_SIZE"

echo "[2/5] Copying pre-genned world to pillowcreate/data/world-td/..."
rm -rf "$PILLOW_DIR/data/world-td"
cp -r "$PREGEN_DIR/data/world" "$PILLOW_DIR/data/world-td"
echo "      done."

echo "[3/5] Downloading stub mod jar..."
mkdir -p "$PILLOW_DIR/data/mods"
curl -sL "$STUB_RELEASE_URL" -o "$PILLOW_DIR/data/mods/terrain-diffusion-stub-0.1.0.jar"
ls -lh "$PILLOW_DIR/data/mods/terrain-diffusion-stub-0.1.0.jar"

echo "[4/5] Patching pillowcreate/docker-compose.yml..."
COMPOSE="$PILLOW_DIR/docker-compose.yml"
# LEVEL → world-td
if grep -q "^      LEVEL:" "$COMPOSE"; then
  sed -i 's|^      LEVEL:.*|      LEVEL: "world-td"|' "$COMPOSE"
  echo "      updated LEVEL"
else
  sed -i '/^      VERSION:/a\      LEVEL: "world-td"' "$COMPOSE"
  echo "      added LEVEL: world-td"
fi
# Enable RCON so we can set worldborder via docker compose exec
if grep -q "^      ENABLE_RCON:" "$COMPOSE"; then
  echo "      RCON already configured, leaving alone"
else
  sed -i '/^      LEVEL: "world-td"/a\      ENABLE_RCON: "TRUE"' "$COMPOSE"
  echo "      added ENABLE_RCON: TRUE"
fi

echo "[5/5] Done. Next steps:"
echo
echo "  1. Make sure Docker Desktop is running."
echo "  2. cd $PILLOW_DIR && docker compose up -d"
echo "  3. Wait for the server to come online (tail logs):"
echo "       docker compose logs -f"
echo "  4. Set the worldborder once the server is ready (5000 blocks square,"
echo "     centered on 0,0 — keeps players inside the pre-genned area):"
echo "       docker compose exec pillowcreate rcon-cli worldborder center 0 0"
echo "       docker compose exec pillowcreate rcon-cli worldborder set 5000"
echo "     (Or via the in-game console if you connect as op.)"
echo
echo "  Rollback: edit docker-compose.yml, set LEVEL: \"world\" (or remove the"
echo "  LEVEL line entirely), and restart. Your original world is untouched at"
echo "  $PILLOW_DIR/data/world/"
