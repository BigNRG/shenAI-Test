# Shen.AI SDK test apps

Three small apps for trying out the [Shen.AI SDK](https://github.com/mxlaboratories/shenai-sdk) (camera-based vital signs) on each platform:

| Platform | Folder | Stack | SDK dependency |
|---|---|---|---|
| Android | [`android/`](android/) | Kotlin, programmatic Views | `ai.shen:shenai-sdk:3.1.14` (Maven Central) |
| iOS | [`ios/`](ios/) | Swift, UIKit | `ShenaiSDK` 3.1.14 (Swift Package Manager) |
| Web | [`web/`](web/) | TypeScript + Vite | `@shenai/sdk@3.1.14` (npm) |

All three apps have the same screens:

1. **Home**: paste your API key (saved on the device), optionally set a user ID, then pick a mode.
2. **Measurement (SDK UI)**: the SDK's built-in flow (measurement, then results, then health risks). When it finishes, the app shows its own results summary.
3. **Measurement (Custom UI + live metrics)**: the SDK draws only the camera preview and face mask. The app shows status hints (lighting, face position, and so on), progress, and live HR, HRV, breathing, BP, stress and signal quality. It polls the SDK every 200 ms and has its own Start/Stop buttons.
4. **Dashboard**: the SDK's built-in measurements dashboard.
5. **Results**: heart rate, HRV, breathing rate, blood pressure, cardiac stress/workload, age/BMI estimates and signal quality, plus an **Open PDF report** button.

All modes use the `THIRTY_SECONDS_ALL_METRICS` preset with relaxed precision and some example health-risk factors. You can change this in each app's settings function.

## You need an API key

Get one from the [Shen.AI Developer Portal](https://developer.shen.ai). Keys can be tied to a platform, so check that the key is enabled for the platform you're testing. You can **paste the key into the app's home screen at runtime**, or set it at build time as described in each README. Never commit a real key.

## Quick start

```bash
# Web (desktop Chrome recommended)
cd web && npm install && npm run dev        # open http://localhost:5173

# Android (device with a camera, USB debugging on)
cd android && ./gradlew installDebug        # or open the folder in Android Studio

# iOS (physical iPhone; the simulator has no camera)
open ios/ShenAITest/ShenAITest.xcodeproj    # set your signing team, then Run
```

For details, see [`android/README.md`](android/README.md), [`ios/README.md`](ios/README.md) and [`web/README.md`](web/README.md).

## Changing the SDK version

- Android: `shenaiSdkVersion` in `android/gradle.properties`
- iOS: Xcode → project → Package Dependencies → ShenaiSDK (exact version), and `SHENAI_SDK_VERSION` in `ios/ShenAITest/Config.xcconfig` (display only)
- Web: `@shenai/sdk` in `web/package.json`, then `npm install`
