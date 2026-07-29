#!/bin/zsh

set -euo pipefail

script_directory="${0:A:h}"
project_directory="${script_directory:h}"
derived_data_directory="${project_directory}/.build/RightOpDerivedData"
output_directory="${project_directory}/dist"
built_app="${derived_data_directory}/Build/Products/Release/RightOp.app"
extension_entitlements="${project_directory}/RightOpFinderExtension/RightOpFinderExtension.entitlements"
app_entitlements="${project_directory}/RightOp/RightOp.entitlements"

command -v xcodebuild >/dev/null
command -v codesign >/dev/null

mkdir -p "${output_directory}"
staging_directory="$(mktemp -d "${output_directory}/.rightop-local.XXXXXX")"
staged_app="${staging_directory}/RightOp.app"
installed_app="${output_directory}/RightOp.app"

cleanup() {
  rm -rf "${staging_directory}"
}
trap cleanup EXIT

cd "${project_directory}"

xcodebuild \
  -quiet \
  -project RightOp.xcodeproj \
  -scheme RightOp \
  -configuration Release \
  -derivedDataPath "${derived_data_directory}" \
  CODE_SIGNING_ALLOWED=NO \
  build

/usr/bin/ditto "${built_app}" "${staged_app}"

/usr/bin/codesign \
  --force \
  --sign - \
  --timestamp=none \
  --entitlements "${extension_entitlements}" \
  "${staged_app}/Contents/PlugIns/RightOpFinderExtension.appex"

/usr/bin/codesign \
  --force \
  --sign - \
  --timestamp=none \
  --entitlements "${app_entitlements}" \
  "${staged_app}"

/usr/bin/codesign --verify --deep --strict --verbose=2 "${staged_app}"

if [[ -e "${installed_app}" ]]; then
  mv "${installed_app}" "${staging_directory}/previous-RightOp.app"
fi
mv "${staged_app}" "${installed_app}"

printf '\nLocal build ready:\n%s\n' "${installed_app}"
printf 'No Apple account or development certificate was used.\n'
