# Privacy Policy for Vidra

**Effective Date:** August 7, 2026

## 1. Introduction

Welcome to **Vidra**. We are deeply committed to protecting your privacy. This Privacy Policy explains our approach to data handling.

Vidra is an open-source, cross-platform media downloader built to run entirely on your local device. **Our core principle is simple: we do not collect, store, share, transmit, or monetize any of your personal data.**

## 2. Data Collection and Usage

**We do not collect any personal information.**
Vidra operates locally on your machine or mobile device. There are no tracking scripts, no analytics, no crash reporting SDKs, and no telemetry built into the application. We do not know who you are, what you search for, what you download, or how you use the application.

## 3. Local Storage

To function properly, Vidra stores certain configuration and state data locally on your device. This includes:

- **Download History:** Records of the videos or playlists you have downloaded.
- **App Preferences:** Your settings (e.g., preferred download formats, resolution, UI theme).

All of this data is stored strictly on your device's local storage (using local databases or preference files). **This data never leaves your device** and is never synced to our servers (because we do not have any servers). You have full control over this data and can delete it at any time by clearing the application data or uninstalling the app.

## 4. Network Activity and Third-Party Services

While Vidra itself does not track you, the core functionality of the app requires making direct connections to the internet:

- **Downloading Media:** Vidra communicates directly with third-party video hosting platforms (e.g., YouTube, Vimeo, etc.) to fetch metadata and download media. These requests are made from your IP address directly to the service provider.
- **Third-Party Policies:** When you download content from a third-party service, you are subject to that service's privacy policy and terms of service. They will be able to see your IP address and the requests you make. Vidra is merely a client executing these requests locally on your behalf.

Vidra internally utilizes open-source tools such as `yt-dlp` and `FFmpeg` to process downloads. These tools also operate entirely locally and do not report usage data back to us.

## 5. Required Device Permissions

Depending on your operating system (Android, Windows, Linux, macOS), Vidra may request certain permissions to function:

- **Storage / Filesystem Access:** Required to save the downloaded media files to your device and to read them.
- **Network / Internet Access:** Required to connect to third-party websites to download your requested content.

These permissions are used strictly for the application's core functionality.

## 6. Children's Privacy

Because we do not collect any personal data from anyone, our application is safe for all ages. However, please be aware that the internet services you connect to through Vidra may have their own age restrictions and content policies.

## 7. Changes to This Privacy Policy

We may update this Privacy Policy from time to time. Since the app does not collect data, any changes will likely reflect new features or regulatory requirements. We will notify you of any changes by posting the new Privacy Policy in this repository and updating the "Effective Date" at the top.

## 8. Contact Us

If you have any questions or concerns about this Privacy Policy, or if you want to inspect the source code to verify our claims, please visit our repository:

- **GitHub Repository:** [https://github.com/chomusuke-mk/vidra](https://github.com/chomusuke-mk/vidra)
- **Email:** <7k9mc4urn@mozmail.com>
