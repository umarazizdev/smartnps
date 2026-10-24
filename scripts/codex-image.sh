#!/usr/bin/env bash
# Delegate AI image/icon generation to Codex. Cursor handles all non-image work.
set -euo pipefail

MODE="image"
PROMPT=""
OUT_PATH=""

usage() {
  local code="${1:-1}"
  cat >&2 <<'EOF'
Usage:
  scripts/codex-image.sh [--image|--icon|--both] "prompt" [output/path]

Modes:
  --image   Generate a raster image only (default)
  --icon    Generate an icon only (transparent PNG, UI/app-icon ready)
  --both    Generate both a full image and an icon variant

Examples:
  scripts/codex-image.sh "hero illustration of a dashboard"
  scripts/codex-image.sh --icon "simple NPS gauge icon" assets/icons/nps.png
  scripts/codex-image.sh --both "onboarding welcome art" assets/generated/welcome
EOF
  exit "$code"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --image|--img)
      MODE="image"
      shift
      ;;
    --icon|--icons)
      MODE="icon"
      shift
      ;;
    --both|--all)
      MODE="both"
      shift
      ;;
    -h|--help)
      usage 0
      ;;
    --)
      shift
      break
      ;;
    -*)
      echo "Unknown option: $1" >&2
      usage
      ;;
    *)
      if [[ -z "$PROMPT" ]]; then
        PROMPT="$1"
      elif [[ -z "$OUT_PATH" ]]; then
        OUT_PATH="$1"
      else
        echo "Unexpected argument: $1" >&2
        usage
      fi
      shift
      ;;
  esac
done

# Allow remaining positional args after --
while [[ $# -gt 0 ]]; do
  if [[ -z "$PROMPT" ]]; then
    PROMPT="$1"
  elif [[ -z "$OUT_PATH" ]]; then
    OUT_PATH="$1"
  else
    echo "Unexpected argument: $1" >&2
    usage
  fi
  shift
done

if [[ -z "$PROMPT" ]]; then
  usage
fi

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

case "$MODE" in
  image)
    TASK_KIND="a high-quality raster image"
    DEFAULT_DIR="assets/generated"
    PATH_HINT="image"
    ;;
  icon)
    TASK_KIND="a high-quality icon"
    DEFAULT_DIR="assets/icons"
    PATH_HINT="icon"
    ;;
  both)
    TASK_KIND="both a high-quality raster image AND a matching icon"
    DEFAULT_DIR="assets/generated"
    PATH_HINT="image + icon"
    ;;
esac

DEST_INSTRUCTION=""
if [[ -n "$OUT_PATH" ]]; then
  # If path looks like a directory (no extension) or ends with /, treat as dir.
  if [[ "$OUT_PATH" == */ ]] || [[ "$OUT_PATH" != *.* ]]; then
    mkdir -p "$OUT_PATH"
    case "$MODE" in
      image)
        DEST_INSTRUCTION="Save the final image under this directory: ${OUT_PATH}
Use a clear filename (e.g. image.png)."
        ;;
      icon)
        DEST_INSTRUCTION="Save the final icon under this directory: ${OUT_PATH}
Use a clear filename (e.g. icon.png). Prefer a square transparent PNG."
        ;;
      both)
        DEST_INSTRUCTION="Save both assets under this directory: ${OUT_PATH}
Use clear filenames such as image.png and icon.png."
        ;;
    esac
  else
    mkdir -p "$(dirname "$OUT_PATH")"
    case "$MODE" in
      image)
        DEST_INSTRUCTION="Copy or move the final selected image into this exact project path: ${OUT_PATH}
Do not leave the project asset only under \$CODEX_HOME/generated_images."
        ;;
      icon)
        DEST_INSTRUCTION="Copy or move the final selected icon into this exact project path: ${OUT_PATH}
Prefer a square transparent PNG. Do not leave the project asset only under \$CODEX_HOME/generated_images."
        ;;
      both)
        BASE="${OUT_PATH%.*}"
        EXT="${OUT_PATH##*.}"
        if [[ "$EXT" == "$OUT_PATH" ]]; then
          EXT="png"
          BASE="$OUT_PATH"
        fi
        DEST_INSTRUCTION="Save two files derived from this path base:
- Image: ${BASE}.${EXT} (or ${BASE}-image.${EXT} if needed)
- Icon:  ${BASE}-icon.${EXT}
Do not leave the project assets only under \$CODEX_HOME/generated_images."
        ;;
    esac
  fi
else
  case "$MODE" in
    image)
      DEST_INSTRUCTION="Copy or move the final selected image into ${DEFAULT_DIR}/ (create the folder if needed) with a clear filename. Report the final project-relative path."
      ;;
    icon)
      DEST_INSTRUCTION="Copy or move the final selected icon into ${DEFAULT_DIR}/ (create the folder if needed) with a clear filename (square transparent PNG preferred). Report the final project-relative path."
      ;;
    both)
      DEST_INSTRUCTION="Copy or move both assets into ${DEFAULT_DIR}/ (create the folder if needed) with clear filenames such as <name>.png and <name>-icon.png. Report both final project-relative paths."
      ;;
  esac
fi

ICON_GUIDANCE=""
if [[ "$MODE" == "icon" || "$MODE" == "both" ]]; then
  ICON_GUIDANCE="
Icon requirements:
- Square canvas, simple readable silhouette at small sizes
- Transparent background unless the prompt says otherwise
- No tiny illegible text; prefer a single symbol/mark
- Export as PNG suitable for Flutter Image.asset / app icon use"
fi

LAST_MSG="$(mktemp -t codex-image-last.XXXXXX)"
trap 'rm -f "$LAST_MSG"' EXIT

codex exec \
  -C "$ROOT" \
  -s workspace-write \
  -o "$LAST_MSG" \
  "Use the imagegen skill (built-in image_gen tool).

Task: generate (or edit if references imply edit) ${TASK_KIND} for this Flutter project.
Mode: ${MODE} (${PATH_HINT})
${ICON_GUIDANCE}

User prompt:
${PROMPT}

${DEST_INSTRUCTION}

When done, reply with:
1) final project path(s) of the saved asset(s)
2) one-line description of what was generated
Do not change application code."

echo "----- Codex last message -----"
cat "$LAST_MSG"
echo
echo "----- Done (${MODE}) -----"
