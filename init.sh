#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSETS_DIR="${ROOT_DIR}/OcrLibrary/src/main/assets"
SDK_NATIVE_DIR="${ROOT_DIR}/OcrLibrary/src/sdk/native"
ORT_DIR="${ROOT_DIR}/OcrLibrary/src/main/onnxruntime-shared"
TMP_DIR="${ROOT_DIR}/.tmp/init"

OPENCV_URL="${OPENCV_URL:-https://gitee.com/benjaminwan/ocr-lite-android-ncnn/attach_files/843219/download/opencv-mobile-3.4.15-android.7z}"
ORT_URL="${ORT_URL:-https://github.com/RapidAI/OnnxruntimeBuilder/releases/download/1.14.0/onnxruntime-1.14.0-android-shared.7z}"
MODEL_URL="${MODEL_URL:-}"
MODEL_DIR="${MODEL_DIR:-}"
MODEL_ARCHIVE="${MODEL_ARCHIVE:-}"
MODEL_INDEX_URL="${MODEL_INDEX_URL:-https://raw.githubusercontent.com/RapidAI/RapidOCR/main/python/rapidocr/default_models.yaml}"

DET_SOURCE_NAME="${DET_SOURCE_NAME:-${DET_MODEL:-ch_PP-OCRv5_mobile_det.onnx}}"
REC_SOURCE_NAME="${REC_SOURCE_NAME:-${REC_MODEL:-ch_PP-OCRv5_rec_mobile_infer.onnx}}"
CLS_SOURCE_NAME="${CLS_SOURCE_NAME:-${CLS_MODEL:-ch_ppocr_mobile_v2.0_cls_infer.onnx}}"
DET_ASSET_NAME="${DET_ASSET_NAME:-det.onnx}"
REC_ASSET_NAME="${REC_ASSET_NAME:-rec.onnx}"
CLS_ASSET_NAME="${CLS_ASSET_NAME:-cls.onnx}"
KEYS_FILE="ppocr_keys_v1.txt"

CLS_URL="${CLS_URL:-}"
DET_URL="${DET_URL:-}"
REC_URL="${REC_URL:-}"
KEYS_URL="${KEYS_URL:-https://www.modelscope.cn/models/RapidAI/RapidOCR/resolve/v3.6.0/paddle/PP-OCRv4/rec/ch_PP-OCRv4_rec_infer/ppocr_keys_v1.txt}"

usage() {
  cat <<'EOF'
Usage: ./init.sh [--clean]

环境变量：
  OPENCV_URL       opencv-mobile-3.4.15-android.7z 下载地址
  ORT_URL          onnxruntime-1.14.0-android-shared.7z 下载地址
  MODEL_URL        模型压缩包下载地址（可选）
  MODEL_ARCHIVE    本地模型压缩包路径（可选）
  MODEL_DIR        本地模型目录（可选，显式指定才使用）
  MODEL_INDEX_URL  模型索引 YAML 地址（默认：RapidOCR default_models.yaml）
  DET_SOURCE_NAME  det 源模型文件名（默认：ch_PP-OCRv5_mobile_det.onnx）
  REC_SOURCE_NAME  rec 源模型文件名（默认：ch_PP-OCRv5_rec_mobile_infer.onnx）
  CLS_SOURCE_NAME  cls 源模型文件名（默认：ch_ppocr_mobile_v2.0_cls_infer.onnx）
  DET_ASSET_NAME   det 目标文件名（默认：det.onnx）
  REC_ASSET_NAME   rec 目标文件名（默认：rec.onnx）
  CLS_ASSET_NAME   cls 目标文件名（默认：cls.onnx）
  CLS_URL          cls 模型下载直链（可选）
  DET_URL          det 模型下载直链（可选）
  REC_URL          rec 模型下载直链（可选）
  KEYS_URL         keys 文件下载直链（可选）

示例：
  MODEL_URL=... ./init.sh
  MODEL_DIR=/path/to/models ./init.sh
  MODEL_ARCHIVE=/path/to/models.7z ./init.sh
  MODEL_INDEX_URL=... ./init.sh
  DET_SOURCE_NAME=... REC_SOURCE_NAME=... DET_URL=... REC_URL=... KEYS_URL=... ./init.sh
EOF
}

log() {
  printf "[init] %s\n" "$*"
}

fail() {
  printf "[init] ERROR: %s\n" "$*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1
}

