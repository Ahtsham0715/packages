import AuthenticationServices
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {

    /// Covers the window when the app is not frontmost.
    private var privacyOverlay: UIVisualEffectView?

    /// Whether the user has asked for screen privacy.
    private var secureModeEnabled = false

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        let controller = window?.rootViewController as! FlutterViewController

        FlutterMethodChannel(
            name: "sablekey/secure_screen",
            binaryMessenger: controller.binaryMessenger
        ).setMethodCallHandler { [weak self] call, result in
            self?.handleSecureScreen(call, result)
        }

        FlutterMethodChannel(
            name: "sablekey/autofill",
            binaryMessenger: controller.binaryMessenger
        ).setMethodCallHandler { [weak self] call, result in
            self?.handleAutofill(call, result)
        }

        GeneratedPluginRegistrant.register(with: self)
        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }

    // MARK: - Screen privacy

    private func handleSecureScreen(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        switch call.method {
        case "setSecure":
            let arguments = call.arguments as? [String: Any]
            secureModeEnabled = arguments?["enabled"] as? Bool ?? true
            if !secureModeEnabled { removeOverlay() }
            result(nil)

        case "copySensitive":
            guard let arguments = call.arguments as? [String: Any],
                  let value = arguments["value"] as? String else {
                result(FlutterError(code: "bad_args", message: "value is required", details: nil))
                return
            }
            let seconds = arguments["expiresInSeconds"] as? Int ?? 0
            copySensitive(value, expiresInSeconds: seconds)
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    /// Copies without letting the value leave the device.
    ///
    /// `localOnly` keeps Universal Clipboard from pushing the password to a
    /// nearby Mac or iPad, which would put it somewhere the user is not looking
    /// and did not consent to. The expiry is a second line of defence behind
    /// the app's own clear timer, and survives the app being killed.
    private func copySensitive(_ value: String, expiresInSeconds: Int) {
        var options: [UIPasteboard.OptionsKey: Any] = [.localOnly: true]
        if expiresInSeconds > 0 {
            options[.expirationDate] = Date().addingTimeInterval(TimeInterval(expiresInSeconds))
        }
        UIPasteboard.general.setItems([[kUTTypeUTF8PlainText: value]], options: options)
    }

    /// iOS provides no equivalent of Android's `FLAG_SECURE`; a determined user
    /// or an attacker holding an unlocked phone can always take a screenshot.
    /// What can be prevented is the snapshot the system takes for the app
    /// switcher, which is the one that persists on disk.
    override func applicationWillResignActive(_ application: UIApplication) {
        guard secureModeEnabled else { return }
        showOverlay()
    }

    override func applicationDidBecomeActive(_ application: UIApplication) {
        removeOverlay()
    }

    private func showOverlay() {
        guard privacyOverlay == nil, let window = window else { return }
        let effect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        let overlay = UIVisualEffectView(effect: effect)
        overlay.frame = window.bounds
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(overlay)
        privacyOverlay = overlay
    }

    private func removeOverlay() {
        privacyOverlay?.removeFromSuperview()
        privacyOverlay = nil
    }

    // MARK: - Autofill

    private func handleAutofill(_ call: FlutterMethodCall, _ result: @escaping FlutterResult) {
        switch call.method {
        case "isEnabled":
            checkExtensionEnabled(result)

        case "openSettings":
            // iOS has no deep link to the AutoFill provider list. Passwords
            // settings is the closest reachable destination; the app's own
            // instructions on screen carry the rest.
            if let url = URL(string: "App-Prefs:PASSWORDS"),
               UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url)
            } else if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
            result(nil)

        case "syncMirror":
            syncMirror(call.arguments as? [String: Any], result)

        case "clearMirror":
            SablekeyMirror.clear()
            result(true)

        // The picker flow is Android-only; on iOS the extension owns it.
        case "getRequest":
            result(nil)
        case "respond", "cancel", "finishSave":
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    private func checkExtensionEnabled(_ result: @escaping FlutterResult) {
        // There is no API to ask "is my credential provider selected?".
        // The presence of a written mirror is the closest honest proxy, and the
        // settings screen words it as "set up" rather than "enabled".
        result(SablekeyMirror.exists)
    }

    private func syncMirror(_ arguments: [String: Any]?, _ result: @escaping FlutterResult) {
        guard let payload = arguments?["entries"] as? String,
              let data = payload.data(using: .utf8) else {
            result(FlutterError(code: "bad_args", message: "entries is required", details: nil))
            return
        }
        do {
            let entries = try JSONDecoder().decode([SablekeyMirror.Entry].self, from: data)
            try SablekeyMirror.write(entries: entries)
            result(true)
        } catch {
            result(FlutterError(
                code: "mirror_failed",
                message: "Could not write the autofill mirror: \(error)",
                details: nil
            ))
        }
    }
}

/// `UIPasteboard.setItems` keys its dictionary by uniform type identifier
/// string, not by the `UTType` value type.
private let kUTTypeUTF8PlainText = "public.utf8-plain-text"
