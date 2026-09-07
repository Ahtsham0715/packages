package com.sablekey.app.autofill

import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.service.autofill.Dataset
import android.view.WindowManager
import android.view.autofill.AutofillId
import android.view.autofill.AutofillManager
import android.view.autofill.AutofillValue
import android.widget.RemoteViews
import com.sablekey.app.R
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * The activity the autofill service launches so the user can unlock and choose.
 *
 * It runs the same Flutter app as [com.sablekey.app.MainActivity], but enters
 * at the `/autofill` route, which shows an unlock screen followed by a picker
 * filtered to the requesting site. When the user chooses, Dart calls `respond`
 * and this activity assembles the [Dataset] the platform is waiting for.
 *
 * `FLAG_SECURE` is set unconditionally here rather than following the user's
 * preference: this window displays credentials on behalf of another app, often
 * a browser, and is exactly the screen worth capturing.
 */
class AutofillHostActivity : FlutterActivity() {

    companion object {
        const val CHANNEL = "sablekey/autofill"

        const val EXTRA_MODE = "mode"
        const val MODE_FILL = "fill"
        const val MODE_SAVE = "save"

        const val EXTRA_WEB_DOMAIN = "webDomain"
        const val EXTRA_PACKAGE_NAME = "packageName"
        const val EXTRA_USERNAME_ID = "usernameId"
        const val EXTRA_PASSWORD_ID = "passwordId"
        const val EXTRA_OTP_ID = "otpId"
        const val EXTRA_CARD_NUMBER_ID = "cardNumberId"
        const val EXTRA_CARD_EXPIRY_ID = "cardExpiryId"
        const val EXTRA_CARD_CVV_ID = "cardCvvId"
        const val EXTRA_CARD_HOLDER_ID = "cardHolderId"
        const val EXTRA_WANTS_CARD = "wantsCard"
        const val EXTRA_SAVE_USERNAME = "saveUsername"
        const val EXTRA_SAVE_PASSWORD = "savePassword"
    }

    override fun getInitialRoute(): String = "/autofill"

    override fun onCreate(savedInstanceState: Bundle?) {
        window.setFlags(
            WindowManager.LayoutParams.FLAG_SECURE,
            WindowManager.LayoutParams.FLAG_SECURE
        )
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getRequest" -> result.success(describeRequest())
                    "respond" -> {
                        respondWithDataset(call.arguments as? Map<*, *>)
                        result.success(null)
                    }
                    "cancel" -> {
                        setResult(Activity.RESULT_CANCELED)
                        result.success(null)
                        finish()
                    }
                    "finishSave" -> {
                        setResult(Activity.RESULT_OK)
                        result.success(null)
                        finish()
                    }
                    // The picker shares its channel with the main app, which
                    // asks these two on the settings screen.
                    "isEnabled" -> result.success(isAutofillServiceEnabled())
                    "openSettings" -> {
                        openAutofillSettings()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun describeRequest(): Map<String, Any?> {
        val packageName = intent.getStringExtra(EXTRA_PACKAGE_NAME)
        return mapOf(
            "mode" to (intent.getStringExtra(EXTRA_MODE) ?: MODE_FILL),
            "webDomain" to intent.getStringExtra(EXTRA_WEB_DOMAIN),
            "packageName" to packageName,
            "appLabel" to packageName?.let(::labelForPackage),
            "username" to intent.getStringExtra(EXTRA_SAVE_USERNAME),
            "password" to intent.getStringExtra(EXTRA_SAVE_PASSWORD),
            "wantsPassword" to (autofillId(EXTRA_PASSWORD_ID) != null),
            "wantsCard" to intent.getBooleanExtra(EXTRA_WANTS_CARD, false)
        )
    }

    /**
     * Resolves a package name to the name a human would recognise, so the
     * picker can say "Signal" rather than "org.thoughtcrime.securesms".
     */
    private fun labelForPackage(packageName: String): String? = try {
        val manager = packageManager
        val info = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            manager.getApplicationInfo(
                packageName,
                PackageManager.ApplicationInfoFlags.of(0)
            )
        } else {
            @Suppress("DEPRECATION")
            manager.getApplicationInfo(packageName, 0)
        }
        manager.getApplicationLabel(info).toString()
    } catch (_: PackageManager.NameNotFoundException) {
        null
    }

    private fun respondWithDataset(arguments: Map<*, *>?) {
        if (arguments == null) {
            setResult(Activity.RESULT_CANCELED)
            finish()
            return
        }

        val presentation = RemoteViews(packageName, R.layout.autofill_dataset).apply {
            setTextViewText(R.id.autofill_title, getString(R.string.app_name))
            setTextViewText(R.id.autofill_subtitle, getString(R.string.autofill_filled))
            setImageViewResource(R.id.autofill_icon, R.mipmap.ic_launcher)
        }

        val builder = Dataset.Builder(presentation)
        var filledAnything = false

        fun fill(extra: String, value: String?) {
            val id = autofillId(extra) ?: return
            if (value.isNullOrEmpty()) return
            builder.setValue(id, AutofillValue.forText(value), presentation)
            filledAnything = true
        }

        fill(EXTRA_USERNAME_ID, arguments["username"] as? String)
        fill(EXTRA_PASSWORD_ID, arguments["password"] as? String)
        fill(EXTRA_OTP_ID, arguments["totp"] as? String)

        @Suppress("UNCHECKED_CAST")
        val card = arguments["card"] as? Map<String, String>
        if (card != null) {
            fill(EXTRA_CARD_NUMBER_ID, card["number"])
            fill(EXTRA_CARD_EXPIRY_ID, card["expiry"])
            fill(EXTRA_CARD_CVV_ID, card["cvv"])
            fill(EXTRA_CARD_HOLDER_ID, card["holder"])
        }

        if (!filledAnything) {
            // Returning an empty dataset makes the platform show an error. A
            // plain cancel is what the user's choice actually amounted to.
            setResult(Activity.RESULT_CANCELED)
            finish()
            return
        }

        val reply = Intent().apply {
            putExtra(AutofillManager.EXTRA_AUTHENTICATION_RESULT, builder.build())
        }
        setResult(Activity.RESULT_OK, reply)
        finish()
    }

    private fun autofillId(extra: String): AutofillId? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(extra, AutofillId::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(extra)
        }

    private fun isAutofillServiceEnabled(): Boolean {
        val manager = getSystemService(AutofillManager::class.java) ?: return false
        return manager.hasEnabledAutofillServices()
    }

    private fun openAutofillSettings() {
        val intent = Intent(android.provider.Settings.ACTION_REQUEST_SET_AUTOFILL_SERVICE)
            .setData(android.net.Uri.parse("package:$packageName"))
        try {
            startActivity(intent)
        } catch (_: Exception) {
            startActivity(Intent(android.provider.Settings.ACTION_SETTINGS))
        }
    }
}
