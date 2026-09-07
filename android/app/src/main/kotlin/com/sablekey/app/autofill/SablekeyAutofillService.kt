package com.sablekey.app.autofill

import android.app.PendingIntent
import android.content.Intent
import android.os.Build
import android.os.CancellationSignal
import android.service.autofill.AutofillService
import android.service.autofill.Dataset
import android.service.autofill.FillCallback
import android.service.autofill.FillRequest
import android.service.autofill.FillResponse
import android.service.autofill.SaveCallback
import android.service.autofill.SaveInfo
import android.service.autofill.SaveRequest
import android.widget.RemoteViews
import com.sablekey.app.R
import java.util.concurrent.atomic.AtomicInteger

/**
 * Sablekey's Android autofill provider.
 *
 * # The design in one paragraph
 *
 * This service never sees a decrypted credential. It runs in the background,
 * outside any unlocked session, so anything it could read would have to be
 * stored in a form readable without the master password — which is exactly what
 * this app exists to avoid. So it answers every request with a single *locked*
 * dataset: a row that says "Unlock Sablekey" and carries an authentication
 * intent. Tapping it launches [AutofillHostActivity], the user unlocks and
 * picks an entry there, and that activity returns the filled dataset. The vault
 * is decrypted only inside the app process, only while the picker is up.
 *
 * The cost is one extra tap compared with managers that keep a plaintext cache.
 * That tap is the product.
 */
class SablekeyAutofillService : AutofillService() {

    private val requestCounter = AtomicInteger(0)

    override fun onFillRequest(
        request: FillRequest,
        cancellationSignal: CancellationSignal,
        callback: FillCallback
    ) {
        var cancelled = false
        cancellationSignal.setOnCancelListener { cancelled = true }

        // The last context is the current state of the form; earlier ones are
        // previous steps of a multi-screen flow.
        val structure = request.fillContexts.lastOrNull()?.structure
        if (structure == null) {
            callback.onSuccess(null)
            return
        }

        val parsed = StructureParser.parse(structure)
        if (!parsed.isFillable || cancelled) {
            // Returning null rather than an empty response tells the platform
            // we have nothing, so it does not show an empty Sablekey row on
            // every unrelated text box in the system.
            callback.onSuccess(null)
            return
        }

        val response = try {
            buildLockedResponse(parsed)
        } catch (error: Exception) {
            callback.onFailure(error.message)
            return
        }

        callback.onSuccess(response)
    }

    private fun buildLockedResponse(parsed: ParsedStructure): FillResponse {
        val presentation = RemoteViews(packageName, R.layout.autofill_dataset).apply {
            setTextViewText(R.id.autofill_title, getString(R.string.autofill_unlock_title))
            setTextViewText(
                R.id.autofill_subtitle,
                parsed.target ?: getString(R.string.autofill_unlock_subtitle)
            )
            setImageViewResource(R.id.autofill_icon, R.mipmap.ic_launcher)
        }

        val authIntent = Intent(this, AutofillHostActivity::class.java).apply {
            putExtra(AutofillHostActivity.EXTRA_MODE, AutofillHostActivity.MODE_FILL)
            putExtra(AutofillHostActivity.EXTRA_WEB_DOMAIN, parsed.webDomain)
            putExtra(AutofillHostActivity.EXTRA_PACKAGE_NAME, parsed.packageName)
            putExtra(AutofillHostActivity.EXTRA_USERNAME_ID, parsed.usernameId)
            putExtra(AutofillHostActivity.EXTRA_PASSWORD_ID, parsed.passwordId)
            putExtra(AutofillHostActivity.EXTRA_OTP_ID, parsed.otpId)
            putExtra(AutofillHostActivity.EXTRA_CARD_NUMBER_ID, parsed.cardNumberId)
            putExtra(AutofillHostActivity.EXTRA_CARD_EXPIRY_ID, parsed.cardExpiryId)
            putExtra(AutofillHostActivity.EXTRA_CARD_CVV_ID, parsed.cardCvvId)
            putExtra(AutofillHostActivity.EXTRA_CARD_HOLDER_ID, parsed.cardHolderId)
            putExtra(AutofillHostActivity.EXTRA_WANTS_CARD, parsed.hasCardFields)
        }

        val pendingIntent = PendingIntent.getActivity(
            this,
            requestCounter.incrementAndGet(),
            authIntent,
            // MUTABLE because the platform writes the fill response into this
            // intent's result. CANCEL_CURRENT so a stale request for a
            // different form can never be reused.
            PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_CANCEL_CURRENT
        )

        val dataset = Dataset.Builder(presentation).apply {
            // With authentication set, the values must be null: the real values
            // arrive later, from the activity. Every field the parser found is
            // listed so the platform knows which boxes this row can fill.
            for (id in parsed.allIds) {
                setValue(id, null, presentation)
            }
            setAuthentication(pendingIntent.intentSender)
        }.build()

        return FillResponse.Builder()
            .addDataset(dataset)
            .apply { buildSaveInfo(parsed)?.let { setSaveInfo(it) } }
            .build()
    }

