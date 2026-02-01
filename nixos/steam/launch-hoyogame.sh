#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: launch-hoyogame.sh [options] -- [extra args]

Options:
  --steam-root PATH     Steam root (default: $HOME/.local/share/Steam)
  --compat-id ID        Steam compatdata app ID (e.g. 2649200909)
  --compat-data PATH    Full compatdata path (overrides --compat-id)
  --exe PATH            Game EXE path; if relative, it is under drive_c
  --proton PATH         Proton script (overrides auto-detect)
  --steam-app-id ID     Export SteamAppId/SteamGameId/STEAM_COMPAT_APP_ID
  --steam-run           Force steam-run (FHS env)
  --no-steam-run        Disable steam-run
  -h, --help            Show help
USAGE
}

STEAM_ROOT="${HOME}/.local/share/Steam"
COMPAT_ID=""
COMPAT_DATA=""
EXE=""
PROTON=""
STEAM_APP_ID=""
USE_STEAM_RUN="auto"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --steam-root)
      STEAM_ROOT="$2"; shift 2 ;;
    --compat-id)
      COMPAT_ID="$2"; shift 2 ;;
    --compat-data)
      COMPAT_DATA="$2"; shift 2 ;;
    --exe)
      EXE="$2"; shift 2 ;;
    --proton)
      PROTON="$2"; shift 2 ;;
    --steam-app-id)
      STEAM_APP_ID="$2"; shift 2 ;;
    --steam-run)
      USE_STEAM_RUN=1; shift ;;
    --no-steam-run)
      USE_STEAM_RUN=0; shift ;;
    -h|--help)
      usage; exit 0 ;;
    --)
      shift; break ;;
    *)
      echo "Unknown arg: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "${COMPAT_DATA}" ]]; then
  if [[ -z "${COMPAT_ID}" ]]; then
    echo "Missing --compat-id or --compat-data" >&2
    exit 1
  fi
  COMPAT_DATA="${STEAM_ROOT}/steamapps/compatdata/${COMPAT_ID}"
fi

if [[ -z "${EXE}" ]]; then
  echo "Missing --exe" >&2
  exit 1
fi

if [[ "${EXE}" != /* ]]; then
  EXE="${COMPAT_DATA}/pfx/drive_c/${EXE}"
fi

if [[ ! -d "${COMPAT_DATA}" ]]; then
  echo "Compatdata not found: ${COMPAT_DATA}" >&2
  exit 1
fi

if [[ -n "${STEAM_APP_ID}" ]]; then
  export SteamAppId="${STEAM_APP_ID}"
  export SteamGameId="${STEAM_APP_ID}"
  export STEAM_COMPAT_APP_ID="${STEAM_APP_ID}"
fi

# If NVIDIA ICD exists, prefer it for Vulkan.
NVIDIA_ICD="/run/opengl-driver/share/vulkan/icd.d/nvidia_icd.x86_64.json"
if [[ -f "${NVIDIA_ICD}" ]]; then
  export VK_ICD_FILENAMES="${NVIDIA_ICD}"
  export VK_DRIVER_FILES="${NVIDIA_ICD}"
  export __NV_PRIME_RENDER_OFFLOAD=1
  export __GLX_VENDOR_LIBRARY_NAME=nvidia
fi

export STEAM_COMPAT_CLIENT_INSTALL_PATH="${STEAM_ROOT}"
export STEAM_COMPAT_DATA_PATH="${COMPAT_DATA}"

if [[ -z "${PROTON}" ]] && [[ -f "${COMPAT_DATA}/config_info" ]]; then
  tool_root=$(awk -F'/files/' '/\\/files\\/share\\/default_pfx\\// {print $1; exit}' "${COMPAT_DATA}/config_info" || true)
  if [[ -n "${tool_root}" ]] && [[ -x "${tool_root}/proton" ]]; then
    PROTON="${tool_root}/proton"
  fi
fi

if [[ -z "${PROTON}" ]]; then
  fallback="${STEAM_ROOT}/steamapps/common/Proton - Experimental/proton"
  if [[ -x "${fallback}" ]]; then
    PROTON="${fallback}"
  fi
fi

if [[ -z "${PROTON}" ]]; then
  echo "Proton not found. Install Proton or pass --proton PATH." >&2
  exit 1
fi

if [[ ! -x "${EXE}" ]]; then
  echo "EXE not found: ${EXE}" >&2
  exit 1
fi

if [[ "${USE_STEAM_RUN}" == "auto" ]]; then
  if command -v steam-run >/dev/null 2>&1; then
    USE_STEAM_RUN=1
  else
    USE_STEAM_RUN=0
  fi
fi

if [[ "${USE_STEAM_RUN}" == "1" ]]; then
  exec steam-run "${PROTON}" run "${EXE}" "$@"
fi

exec "${PROTON}" run "${EXE}" "$@"
