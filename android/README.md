# Shen.AI SDK – Android test app

This is a single-activity Kotlin app. The UI is built in code, so there are no XML layouts. The SDK comes from Maven Central as `ai.shen:shenai-sdk` (version in `gradle.properties`).

Requirements: Android Studio (or JDK 17 plus the Android SDK), and a **physical device** with a front camera (minSdk 26).

## Run

1. Open the `android/` folder in Android Studio and run the `app` configuration, **or** from the command line:
   ```bash
   ./gradlew installDebug
   adb shell am start -n com.shenai.test/.MainActivity
   ```
2. Paste your **Android** API key on the home screen. It's saved in SharedPreferences.

To set the key at build time instead, use any of these:

```bash
./gradlew installDebug -PshenaiApiKey=YOUR_KEY     # Gradle property
SHENAI_API_KEY=YOUR_KEY ./gradlew installDebug     # environment variable
echo "shenai.apiKey=YOUR_KEY" >> local.properties  # git-ignored file
```

## Files

- `app/src/main/java/com/shenai/test/MainActivity.kt`: all screens, SDK settings per mode, live-metrics polling, results
- `app/build.gradle`: SDK dependency and how the API key is injected into `BuildConfig`

Logs: `adb logcat -s ShenAITest`
