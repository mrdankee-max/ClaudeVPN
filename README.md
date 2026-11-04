# ClaudeVPN Android project

This project keeps the supplied ClaudeVPN HTML interface and replaces the demo connect animation / fake traffic counters with a real sing-box VPN tunnel.

## Build from GitHub Actions

1. Create a GitHub repository.
2. Upload the contents of this project ZIP so `.github/workflows/build.yml` is at the repository root and `app_src/` is beside it.
3. Push/commit to the `main` branch, or open **Actions → Build ClaudeVPN APK → Run workflow**.
4. Wait for the workflow to finish successfully.
5. Open the completed run, find **Artifacts**, and download **ClaudeVPN-APK**.
6. Extract the ZIP artifact and install `app-release.apk` on your Android phone.

## First launch

Tap **Настроить подписку**, paste your subscription URL, and save it. The URL is stored locally in the app's preferences and is not written into the repository. Then tap the large central button and approve Android's VPN connection prompt.

The subscription is passed to sing-box. Multi-server subscriptions are handled by sing-box's automatic selector; the first version uses automatic selection rather than pretending that hard-coded country rows are real servers.

## Important notes

- This build targets Android ARM64 (`arm64-v8a`), which is suitable for most modern Android phones. If your device is 32-bit only, the workflow needs a different target.
- First build downloads the native sing-box library and may take several minutes.
- sing_box and sing-box are GPL-3.0-or-later. Keep their license notices and comply with the license if you redistribute a modified app.
- This is a starter project. It has not been run on your physical phone yet; if Actions reports a build error, share the failed log and it can be corrected.