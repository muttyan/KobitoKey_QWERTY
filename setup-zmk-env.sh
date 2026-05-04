#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# KobitoKey / ZMK Docker ビルド環境 初期化スクリプト
#
# 前提:
#   workspace/
#     KobitoKey_QWERTY/
#       setup-zmk-env.sh  ← このスクリプト
#       config/
#         west.yml
#
# 作成されるもの:
#   workspace/
#     zmk-env/            ← west workspace / ZMK本体 / modules
#     zmk-build/          ← ビルド結果用
#
# 目的:
#   Windows + WSL + Docker Desktop 環境で、
#   ZMKのビルドに必要なwest環境をDocker上で初期化する
# ============================================================

IMAGE="zmkfirmware/zmk-build-arm:stable"

# コンテナ内のマウント先
CONTAINER_WORKSPACE="/workspaces"
CONTAINER_ENV_DIR="${CONTAINER_WORKSPACE}/zmk-env"

# 色付き出力
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# スクリプト自身の場所 = KobitoKey_QWERTY
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# KobitoKey_QWERTY の親 = workspace
WORKSPACE_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# 各ディレクトリ
CONFIG_DIR="${SCRIPT_DIR}/config"
ENV_DIR="${WORKSPACE_DIR}/zmk-env"
BUILD_DIR="${WORKSPACE_DIR}/zmk-build"

# Docker credential 問題を避けるため、ZMK専用のDocker設定を使う
# ~/.docker/config.json の credsStore=desktop.exe を読ませない
DOCKER_CONFIG_DIR="${WORKSPACE_DIR}/.docker-zmk"

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
  log_error "エラーが発生しました"
  log_error "========================================"
  echo
  log_warn "確認してください:"
  echo "  1. Docker Desktop が起動しているか"
  echo "  2. Docker Desktop の WSL integration が有効か"
  echo "  3. WSL内で docker version が成功するか"
  echo "  4. config/west.yml が存在するか"
  echo
  log_warn "完全にやり直す場合:"
  echo "  rm -rf \"${ENV_DIR}\" \"${BUILD_DIR}\""
  echo
  exit 1
}

trap error_handler ERR

prepare_docker_config() {
  mkdir -p "${DOCKER_CONFIG_DIR}"

  # 空に近いDocker設定を作る。
  # これにより ~/.docker/config.json の credsStore / credStore を回避する。
  cat > "${DOCKER_CONFIG_DIR}/config.json" <<'JSON'
{
  "auths": {}
}
JSON
}

run_docker() {
  # 端末がある場合だけ -t を付ける
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

check_requirements() {
  log_info "[1/5] 前提条件を確認しています..."

  if ! command -v docker >/dev/null 2>&1; then
    log_error "docker コマンドが見つかりません。"
    log_error "Docker Desktop の WSL integration を有効にしてください。"
    exit 1
  fi

  if [ ! -d "${CONFIG_DIR}" ]; then
    log_error "config ディレクトリが見つかりません: ${CONFIG_DIR}"
    exit 1
  fi

  if [ ! -f "${CONFIG_DIR}/west.yml" ]; then
    log_error "west.yml が見つかりません: ${CONFIG_DIR}/west.yml"
    exit 1
  fi

  log_ok "✓ 前提条件OK"
  echo
}

show_summary() {
  echo -e "${GREEN}========================================${NC}"
  echo -e "${GREEN}KobitoKey / ZMK ビルド環境 初期化${NC}"
  echo -e "${GREEN}========================================${NC}"
  echo
  echo "workspace : ${WORKSPACE_DIR}"
  echo "config    : ${CONFIG_DIR}"
  echo "env       : ${ENV_DIR}"
  echo "build     : ${BUILD_DIR}"
  echo "docker    : ${DOCKER_CONFIG_DIR}"
  echo "image     : ${IMAGE}"
  echo
}

main() {
  show_summary

  prepare_docker_config
  check_requirements

  log_info "[2/5] 作業ディレクトリを作成しています..."
  mkdir -p "${ENV_DIR}"
  mkdir -p "${BUILD_DIR}"

  # zmk-env/config に KobitoKey_QWERTY/config をコピーする
  # west init -l は symlink を解決してしまうため、symlink は使わない
  rm -rf "${ENV_DIR}/config"
  mkdir -p "${ENV_DIR}/config"
  cp -a "${CONFIG_DIR}/." "${ENV_DIR}/config/"

  log_ok "✓ ディレクトリ作成完了"
  echo

  log_info "[3/5] Dockerイメージを取得しています..."
  DOCKER_CONFIG="${DOCKER_CONFIG_DIR}" docker pull "${IMAGE}"
  log_ok "✓ Dockerイメージ準備完了"
  echo

  log_info "[4/5] West workspace を初期化しています..."

  if [ -d "${ENV_DIR}/.west" ]; then
    log_warn ".west は既に存在するため、west init はスキップします。"
  else
    run_docker west init -l config
    log_ok "✓ west init 完了"
  fi

  if [ ! -d "${ENV_DIR}/.west" ]; then
    log_error "west init に失敗しました。.west が作成されていません。"
    exit 1
  fi

  echo

  log_info "[5/5] ZMK本体と依存モジュールを取得しています..."
  log_warn "初回は数分かかる場合があります。"

  run_docker west update
  run_docker west zephyr-export

  echo
  log_ok "========================================"
  log_ok "初期化が完了しました"
  log_ok "========================================"
  echo
  echo "作成された環境:"
  echo "  ${ENV_DIR}"
  echo
  echo "ビルド結果用ディレクトリ:"
  echo "  ${BUILD_DIR}"
  echo
  echo "次のステップ:"
  echo "  ビルド用スクリプトを作成して、left / right / settings_reset をビルドします。"
}

main "$@"