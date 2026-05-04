#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# KobitoKey / ZMK Docker ビルドスクリプト
#
# 前提:
#   workspace/
#     KobitoKey_QWERTY/
#       build-zmk.sh
#       config/
#     zmk-env/
#       .west/
#       zmk/
#       modules/
#     zmk-build/
#
# 出力:
#   workspace/zmk-build/firmware/
#     KobitoKey_left.uf2
#     KobitoKey_right.uf2
#     settings_reset.uf2
# ============================================================

IMAGE="zmkfirmware/zmk-build-arm:stable"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

ENV_DIR="${WORKSPACE_DIR}/zmk-env"
BUILD_ROOT="${WORKSPACE_DIR}/zmk-build"
OUTPUT_DIR="${BUILD_ROOT}/firmware"

DOCKER_CONFIG_DIR="${WORKSPACE_DIR}/.docker-zmk"

CONTAINER_WORKSPACE="/workspaces"
CONTAINER_ENV_DIR="${CONTAINER_WORKSPACE}/zmk-env"
CONTAINER_BUILD_ROOT="${CONTAINER_WORKSPACE}/zmk-build"
CONTAINER_OUTPUT_DIR="${CONTAINER_BUILD_ROOT}/firmware"

BOARD="seeeduino_xiao_ble"
CONFIG_DIR="${CONTAINER_ENV_DIR}/config"
ZMK_APP_DIR="${CONTAINER_ENV_DIR}/zmk/app"

GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_info() {
  echo -e "${BLUE}$*${NC}"
}

log_ok() {
  echo -e "${GREEN}$*${NC}"
}

log_warn() {
  echo -e "${YELLOW}$*${NC}"
}

log_error() {
  echo -e "${RED}$*${NC}"
}

error_handler() {
  echo
  log_error "========================================"
  log_error "ビルド中にエラーが発生しました"
  log_error "========================================"
  echo
  log_warn "確認してください:"
  echo "  1. setup-zmk-env.sh を先に実行済みか"
  echo "  2. Docker Desktop が起動しているか"
  echo "  3. zmk-env/.west と zmk-env/zmk が存在するか"
  echo "  4. config/build.yaml の shield 名と実ファイル名が一致しているか"
  echo
  exit 1
}

trap error_handler ERR

prepare_docker_config() {
  mkdir -p "${DOCKER_CONFIG_DIR}"

  # WSL側の ~/.docker/config.json にある
  # docker-credential-desktop.exe 問題を避けるため、
  # ZMK専用のDocker設定を使用する。
  cat > "${DOCKER_CONFIG_DIR}/config.json" <<'JSON'
{
  "auths": {}
}
JSON
}

check_requirements() {
  log_info "[1/4] 前提条件を確認しています..."

  if ! command -v docker >/dev/null 2>&1; then
    log_error "docker コマンドが見つかりません。"
    exit 1
  fi

  if [ ! -d "${ENV_DIR}/.west" ]; then
    log_error "West workspace が見つかりません: ${ENV_DIR}/.west"
    log_error "先に setup-zmk-env.sh を実行してください。"
    exit 1
  fi

  if [ ! -d "${ENV_DIR}/zmk/app" ]; then
    log_error "ZMK app ディレクトリが見つかりません: ${ENV_DIR}/zmk/app"
    log_error "先に setup-zmk-env.sh を実行してください。"
    exit 1
  fi

  mkdir -p "${OUTPUT_DIR}"

  log_ok "✓ 前提条件OK"
  echo
}

run_docker() {
  if [ -t 0 ]; then
    TTY_FLAG="-it"
  else
    TTY_FLAG="-i"
  fi

  DOCKER_CONFIG="${DOCKER_CONFIG_DIR}" docker run --rm ${TTY_FLAG} \
    --user "$(id -u):$(id -g)" \
    -v "${WORKSPACE_DIR}:${CONTAINER_WORKSPACE}" \
    -w "${CONTAINER_ENV_DIR}" \
    "${IMAGE}" \
    "$@"
}

build_one() {
  local name="$1"
  local shield="$2"
  local build_dir="${CONTAINER_BUILD_ROOT}/${name}"
  local output_file="${CONTAINER_OUTPUT_DIR}/${name}.uf2"

  log_info "ビルド開始: ${name}"
  echo "  board  : ${BOARD}"
  echo "  shield : ${shield}"
  echo

  run_docker bash -lc "
    set -euo pipefail

    # west から Zephyr の実パスを取得する
    export ZEPHYR_BASE=\"\$(west list -f '{abspath}' zephyr)\"

    # CMake が find_package(Zephyr) できるように Zephyr_DIR を明示する
    export Zephyr_DIR=\"\${ZEPHYR_BASE}/share/zephyr-package/cmake\"

    # 念のため Zephyr の環境設定も読み込む
    if [ -f \"\${ZEPHYR_BASE}/zephyr-env.sh\" ]; then
      source \"\${ZEPHYR_BASE}/zephyr-env.sh\"
    fi

    echo \"ZEPHYR_BASE=\${ZEPHYR_BASE}\"
    echo \"Zephyr_DIR=\${Zephyr_DIR}\"

    if [ ! -f \"\${Zephyr_DIR}/ZephyrConfig.cmake\" ]; then
      echo \"ERROR: ZephyrConfig.cmake が見つかりません: \${Zephyr_DIR}/ZephyrConfig.cmake\"
      exit 1
    fi

    west build -p always \
      -s '${ZMK_APP_DIR}' \
      -b '${BOARD}' \
      -d '${build_dir}' \
      -- \
      -DZephyr_DIR=\"\${Zephyr_DIR}\" \
      -DSHIELD='${shield}' \
      -DZMK_CONFIG='${CONFIG_DIR}'

    cp '${build_dir}/zephyr/zmk.uf2' '${output_file}'
  "

  log_ok "✓ 完了: ${OUTPUT_DIR}/${name}.uf2"
  echo
}

main() {
  echo -e "${GREEN}========================================${NC}"
  echo -e "${GREEN}KobitoKey / ZMK Docker ビルド${NC}"
  echo -e "${GREEN}========================================${NC}"
  echo
  echo "workspace : ${WORKSPACE_DIR}"
  echo "env       : ${ENV_DIR}"
  echo "output    : ${OUTPUT_DIR}"
  echo "image     : ${IMAGE}"
  echo

  prepare_docker_config
  check_requirements

  log_info "[2/4] Dockerイメージを確認しています..."
  DOCKER_CONFIG="${DOCKER_CONFIG_DIR}" docker image inspect "${IMAGE}" >/dev/null 2>&1 || \
    DOCKER_CONFIG="${DOCKER_CONFIG_DIR}" docker pull "${IMAGE}"
  log_ok "✓ DockerイメージOK"
  echo

  log_info "[3/4] ファームウェアをビルドしています..."
  echo

  build_one "KobitoKey_left" "KobitoKey_left rgbled_adapter"
  build_one "KobitoKey_right" "KobitoKey_right rgbled_adapter"
  build_one "settings_reset" "settings_reset"

  log_info "[4/4] 出力ファイルを確認しています..."
  ls -lh "${OUTPUT_DIR}"

  echo
  log_ok "========================================"
  log_ok "ビルドが完了しました"
  log_ok "========================================"
  echo
  echo "出力先:"
  echo "  ${OUTPUT_DIR}"
  echo
  echo "生成ファイル:"
  echo "  ${OUTPUT_DIR}/KobitoKey_left.uf2"
  echo "  ${OUTPUT_DIR}/KobitoKey_right.uf2"
  echo "  ${OUTPUT_DIR}/settings_reset.uf2"
}

main "$@"