# 📝 Changelog

All notable changes to the **[Vidra](https://github.com/chomusuke-mk/vidra)** project will be documented in this file.

---

## [4.1.1] - Bug Fixes

- **Missing Localization:** Fixed an issue where the localization for the cut video feature was missing, ensuring that users can view the feature in their preferred language.
- **Force KeyFrames Option:** Now this option is in fast cut modal, allowing users to enable or disable the force keyframes setting when trimming videos, providing more control over the cutting process.

## [4.1.0] - New Features

- **New Features:** Added cut video feature, allowing users to trim videos directly within the application. This feature provides a convenient way to edit videos without the need for external software, enhancing the overall functionality of the application.
- **Performance:** Improved performance of Dropdown menus, resulting in faster and more responsive interactions when navigating through options and settings.
- **UX:** Now click download card shows action buttons.
- **FFmpeg:** New version of FFmpeg, which includes various performance improvements and bug fixes, ensuring better media processing capabilities and support for a wider range of formats.
- **Bug Fixes:** Filename too long issue fixed, ensuring that users can save files with longer names without encountering errors or truncation issues.
- **Bug Fixes:** Sponsorblock remove now has correct time range, ensuring that the feature accurately removes sponsored segments from videos without affecting other content.
- **Bug Fixes:** Fix settings/rate-limit wrong file-selector.

## [4.0.0] - New Interface

- **New Interface:** The user interface has been redesigned to provide a more modern and intuitive experience. The new design focuses on usability, accessibility, and visual appeal, making it easier for users to navigate and interact with the application.
- **Enhanced User Experience:** The updated interface includes improved layouts, clearer navigation, and more responsive design elements, ensuring a seamless experience across different devices and screen sizes.
- **Automatic Download Missing Resources:** The application now automatically detects and downloads any missing resources required for the new interface, ensuring that users have access to all necessary components without manual intervention.
- **More buttons**: Add play, open folder for playlist and playlist entry. Add open folder for completed entry.
- **Bug Fixes:** Addressed various bugs and issues reported by users, enhancing the overall stability and reliability of the application.

## [3.1.0] - New Features

- **Quick Settings:** Added a new feature that allows users to quickly access and modify their download settings directly from the main interface, improving usability and efficiency.
- **Fix Details Buttons:** Now show action buttons in details view.
- **Android | Overlay permission Optional:** The overlay permission is now optional on Android, allowing users to choose whether to enable it based on their preferences and needs.
- **Bug Fix:** Pause/Cancel now are instantly applied to all entries in the queue, ensuring a more responsive and user-friendly experience when managing downloads.
- **yt-dlp:** Now app uses nightly version of yt-dlp by default, ensuring users have access to the latest features and improvements. The stable version can still be used if preferred.
- **Permissions:** Additional horizontal layout for permissions dialog on Android, improving the user experience when managing app permissions.

## [3.0.0] - Major Release

- **New OTA Engine:** Introduced a new Over-The-Air (OTA) technique that allows for hot-reloading of the backend without requiring shutting down backend processes. This enables seamless updates and reduces downtime during maintenance.
- **Enhanced Update Mechanism:** The new OTA technique supports dynamic module loading and unloading, allowing for more flexible and efficient updates to the backend services.
- **Info getter Improved:** Now first call to yt-dlp saves a .info.json file in the cache folder, which is used for downloading without re-calling http request. This reduces probability of being blocked by YouTube and improves download speed.
- **Bug Fix**: Fixed pause/cancel issue when downloading multiple entries. Now pause/cancel will be applied to all entries in the queue.
- **Bug Fix**: Fixed issue where download/update yt-dlp/yt-dlp-ejs failed because running conditions were not met. Now correctly wait for finishing downloading before valid PGP signs.

## [2.5.19]

- **Emergency Bug Fix**: Fix download error detection.

> [!WARNING]
>
> ### 🚨 URGENT ADVICE: YouTube Downloads Failing
>
> The current **`yt-dlp` stable version is blocked** by YouTube. **Please use the nightly version instead.**
>
> Press (?) if you don't know how to switch to the nightly version.
>
> _Alternative Workaround:_ Cookies from your browser also fix the YouTube download error. However, this is **not available in Android and Snap** because of the sandbox isolation. Please use a browser to export your cookies manually and import them into Vidra.

## [2.5.18]

- **Backend Bug Fixes**: Fixed pause when collecting entries, add cancel when waiting for selection. Fix losing entries selection when select in pausing state.
- **Color Fixes**: Pending entries now have correct color. Fix remaining entries color when re-downloading. Fix color of entries when downloading is paused.
- **Preventive Fixes**: Unique ID now get from unique counter in database instead of using max value of existing entries. This prevents issues when deleting entries and re-downloading them.

## [2.5.17]

- **Optimization**: Site packages are now precompiled to improve performance and reduce load times.

## [2.5.0]

- **Fixes**: Windows progress notification issue, now notification will be displayed correctly when downloading files on Windows platform.
- **Notifications**: Progress notifications are disabled on Linux, only show State notifications. This is due to the lack of support for progress notifications on Linux platforms.

## [2.4.0] - New Features

- **New QuickJS Version:** Updated the QuickJS engine to the latest version, enhancing performance and compatibility with modern JavaScript features.
- **New FFmpeg Version:** Upgraded the FFmpeg module to the latest version, improving media processing capabilities and support for a wider range of formats.

## [2.3.0] - New Features

- **Localization System:** Implemented a new localization system that allows users to select their preferred language, enhancing accessibility and user experience across different regions.
- **Performance Improvements:** Optimized the application's performance, resulting in faster load times and smoother interactions for users.
- **Bug Fixes:** Addressed various bugs and issues reported by users, improving overall stability and reliability of the application.

## [2.2.0] - New Features

- **Changelog Dialog:** Added a new dialog that displays the changelog for the current version, providing users with a clear overview of updates and changes.
- **Tutorial System:** Introduced a comprehensive tutorial system to guide users through the application's features and functionalities, enhancing user onboarding and experience.
- **Enhanced User Interface:** Improved the user interface for a more intuitive and seamless experience when interacting with the application.

## [2.1.1] - Better Logs

- **Logs level:** Current backend logging level is INFO.

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