    /**
     * Describes what the platform should offer to save after a sign-up or a
     * password change.
     */
    private fun buildSaveInfo(parsed: ParsedStructure): SaveInfo? {
        val required = mutableListOf<android.view.autofill.AutofillId>()
        var type = 0

        parsed.passwordId?.let {
            required += it
            type = type or SaveInfo.SAVE_DATA_TYPE_PASSWORD
        }
        if (parsed.cardNumberId != null) {
            required += parsed.cardNumberId
            type = type or SaveInfo.SAVE_DATA_TYPE_CREDIT_CARD
        }
        if (required.isEmpty()) return null

        val optional = listOfNotNull(
            parsed.usernameId,
            parsed.cardExpiryId,
            parsed.cardCvvId,
            parsed.cardHolderId
        ).toTypedArray()

        if (type and SaveInfo.SAVE_DATA_TYPE_PASSWORD != 0 && parsed.usernameId != null) {
            type = type or SaveInfo.SAVE_DATA_TYPE_USERNAME
        }

        return SaveInfo.Builder(type, required.toTypedArray())
            .apply { if (optional.isNotEmpty()) setOptionalIds(optional) }
            .build()
    }

    override fun onSaveRequest(request: SaveRequest, callback: SaveCallback) {
        val structure = request.fillContexts.lastOrNull()?.structure
        if (structure == null) {
            callback.onSuccess()
            return
        }

        val parsed = StructureParser.parse(structure)
        val username = parsed.currentValues["username"]
        val password = parsed.currentValues["password"]

        if (password.isNullOrBlank()) {
            callback.onSuccess()
            return
        }

        val saveIntent = Intent(this, AutofillHostActivity::class.java).apply {
            putExtra(AutofillHostActivity.EXTRA_MODE, AutofillHostActivity.MODE_SAVE)
            putExtra(AutofillHostActivity.EXTRA_WEB_DOMAIN, parsed.webDomain)
            putExtra(AutofillHostActivity.EXTRA_PACKAGE_NAME, parsed.packageName)
            putExtra(AutofillHostActivity.EXTRA_SAVE_USERNAME, username)
            putExtra(AutofillHostActivity.EXTRA_SAVE_PASSWORD, password)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            // Hand the platform an intent to launch. It shows our unlock screen
            // at the right moment, rather than us fighting to start an activity
            // from a background service.
            val pendingIntent = PendingIntent.getActivity(
                this,
                requestCounter.incrementAndGet(),
                saveIntent,
                PendingIntent.FLAG_MUTABLE or PendingIntent.FLAG_CANCEL_CURRENT
            )
            callback.onSuccess(pendingIntent.intentSender)
        } else {
            // On API 26-27 there is no way to ask for the vault to be unlocked
            // at save time, and writing the credential without the key is not
            // possible. Decline rather than pretending it was saved.
            callback.onSuccess()
        }
    }
}
