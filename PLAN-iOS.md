# iOS Port Plan — Project Picori (The Minish Cap recomp) on iPhone

Goal: run The Legend of Zelda: The Minish Cap **natively** on an iPhone 16 Pro
Max (arm64), no emulator. Deliverable: an **unsigned `.ipa`** the user
re-signs with their own Apple ID via SideStore / AltStore.

**Verification status (2026-09-24): NOT yet compiled for iOS. No .ipa exists.
Everything below the "changes" section is real; the build is still
unverified until the GitHub Actions `iOS Build` workflow goes green on a
macOS runner. Do not tell the user it works until then.**

## How the port works (confirmed by reading the tree)

- Native entry: `port/port_main.c` → inits SDL3 → ROM → assets → audio →
  input → PPU → `AgbMain()`.
- Renderer: SDL3 `SDL_Renderer` (software PPU; optional SDL_GPU path). Touch
  overlay draws through the same renderer.
- Audio: agbplay / VirtuaAPU → SDL3 audio (native iOS backend at runtime).
- Build: `xmake.lua` (also drives the Android Gradle packaging).
- All state is CWD-relative: `config.json`, `tmc.sav`, quicksaves, `assets/`
  cache, `rom_data/`, `bugreports/`, and the installed `baserom.gba`.
- ROM flow (already mobile-ready): hash-validates USA/EU/JP ROMs, offers a
  file picker, installs the chosen ROM as `baserom.gba`, extracts the asset
  cache on first boot. **No Nintendo assets are ever packaged in the app.**
- Touch controls already exist (`port/port_touch_controls.cpp`): floating
  joystick or d-pad, A/B/R/L, Start/Select, multitouch, SDL-drawn overlay,
  settings button — previously gated to `__ANDROID__` only.

## iOS changes made (this tree)

1. `port/port_touch_controls.cpp` — implementation guard is now
   `#if defined(__ANDROID__) || defined(TMC_TOUCH_UI)`; xmake defines
   `TMC_TOUCH_UI` for the `iphoneos` platform.
2. `port/port_main.c`
   - `<SDL3/SDL_main.h>` now included for `SDL_PLATFORM_IOS` too (needed:
     SDL3's UIKit glue invokes `SDL_main`).
   - New `SDL_PLATFORM_IOS` block at startup: `SDL_GetPrefPath("picori",
     "tmc")` + `chdir()` there. iOS starts the app with CWD at the
     read-only bundle; one chdir makes every CWD-relative file land in
     `~/Library/Application Support/picori/tmc/` (writable, backed up).
3. `xmake.lua`
   - `iphoneos` platform branch on target `tmc_pc`: `set_kind("binary")`,
     `set_targetdir("build/ios")`, `add_defines("TMC_TOUCH_UI")`.
   - libpng+zlib built from source for `iphoneos` (no system pkgs in the
     iOS SDK), same as Android.
   - RetroAchievements + libcurl disabled for `iphoneos` (no libcurl in the
     iOS SDK), same as Android.
   - OpenMP flag skipped for `iphoneos` (no OpenMP runtime in the iOS SDK;
     the PPU's mode-1 scanline pragma degrades to a serial loop — slower
     but visually identical).
   - Desktop launcher (GUILITE) skipped on iOS — unverified package for
     the iphoneos toolchain; iOS uses the SDL prelaunch screen.
4. `ios/Info.plist` (new) — bundle id `dev.picori.tmc`, executable
   `tmc_pc`, landscape-only, fullscreen, `MinimumOSVersion 15.0`,
   `ITSAppUsesNonExemptEncryption=false`, launch screen stub.
5. `ios/package_ipa.sh` (new) — wraps `build/ios/tmc_pc` into
   `Payload/TMC.app`, stamps `CFBundleShortVersionString` from
   `TMC_PC_VERSION` in `xmake.lua`, zips unsigned `tmc-ios.ipa`.
6. `.github/workflows/ios.yaml` (new) — macOS-14 runner: submodule init
   (same token pattern as `_build.yaml`), xmake v3.0.8 (pinned, same
   reason as `_build.yaml`), `xmake f -y -p iphoneos -a arm64`,
   `xmake build -y tmc_pc`, package, upload `tmc-ios-unsigned` artifact.

Deliberately left as-is for the first iOS build (all degrade safely):
- Update checker: POSIX path is `popen("curl …")`; no `curl` binary on iOS
  → fails closed, no dialog, no crash.
- Apple TTS: iOS has no `say` CLI → backend probe finds nothing → no-op.
- Discord RPC / crash backtrace / shm framebuffer: desktop/`__APPLE__`-macOS
  guarded; inert on iOS.
- ImGui prelaunch screen: SDL3+SDL_Renderer backend already, kept.
- SDL_GPU path stays off by default (SDL_Renderer = Metal on iOS anyway).

## Install flow (user side)

1. User installs the unsigned `.ipa` via SideStore/AltStore (re-signs with
   their Apple ID).
2. First launch: the built-in ROM picker (`SDL_ShowOpenFileDialog`) opens;
   user picks their own legally-dumped Minish Cap GBA ROM → hash-checked →
   installed as `baserom.gba` in the writable data dir.
3. Asset cache extracts from the ROM on first boot; `config.json` and
   `tmc.sav` persist in Application Support.

## Risks / unknowns (to verify on CI + device)

- **Compile**: SDL3 + all deps building for `iphoneos` under xmake on a
  macOS runner is unverified. Highest-risk unknowns: the xmake `libsdl3`
  package's iOS framework linkage, and any Apple-Clang-strictness issue in
  the port sources. The workflow's first green run settles this.
- **File picker on iOS**: `SDL_ShowOpenFileDialog` on iOS presents a
  document picker; whether the returned path is directly readable by the
  existing `SDL_LoadFile` copy flow needs a device test.
- **Touch layout**: overlay tuned for Android landscape; usable on iPhone
  but may want iPhone-specific sizing later.
- **Backgrounding**: no `SDL_EVENT_DID_ENTER_BACKGROUND` handling yet —
  autosave covers progress, but a proper pause-on-background is future work.
- **Performance**: desktop defaults (widescreen 384px, color correction)
  are on; A18 Pro should handle the software PPU, but thermals/battery are
  unmeasured. Tunables live in the F8 port settings menu.

## Commands

```bash
# from the repo root, on a Mac with Xcode:
xmake f -p iphoneos -a arm64 -y
xmake build -y tmc_pc
bash ios/package_ipa.sh          # -> tmc-ios.ipa (unsigned)
```

## TODO

- [ ] Get `.github/workflows/ios.yaml` green (real compile check).
- [ ] Device test: picker, first-boot asset extraction, touch overlay,
      audio, save persistence.
- [ ] Pause-on-background + app-icon (asset catalog needs an Xcode
      project; sideloading works without it).
