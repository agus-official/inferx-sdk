Pod::Spec.new do |s|
  s.name             = 'llx_flutter'
  s.version          = '0.0.1'
  s.summary          = 'Flutter plugin for inferx-sdk (iOS)'
  s.description      = <<-DESC
    Flutter plugin bridging to inferx-sdk iOS Swift package (InferxLLMKit/InferxLLMNative).
  DESC
  s.homepage         = 'https://github.com/breen/inferx-sdk'
  s.license          = { :type => 'MIT' }
  s.author           = { 'Inferx' => 'support@inferx.ai' }
  s.source           = { :path => '.' }

  s.platform         = :ios, '12.0'
  s.swift_version    = '5.0'
  s.static_framework = true

  # Use local Vendor directory to host copied sources (prepared in prepare_command)
  s.source_files = [
    'Classes/**/*.{h,m,mm,swift}',
    'Vendor/InferxLLMKit/**/*.{swift}',
    'Vendor/InferxLLMNative/**/*.{h,m,mm}',
    'Vendor/CLLX/**/*.{h,c}'
  ]

  # Provide headers for C interface
  s.public_header_files = [
    'Vendor/CLLX/include/*.h',
    'Vendor/InferxLLMNative/include/*.h'
  ]

  # Link prebuilt llama framework copied into Vendor
  s.vendored_frameworks = 'Vendor/InferxLLMNative/llama.xcframework'

  s.requires_arc = true

  s.pod_target_xcconfig = {
    'ENABLE_BITCODE' => 'NO',
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'gnu++17',
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/Vendor/CLLX/include" "${PODS_TARGET_SRCROOT}/Vendor/InferxLLMNative/include"'
  }

  # Copy sources from repo to local Vendor directory at install time
  s.prepare_command = <<-CMD
    set -euo pipefail
    ROOT="$(pwd -P)"
    REPO_ROOT="$(cd "${ROOT}/../../../" && pwd -P)"
    SRC_KIT="${REPO_ROOT}/ios/llx-ios/Sources/InferxLLMKit"
    SRC_NATIVE="${REPO_ROOT}/ios/llx-ios/Sources/InferxLLMNative"
    SRC_CLLX="${REPO_ROOT}/ios/llx-ios/Sources/CLLX"
    DEST="${ROOT}/Vendor"
    rm -rf "${DEST}"
    mkdir -p "${DEST}/InferxLLMKit" "${DEST}/InferxLLMNative" "${DEST}/CLLX"
    rsync -a --delete "${SRC_KIT}/"    "${DEST}/InferxLLMKit/"
    rsync -a --delete "${SRC_NATIVE}/" "${DEST}/InferxLLMNative/"
    rsync -a --delete "${SRC_CLLX}/"   "${DEST}/CLLX/"
  CMD

  s.dependency 'Flutter'
end


