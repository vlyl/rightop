#!/bin/zsh

set -euo pipefail

script_directory="${0:A:h}"
project_directory="${script_directory:h}"
output_directory="${project_directory}/dist"
app_path="${output_directory}/RightOp.app"

"${script_directory}/build-local.sh"

version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "${app_path}/Contents/Info.plist")"
dmg_path="${output_directory}/RightOp-${version}.dmg"

staging_directory="$(mktemp -d "${output_directory}/.rightop-dmg.XXXXXX")"
volume_directory="${staging_directory}/volume"
temporary_dmg="${staging_directory}/RightOp-${version}.dmg"

cleanup() {
  rm -rf "${staging_directory}"
}
trap cleanup EXIT

mkdir -p "${volume_directory}"
/usr/bin/ditto "${app_path}" "${volume_directory}/RightOp.app"
ln -s /Applications "${volume_directory}/Applications"
/usr/bin/ditto "${project_directory}/LICENSE" "${volume_directory}/LICENSE"

hdiutil create \
  -volname "RightOp ${version}" \
  -srcfolder "${volume_directory}" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  "${temporary_dmg}"

hdiutil verify "${temporary_dmg}"
mv -f "${temporary_dmg}" "${dmg_path}"

printf '\nDisk image ready:\n%s\n' "${dmg_path}"
/usr/bin/shasum -a 256 "${dmg_path}"
