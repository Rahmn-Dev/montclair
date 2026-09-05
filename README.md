
# Montclair
<img width="124" height="124" alt="white" src="https://github.com/user-attachments/assets/b2329bcf-6042-444b-b37c-c0e4cde842cf" />

A deliberately small, native macOS browser built with AppKit and the system WebKit engine.

## UI
<img width="1920" height="1280" alt="453_1x_shots_so" src="https://github.com/user-attachments/assets/9e2769fb-1916-4f75-9521-bf76afc50b6f" />
<img width="1920" height="1280" alt="71_1x_shots_so" src="https://github.com/user-attachments/assets/bcb26f52-ffbe-4383-a089-65ba33cbba30" />

https://github.com/user-attachments/assets/a035aeb0-d1bb-41b8-8853-e593d4f9b3d6

loading bar

https://github.com/user-attachments/assets/84337b27-c81f-400c-814c-5feb8fd460ab

tab section


## Included

- Multi-tab browsing
- URL/search field using Google Search
- Back, forward, reload/stop, and swipe navigation
- Native WebKit content blocking
- Private windows with isolated, in-memory cookies and website data (`⌘⇧N`)
- Private sessions never enter history or session restore
- Automatic release of background tabs after 10 minutes
- Zero third-party dependencies

## Build

```sh
chmod +x build-app.sh
./build-app.sh
open dist/Montclair.app
```

Requires macOS 14+ and Xcode Command Line Tools. This is an unsigned development build; the script applies ad-hoc signing for local use.

## Verification

```sh
# Release build and ad-hoc signature
./build-app.sh
codesign --verify --deep --strict dist/Montclair.app

# Browser state and privacy regression tests
dist/Montclair.app/Contents/MacOS/Montclair --feature-test
dist/Montclair.app/Contents/MacOS/Montclair --privacy-test
dist/Montclair.app/Contents/MacOS/Montclair --self-test

# Library persistence tests
xcrun swiftc Sources/Montclair/BrowserLibrary.swift Scripts/library-tests.swift -o /tmp/montclair-library-tests
/tmp/montclair-library-tests
```

## Lightweight principles

The app uses the WebKit already shipped with macOS, avoids a bundled JavaScript runtime, and releases inactive web views. Memory measurements must include the related WebKit processes, not only the `Montclair` process.
