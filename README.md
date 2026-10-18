<p align="center">
  <img src="PlaylistReverser/Assets.xcassets/AppIcon.appiconset/icon_256x256@2x.png" width="128" height="128" alt="Playlist Reverser icon">
</p>

<h1 align="center">Playlist Reverser</h1>

A macOS app that reverses the order of your Apple Music playlists. Preview the result, then save it as a new
playlist, or reorder the original in place. English and German UI.

Reversing happens in memory. Nothing is written to Music until you confirm.

## Install

Requires macOS 14 or later (Apple silicon or Intel).

1. Download the DMG from the [releases](../../releases) page and drag the app to Applications.
2. The app is ad-hoc signed and not notarized, so the first launch is blocked. Open it once, then allow it under
   System Settings › Privacy & Security › Open Anyway.
3. When prompted, allow it to control Music (System Settings › Privacy & Security › Automation).

The release includes a SHA256 checksum. To verify your download, put both files in the same folder and run:

```sh
shasum -a 256 -c PlaylistReverser-1.0.0.dmg.sha256
```

## Use

Pick a playlist, press **Reverse Order** (⌘R), then **Save to Music…** (⌘S).

- **New Copy**: creates a new playlist in the shown order. The original is untouched.
- **Reorder Original**: creates a backup playlist first, then empties and refills the original in the new order.
  Attempts to restore from the backup if saving fails. If automatic recovery fails, keep the backup and recover from it in Music.
  Not available for smart playlists. Shared playlists change for everyone.

After saving, every position is checked against the expected order; a failed copy is removed again.

## Limitations

- Playlist artwork can't be copied; Music doesn't expose it to scripts. The copy gets Music's automatic cover.
- Smart playlists are saved as regular playlists.
- Creation date and play counts aren't carried over.

## Build

Needs Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) if you change `project.yml`.

    xcodegen generate
    open PlaylistReverser.xcodeproj
    scripts/package.sh        # universal DMG + SHA256 in dist/

Headless test against your real Music library (creates and removes a temporary playlist):

    "Playlist Reverser" --selftest "<playlist name>" [--rewrite]

## License

[MIT](LICENSE)

Not affiliated with Apple. Apple Music is a trademark of Apple Inc.
