#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SDK_NATIVE_DIR="${ROOT_DIR}/OcrLibrary/src/sdk/native"
ORT_DIR="${ROOT_DIR}/OcrLibrary/src/main/onnxruntime-shared"
JNILIBS_DIR="${ROOT_DIR}/OcrLibrary/src/main/jniLibs"
TMP_DIR="${ROOT_DIR}/.tmp/init"

OPENCV_URL="https://gitee.com/benjaminwan/ocr-lite-android-ncnn/attach_files/843219/download/opencv-mobile-3.4.15-android.7z"
ORT_URL="https://github.com/RapidAI/OnnxruntimeBuilder/releases/download/1.14.0/onnxruntime-1.14.0-android-shared.7z"

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

  if need_cmd 7zz; then
    7zz x -y "-o${out_dir}" "${archive}" >/dev/null
    return 0
  fi
  if need_cmd 7z; then
    7z x -y "-o${out_dir}" "${archive}" >/dev/null
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
    "${SDK_NATIVE_DIR}" \
    "${ORT_DIR}" \
    "${TMP_DIR}" \
    "${ROOT_DIR}/.idea" \
    "${ROOT_DIR}/build" \
    "${ROOT_DIR}/app/build" \
    "${ROOT_DIR}/OcrLibrary/.cxx" \
    "${ROOT_DIR}/OcrLibrary/build"
}

ensure_dirs() {
  mkdir -p "${SDK_NATIVE_DIR}" "${TMP_DIR}"
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
  local archive="${TMP_DIR}/onnxruntime-android-shared.7z"
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

sync_onnxruntime_jni_libs() {
  local abis=("armeabi-v7a" "arm64-v8a" "x86" "x86_64")
  local copied=0

  for abi in "${abis[@]}"; do
    local src="${ORT_DIR}/${abi}/lib/libonnxruntime.so"
    local dst_dir="${JNILIBS_DIR}/${abi}"
    if [ ! -f "${src}" ]; then
      log "缺少 onnxruntime so: ${src}"
      continue
    fi
    mkdir -p "${dst_dir}"
    cp -f "${src}" "${dst_dir}/"
    copied=$((copied + 1))
  done

  if [ "${copied}" -eq 0 ]; then
    fail "未找到任何可用的 libonnxruntime.so，无法同步到 jniLibs"
  fi

  log "已同步 onnxruntime so 到 ${JNILIBS_DIR}"
}

main() {
  clean_cache

  ensure_dirs
  setup_opencv
  setup_onnxruntime
  sync_onnxruntime_jni_libs

  log "清理临时目录"
  rm -rf "${TMP_DIR}"

  log "初始化完成"
  log "Release 编译命令：./gradlew assembleRelease"
}

main "$@"