extract_7z() {
  local archive="$1"
  local out_dir="$2"

  if need_cmd 7z; then
    7z x -y "-o${out_dir}" "${archive}" >/dev/null
    return 0
  fi
  if need_cmd 7zz; then
    7zz x -y "-o${out_dir}" "${archive}" >/dev/null
    return 0
  fi
  if need_cmd unar; then
    unar -o "${out_dir}" "${archive}" >/dev/null
    return 0
  fi

  fail "缺少 7z/7zz/unar，无法解压 ${archive}"
}

download_file() {
  local url="$1"
  local dest="$2"

  if need_cmd curl; then
    curl -L --retry 3 --fail -o "${dest}" "${url}"
    return 0
  fi
  if need_cmd wget; then
    wget -O "${dest}" "${url}"
    return 0
  fi
  fail "缺少 curl 或 wget，无法下载 ${url}"
}

clean_cache() {
  log "清理缓存目录"
  rm -rf \
    "${ROOT_DIR}/.idea" \
    "${ROOT_DIR}/build" \
    "${ROOT_DIR}/app/build" \
    "${ROOT_DIR}/OcrLibrary/.cxx" \
    "${ROOT_DIR}/OcrLibrary/build"
}

ensure_dirs() {
  mkdir -p "${ASSETS_DIR}" "${SDK_NATIVE_DIR}" "${TMP_DIR}"
}

setup_opencv() {
  local archive="${TMP_DIR}/opencv-mobile-3.4.15-android.7z"
  local extract_dir="${TMP_DIR}/opencv"
  rm -rf "${extract_dir}"
  mkdir -p "${extract_dir}"

  if [ ! -f "${archive}" ]; then
    log "下载 OpenCV..."
    download_file "${OPENCV_URL}" "${archive}"
  else
    log "OpenCV 压缩包已存在，跳过下载"
  fi

  log "解压 OpenCV..."
  extract_7z "${archive}" "${extract_dir}"

  local src=""
  if [ -d "${extract_dir}/opencv-mobile-3.4.15-android/sdk/native" ]; then
    src="${extract_dir}/opencv-mobile-3.4.15-android/sdk/native"
  elif [ -d "${extract_dir}/opencv-mobile-3.4.15-android/native/jni" ]; then
    src="${extract_dir}/opencv-mobile-3.4.15-android/native"
  else
    local found
    found="$(find "${extract_dir}" -type d -path "*/sdk/native" -print -quit)"
    if [ -n "${found}" ]; then
      src="${found}"
    fi
  fi

  if [ -z "${src}" ]; then
    fail "未找到 OpenCV 的 native 目录结构"
  fi

  log "安装 OpenCV 到 ${SDK_NATIVE_DIR}"
  mkdir -p "${SDK_NATIVE_DIR}"
  cp -a "${src}/." "${SDK_NATIVE_DIR}/"
}

setup_onnxruntime() {
  local archive="${TMP_DIR}/onnxruntime-1.14.0-android-shared.7z"
  local extract_dir="${TMP_DIR}/onnxruntime"
  rm -rf "${extract_dir}"
  mkdir -p "${extract_dir}"

  if [ ! -f "${archive}" ]; then
    log "下载 onnxruntime..."
    download_file "${ORT_URL}" "${archive}"
  else
    log "onnxruntime 压缩包已存在，跳过下载"
  fi

  log "解压 onnxruntime..."
  extract_7z "${archive}" "${extract_dir}"

  local cmake_path
  cmake_path="$(find "${extract_dir}" -type f -name "OnnxRuntimeWrapper.cmake" -print -quit)"
  if [ -z "${cmake_path}" ]; then
    fail "未找到 OnnxRuntimeWrapper.cmake"
  fi

  local src
  src="$(dirname "${cmake_path}")"

  log "安装 onnxruntime 到 ${ORT_DIR}"
  rm -rf "${ORT_DIR}"
  mkdir -p "${ORT_DIR}"
  cp -a "${src}/." "${ORT_DIR}/"
}

