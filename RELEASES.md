# Releases

1. Update the version and build number in `project.yml`, then run `xcodegen generate`.
2. Run `scripts/package.sh` to build the universal app, DMG and SHA256 checksum in `dist/`. The MIT license is included in the app and DMG.
3. Mount the DMG and verify the version, signature and English/German resources. Run both self-test modes against the packaged app.
4. Tag the source commit and attach the DMG and checksum to the GitHub release.

The app requires macOS 14 or later, supports Apple silicon and Intel, and is ad-hoc signed rather than notarized.
