package com.sablekey.app

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PersistableBundle
import android.provider.Settings
import android.view.WindowManager
import android.view.autofill.AutofillManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private companion object {
        const val SECURE_SCREEN_CHANNEL = "sablekey/secure_screen"
        const val AUTOFILL_CHANNEL = "sablekey/autofill"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECURE_SCREEN_CHANNEL)
            .setMethodCallHandler { call, result -> handleSecureScreen(call, result) }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUTOFILL_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isEnabled" -> result.success(isAutofillServiceEnabled())
                    "openSettings" -> {
                        openAutofillSettings()
                        result.success(null)
                    }
                    // The main activity never serves a fill request; only
                    // AutofillHostActivity does. Answering null here keeps the
                    // Dart side's "am I in autofill mode?" check simple.
                    "getRequest" -> result.success(null)
                    "cancel", "finishSave", "respond" -> result.success(null)
                    else -> result.notImplemented()
                }
            }
    }

    private fun handleSecureScreen(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "setSecure" -> {
                val enabled = call.argument<Boolean>("enabled") ?: true
                if (enabled) {
                    window.setFlags(
                        WindowManager.LayoutParams.FLAG_SECURE,
                        WindowManager.LayoutParams.FLAG_SECURE
                    )
                } else {
                    window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                }
                result.success(null)
            }

            "copySensitive" -> {
                val value = call.argument<String>("value")
                if (value == null) {
                    result.error("bad_args", "value is required", null)
                    return
                }
                copySensitive(value)
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    /**
     * Copies text and tells the OS it is a secret.
     *
     * Since Android 13 the system shows a preview toast of whatever was
     * copied — which would put the password on screen at the exact moment the
     * user is trying not to show it. [ClipDescription.EXTRA_IS_SENSITIVE]
     * replaces the preview with a redacted placeholder, and keeps the value out
     * of clipboard history and out of cross-device sync.
     */
    private fun copySensitive(value: String) {
        val clipboard = getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        val clip = ClipData.newPlainText("Sablekey", value)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            clip.description.extras = PersistableBundle().apply {
                putBoolean("android.content.extra.IS_SENSITIVE", true)
            }
        }
        clipboard.setPrimaryClip(clip)
    }

    private fun isAutofillServiceEnabled(): Boolean {
        val manager = getSystemService(AutofillManager::class.java) ?: return false
        return manager.isEnabled && manager.hasEnabledAutofillServices()
    }

    private fun openAutofillSettings() {
        // Deep-links straight to "choose an autofill service" with Sablekey
        // preselected. Falls back to the top-level settings screen on the
        // handful of OEM builds that do not honour the action.
        val intent = Intent(Settings.ACTION_REQUEST_SET_AUTOFILL_SERVICE)
            .setData(Uri.parse("package:$packageName"))
        try {
            startActivity(intent)
        } catch (_: Exception) {
            startActivity(Intent(Settings.ACTION_SETTINGS))
        }
    }
}