collect_models() {
  local assets="${ASSETS_DIR}"
  local tmp_models_dir="${TMP_DIR}/models"
  local from_dir=""

  if [ -n "${MODEL_ARCHIVE}" ]; then
    log "解压模型压缩包：${MODEL_ARCHIVE}"
    rm -rf "${tmp_models_dir}"
    mkdir -p "${tmp_models_dir}"
    extract_7z "${MODEL_ARCHIVE}" "${tmp_models_dir}"
    from_dir="${tmp_models_dir}"
  elif [ -n "${MODEL_URL}" ]; then
    log "下载模型压缩包..."
    local archive="${TMP_DIR}/models.7z"
    download_file "${MODEL_URL}" "${archive}"
    rm -rf "${tmp_models_dir}"
    mkdir -p "${tmp_models_dir}"
    extract_7z "${archive}" "${tmp_models_dir}"
    from_dir="${tmp_models_dir}"
  elif [ -n "${MODEL_DIR}" ] && [ -d "${MODEL_DIR}" ]; then
    from_dir="${MODEL_DIR}"
  fi

  if [ -z "${from_dir}" ]; then
    local index_yaml="${TMP_DIR}/default_models.yaml"
    log "直接从模型索引下载"
    download_file "${MODEL_INDEX_URL}" "${index_yaml}"
    download_required_models "${index_yaml}" "${assets}"
    return 0
  fi

  local model_root="${from_dir}"
  if [ -d "${from_dir}/OcrLibrary/src/main/assets" ]; then
    model_root="${from_dir}/OcrLibrary/src/main/assets"
  fi

  log "复制模型到 ${assets}"
  cp -a "${model_root}/." "${assets}/"
}

download_required_models() {
  local index_yaml="$1"
  local out_dir="$2"

  download_model_as "${index_yaml}" "${CLS_SOURCE_NAME}" "${CLS_URL}" "${CLS_ASSET_NAME}" "${out_dir}"
  download_model_as "${index_yaml}" "${DET_SOURCE_NAME}" "${DET_URL}" "${DET_ASSET_NAME}" "${out_dir}"
  download_model_as "${index_yaml}" "${REC_SOURCE_NAME}" "${REC_URL}" "${REC_ASSET_NAME}" "${out_dir}"
  download_model_as "${index_yaml}" "${KEYS_FILE}" "${KEYS_URL}" "${KEYS_FILE}" "${out_dir}"
}

download_model_as() {
  local index_yaml="$1"
  local source_name="$2"
  local direct_url="$3"
  local target_name="$4"
  local out_dir="$5"

  if [ -f "${out_dir}/${target_name}" ]; then
    log "模型已存在，跳过下载：${target_name}"
    return 0
  fi

  if [ -f "${out_dir}/${source_name}" ] && [ "${source_name}" != "${target_name}" ]; then
    log "重命名模型：${source_name} -> ${target_name}"
    mv "${out_dir}/${source_name}" "${out_dir}/${target_name}"
    return 0
  fi

  local url=""
  if [ -n "${direct_url}" ]; then
    url="${direct_url}"
  else
    url="$(resolve_model_url_from_index "${index_yaml}" "${source_name}")"
  fi

  if [ -z "${url}" ]; then
    log "模型索引未找到：${source_name}"
    return 0
  fi

  if [ "${source_name}" = "${target_name}" ]; then
    log "下载模型：${target_name}"
    download_file "${url}" "${out_dir}/${target_name}"
    return 0
  fi

  local tmp_file="${out_dir}/.${target_name}.download"
  log "下载模型：${source_name} -> ${target_name}"
  download_file "${url}" "${tmp_file}"
  mv "${tmp_file}" "${out_dir}/${target_name}"
}

resolve_model_url_from_index() {
  local yaml="$1"
  local filename="$2"

  local url
  url="$(
    awk -v f="${filename}" '
      $1 == f ":" {found=1}
      found && $1 == "model_dir:" {print $2; exit}
    ' "${yaml}"
  )"

  printf "%s" "${url}"
}

verify_models() {
  local assets="${ASSETS_DIR}"
  local missing=0

  if [ ! -f "${assets}/${CLS_ASSET_NAME}" ]; then
    log "缺少 cls 模型：${CLS_ASSET_NAME}"
    missing=1
  fi

  if [ ! -f "${assets}/${DET_ASSET_NAME}" ]; then
    log "缺少 det 模型：${DET_ASSET_NAME}"
    missing=1
  fi

  if [ ! -f "${assets}/${REC_ASSET_NAME}" ]; then
    log "缺少 rec 模型：${REC_ASSET_NAME}"
    missing=1
  fi

  if [ ! -f "${assets}/${KEYS_FILE}" ]; then
    log "缺少 keys 文件：${KEYS_FILE}"
    missing=1
  fi

  if [ "${missing}" -ne 0 ]; then
    fail "模型不完整，无法继续"
  fi
}

main() {
  if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
    usage
    exit 0
  fi
  if [ "${1:-}" = "--clean" ]; then
    clean_cache
  fi

  ensure_dirs
  setup_opencv
  setup_onnxruntime
  collect_models
  verify_models

  log "初始化完成"
  log "Release 编译命令：./gradlew assembleRelease"
}

main "$@"