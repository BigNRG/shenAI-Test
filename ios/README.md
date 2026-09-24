# Shen.AI SDK – iOS test app

This is a Swift/UIKit app. The SDK comes through Swift Package Manager from
`https://github.com/mxlaboratories/ShenaiSDK.git`, pinned to **3.1.14**. Xcode resolves it when you open the project.

Requirements: Xcode 15+, and a **physical iPhone/iPad** on iOS 15+ (the simulator has no camera).

## Run

1. `open ShenAITest/ShenAITest.xcodeproj`
2. Set up signing. Pick one:
   - In Xcode: target **ShenAITest** → *Signing & Capabilities*. Choose your Team and change the bundle identifier to something unique, **or**
   - `cp ShenAITest/Secrets.example.xcconfig ShenAITest/Secrets.xcconfig` and set `DEVELOPMENT_TEAM` and `PRODUCT_BUNDLE_IDENTIFIER`. This file is git-ignored.
3. Select your device and press **Run**.
4. Paste your **iOS** API key on the home screen. It's saved in UserDefaults.

You can also provide the key at build time as `SHENAI_API_KEY` in `Secrets.xcconfig`, or as a `SHENAI_API_KEY` environment variable in the scheme (*Product → Scheme → Edit Scheme → Run → Arguments*).

## Files (`ShenAITest/ShenAITest/`)

- `ShenaiSession.swift`: API key storage, `InitializationSettings` per mode, SDK start/stop
- `HomeViewController.swift`: API key entry, camera permission, mode buttons
- `SessionViewController.swift`: hosts `ShenaiView`, both full screen and in the custom UI with live-metrics polling
- `ResultsViewController.swift`: results summary and PDF report
