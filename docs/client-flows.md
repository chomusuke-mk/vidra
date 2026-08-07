# Client Flows

This document details the main interaction flows and lifecycle of the user interface in the client application (Flutter).

## 1. Boot Sequence and Configuration

The main entry point (`main.dart`) initializes asynchronous services before bringing up the user interface.

1. **Base Initialization:** Ensures Flutter widget binding (`WidgetsFlutterBinding.ensureInitialized()`), initializes `SharedPreferences`, and the local notifications service (`NotificationService.init()`).
2. **Dependency Injection:** Creates the `Provider` tree hierarchy. The `SystemController` is instantiated immediately.
3. **Engine (Backend) Launch:**
   - The `SystemController` assigns the dynamic port and token.
   - Creates the backend _Isolate_ (`backendIsolateMain`).
   - Begins extracting the Python binaries (this happens in parallel on the main thread with an `await SeriousPython.prepareApp()`).
4. **UI Validation:** The `App` component observes the state. If startup is not complete, it shows a circular loading indicator. Once ready, it loads the theme, language, and launches the `MainRouter`.

## 2. Main Router (`MainRouter`)

The `MainRouter` decides the main view by evaluating the state dictated by `SystemController`:

- **Missing Permissions (`missingPermissions`):** Shows the `PermissionsScreen` prompting the user for storage access (and notifications if applicable) required to download files.
- **Ready (`ready` or in regular progress):** Wraps the main view (`DownloadsScreen`) inside the `ShareIntentWrapper` widget.

## 3. Link Reception (Share Intent)

Vidra is capable of receiving links from other applications (e.g., "Share from YouTube" on mobile devices). This is handled in `ShareIntentWrapper`.

1. **Link Interception:** Using the `receive_sharing_intent` package, the application detects when it is launched with an incoming URL or when it receives a URL in the background.
2. **Transfer to Controller:** If the incoming text is a valid URL, it is sent to `SystemController.enqueueDownload(url, options)`.
3. **Communication to Isolate:** The `SystemController` packages the request and transmits it to the backend Isolate via the `SendPort`.
4. **Reflection in the UI:** The backend acknowledges receipt of the command and begins the download task. The state is polled or notified (depending on the REST/WebSocket pattern implemented), and the `DownloadsController` updates the view.

## 4. The Overlay System (Independent Isolate)

To interact with the application without completely leaving the context of other applications (very useful on Android), Vidra incorporates a "Quick Share Overlay".

1. **Secondary Entry Point:** In `main.dart`, there is the `@pragma("vm:entry-point") void overlayMain()` function.
2. **Isolation:** This is a completely independent Flutter tree running in its own Isolate, displaying the `QuickShareOverlay` screen.
3. **Restrictions:** Being a separate Isolate, it does not share memory or the main `Provider` hierarchy; it communicates with the central system via channels or ports (SendPort/ReceivePort) to quickly inject downloads without opening the full interface of the main application.

## 5. OTA (Over-The-Air) Updates

Vidra includes an integrated update manager (`UpdateController`).

1. **Check:** Queries the GitHub Releases API, checking the current version against remote versions.
2. **Engine Pause:** If the user decides to update, the application sends a `pause_for_update` command to the backend.
3. **Wait for Ack:** The UI waits for confirmation (`paused_ack`) from the Isolate to ensure there are no locked file descriptors or half-active downloads.
4. **Installation:** Proceeds with downloading and installing the new Vidra package or executable.
