# 📝 Changelog

All notable changes to the **[Vidra](https://github.com/chomusuke-mk/vidra)** project will be documented in this file.

---

## [2.1.0] - New Features

### ⚡️ New Features

- **Download Actions:** Introduced support for download actions, allowing users to manage and customize their download processes more effectively.
- **Enhanced User Interface:** Improved the user interface for a more intuitive and seamless experience when interacting with download actions.

## [2.0.1] - Bug Fix

### 🐛 Bug Fixes

- **Notifications:** Fixed an issue where notifications were not being displayed correctly on certain platforms.

## [2.0.0] - Major Release

### 🚀 Features

- **Full Playlist Support:** Added comprehensive support for downloading complete playlists.
- **Universal Platform Compatibility:** Full support for all platforms compatible with `yt-dlp`.
- **QuickJS & FFmpeg Integration:** Introduced support for downloads utilizing QuickJS (via [vidra-quickjs](https://github.com/chomusuke-mk/vidra-quickjs)) and FFmpeg modules (via [vidra-ffmpeg](https://github.com/chomusuke-mk/vidra-ffmpeg)).
- **OTA Updates:** Added Over-The-Air (OTA) update capabilities for `yt-dlp` and `yt-dlp-ejs`, enabling direct updates from the nightly release channel.
- **Global i18n & Localization:** English is now established as the official base language, featuring an automated translation system to support all other languages seamlessly.

### 🔒 Security

- **Cryptographic Validation:** `yt-dlp` OTA updates are now strictly validated using public key signatures to guarantee distribution integrity and secure updates.

### ⚡️ Performance & Optimizations

- **Massive Engine Optimizations:** Significant performance boosts across both the Vidra client and the backend infrastructure.
- **Leaner Backend Ecosystem:** Drastically reduced the number of backend dependencies for faster and lighter execution.

### 🛠 Refactoring & Architecture

- **Complete Client Rebuild:** Vidra was rebuilt from the ground up utilizing a highly structured programming architecture for better scalability.
- **Backend Separation:** The backend has been decoupled and moved to its own dedicated repository: [vidra-backend](https://github.com/chomusuke-mk/vidra-backend).
- **Flutter-First Approach:** Successfully reduced and eliminated legacy native code, replacing it entirely with robust Flutter packages for improved cross-platform maintainability.

### 🎨 UI & UX Improvements

- **Enhanced Responsiveness:** Smoother and more adaptive user interface behavior across devices.
- **Robust Error Handling:** Improved error capturing mechanisms and more informative user-facing messages.
