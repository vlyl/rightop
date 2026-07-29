# RightOp

![RightOp app icon](Artwork/RightOpIcon-master.png)

RightOp is an open-source macOS Finder Sync extension that adds practical file
operations directly to Finder's context menu. It is a native SwiftUI + AppKit
project with no third-party runtime dependencies.

The product direction was inspired by the breadth of
[iRightMouse](https://www.better365.cn/irightmouse.html), but the interface,
implementation, icon, and source in this repository are original.

## Included actions

- Copy containing-directory paths, names, or shell-escaped paths
- Open the current directory in Terminal, iTerm2, or Warp
- Create uniquely named `.txt` and `.md` files in the current folder
- Hide or unhide selected items
- Copy SHA-256 or MD5 checksums
- Permanently delete selected items, with confirmation enabled by default

Every action can be enabled or disabled in the containing app. The Finder menu
reads the shared preference each time it opens.

RightOp intentionally leaves native operations—such as Copy as Pathname, Open
With, Share/AirDrop, Duplicate, and New Folder with Selection—to Finder.

## Requirements

- macOS 13 or later
- Xcode 16 or later

An Apple account is **not required** to build and use RightOp on your own Mac.
The local-build script uses an ad-hoc signature, preserving the sandbox and App
Group entitlements needed by the app and Finder extension.

## Build locally without an Apple account

From Terminal, run:

```sh
cd /path/to/rightop
./Scripts/build-local.sh
```

The signed application is created at `dist/RightOp.app`.

## Install and enable

1. Make sure RightOp is not already running.
2. Drag `dist/RightOp.app` into your `/Applications` folder.
3. Open RightOp from Applications. If macOS presents a security prompt,
   Control-click the app, choose **Open**, then confirm **Open**.
4. Click **Enable Extension** in the app. macOS opens the Finder Extensions
   management screen; switch RightOp on.
5. Click **Choose Folder** and grant access to your Home folder. Add external
   volumes separately if you want file-changing actions there. The authorization
   is stored as a macOS security-scoped bookmark.
6. Right-click a file, folder, or empty space in a Finder window. RightOp's
   enabled actions appear directly after Finder's built-in actions.

Keep the app at a stable path after enabling the extension. Ad-hoc signing is
intended for local use; it is not notarized for distribution to other Macs.

If Finder has cached an older development build, disable and re-enable RightOp,
or run:

```sh
pluginkit -r /path/to/old/RightOp.app
pluginkit -a /path/to/new/RightOp.app
killall Finder
```

Only run those commands against paths you have verified.

## Build with an Apple development team

This is optional for local use. If you later join the Apple Developer Program:

1. Open `RightOp.xcodeproj` in Xcode.
2. Select your development team for both the **RightOp** and
   **RightOpFinderExtension** targets.
3. If your team already owns different identifiers, change both bundle
   identifiers and the App Group. Keep the App Group identical in:
   - `Shared/AppConstants.swift`
   - `RightOp/RightOp.entitlements`
   - `RightOpFinderExtension/RightOpFinderExtension.entitlements`
4. Run the **RightOp** scheme.

## Tests

The file-naming, path-formatting, and checksum logic is also exposed as a small
Swift package:

```sh
swift test
```

The full application and Finder extension are built through Xcode:

```sh
xcodebuild \
  -project RightOp.xcodeproj \
  -scheme RightOp \
  -configuration Debug \
  build
```

## Project structure

```text
RightOp/                  SwiftUI containing app and settings
RightOpFinderExtension/   Finder Sync menu and action handlers
Shared/                   Shared preferences and testable file utilities
Tests/                    Swift package tests for core logic
Artwork/                  Original high-resolution app icon source
```

Finder Sync only offers menus inside registered directories. RightOp registers
the filesystem root so its menu is available in normal Finder locations and
mounted volumes. The extension remains sandboxed: operations that read or modify
contents only work inside folders the user has explicitly authorized. macOS
privacy controls and volume permissions still apply.

### Safety

“Permanently Delete” calls `FileManager.removeItem` and bypasses the Trash.
Confirmation is on by default and the action can be removed from the Finder menu
entirely. Disabling confirmation is intentionally possible for power users, but
it is not recommended.

## License

MIT — see [LICENSE](LICENSE).
