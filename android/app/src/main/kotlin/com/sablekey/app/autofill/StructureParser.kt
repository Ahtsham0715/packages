package com.sablekey.app.autofill

import android.app.assist.AssistStructure
import android.os.Build
import android.text.InputType
import android.view.View
import android.view.autofill.AutofillId

/**
 * What we managed to work out about the form on screen.
 */
data class ParsedStructure(
    val packageName: String?,
    val webDomain: String?,
    val usernameId: AutofillId? = null,
    val passwordId: AutofillId? = null,
    val otpId: AutofillId? = null,
    val cardNumberId: AutofillId? = null,
    val cardExpiryId: AutofillId? = null,
    val cardCvvId: AutofillId? = null,
    val cardHolderId: AutofillId? = null,
    val allIds: List<AutofillId> = emptyList(),
    val currentValues: Map<String, String> = emptyMap()
) {
    val hasLoginFields: Boolean get() = passwordId != null || usernameId != null
    val hasCardFields: Boolean get() = cardNumberId != null

    /** Whether there is anything here worth offering a credential for. */
    val isFillable: Boolean get() = hasLoginFields || hasCardFields

    /** What a stored item's URI is matched against. */
    val target: String? get() = webDomain ?: packageName
}

/**
 * Turns an [AssistStructure] into the handful of fields Sablekey can fill.
 *
 * Three sources of truth, in descending order of trust:
 *
 *  1. Explicit autofill hints, which a well-behaved app or a page using
 *     `autocomplete=` supplies directly.
 *  2. The HTML attributes of a web view node — `type`, `name`, `id`,
 *     `autocomplete` — which is what most real login pages actually give us.
 *  3. The input type and the resource id, which is all a native app that never
 *     thought about autofill leaves behind.
 *
 * The order matters. Guessing from a resource id called `email` when the app
 * has already declared the field is a password would fill the wrong box, and a
 * password typed into a visible username field is a leak the user cannot undo.
 */
object StructureParser {

    private val USERNAME_TOKENS = listOf(
        "username", "user_name", "userid", "user_id", "login", "loginid",
        "email", "e-mail", "emailaddress", "account", "identifier", "phone"
    )
    private val PASSWORD_TOKENS = listOf(
        "password", "passwd", "pwd", "pass", "passphrase", "secret"
    )
    private val OTP_TOKENS = listOf(
        "otp", "totp", "2fa", "twofactor", "onetimecode", "verificationcode",
        "securitycode", "authcode", "mfa"
    )
    private val CARD_NUMBER_TOKENS = listOf("cardnumber", "ccnumber", "cardno", "creditcard")
    private val CARD_EXPIRY_TOKENS = listOf("expiry", "expiration", "expdate", "ccexp")
    private val CARD_CVV_TOKENS = listOf("cvv", "cvc", "csc", "securitycode", "cardcode")
    private val CARD_HOLDER_TOKENS = listOf("cardholder", "ccname", "nameoncard")

    fun parse(structure: AssistStructure): ParsedStructure {
        val builder = Builder(structure.activityComponent?.packageName)
        for (i in 0 until structure.windowNodeCount) {
            builder.visit(structure.getWindowNodeAt(i).rootViewNode)
        }
        return builder.build()
    }

    private class Builder(private val packageName: String?) {
        private var webDomain: String? = null
        private var usernameId: AutofillId? = null
        private var passwordId: AutofillId? = null
        private var otpId: AutofillId? = null
        private var cardNumberId: AutofillId? = null
        private var cardExpiryId: AutofillId? = null
        private var cardCvvId: AutofillId? = null
        private var cardHolderId: AutofillId? = null
        private val allIds = mutableListOf<AutofillId>()
        private val values = mutableMapOf<String, String>()

        fun visit(node: AssistStructure.ViewNode) {
            node.webDomain?.takeIf { it.isNotBlank() }?.let { domain ->
                // The outermost web domain wins: an ad iframe nested inside the
                // page must never redirect a credential to its own origin.
                if (webDomain == null) webDomain = domain.lowercase()
            }

            classify(node)

            for (i in 0 until node.childCount) {
                visit(node.getChildAt(i))
            }
        }

        private fun classify(node: AssistStructure.ViewNode) {
            val id = node.autofillId ?: return
            if (node.autofillType == View.AUTOFILL_TYPE_NONE) return
            allIds += id

            val currentText = node.autofillValue
                ?.takeIf { it.isText }
                ?.textValue
                ?.toString()

            // 1. Declared hints.
            node.autofillHints?.forEach { raw ->
                when (normalise(raw)) {
                    "username", "newusername" -> assignUsername(id, currentText)
                    "emailaddress", "email" -> assignUsername(id, currentText)
                    "password", "newpassword" -> assignPassword(id, currentText)
                    "smsotpcode", "smsotp" -> if (otpId == null) otpId = id
                    "creditcardnumber" -> if (cardNumberId == null) cardNumberId = id
                    "creditcardexpirationdate",
                    "creditcardexpirationmonth",
                    "creditcardexpirationyear" -> if (cardExpiryId == null) cardExpiryId = id
                    "creditcardsecuritycode" -> if (cardCvvId == null) cardCvvId = id
                    "name", "personname", "creditcardname" ->
                        if (cardHolderId == null) cardHolderId = id
                }
            }
            if (isSettled(id)) return

            // 2. Web page attributes.
            val html = node.htmlInfo
            if (html != null && html.tag.equals("input", ignoreCase = true)) {
                val attributes = html.attributes.orEmpty()
                    .associate { it.first.lowercase() to it.second.lowercase() }
                val type = attributes["type"].orEmpty()
                val descriptor = listOfNotNull(
                    attributes["autocomplete"],
                    attributes["name"],
                    attributes["id"],
                    attributes["placeholder"]
                ).joinToString(" ")

                when {
                    type == "password" -> assignPassword(id, currentText)
                    type == "email" -> assignUsername(id, currentText)
                    type == "hidden" || type == "submit" || type == "button" -> return
                    else -> assignFromText(id, descriptor, currentText)
                }
                if (isSettled(id)) return
            }

            // 3. Native app fallbacks.
            val inputType = node.inputType
            if (isPasswordInputType(inputType)) {
                assignPassword(id, currentText)
                return
            }

            val descriptor = buildString {
                append(node.idEntry.orEmpty()).append(' ')
                append(node.hint.orEmpty()).append(' ')
                append(node.contentDescription?.toString().orEmpty())
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                    node.text?.let { append(' ').append(it) }
                }
            }
            assignFromText(id, descriptor, currentText)
        }

        private fun assignFromText(id: AutofillId, descriptor: String, value: String?) {
            val text = normalise(descriptor)
            if (text.isEmpty()) return

            // Card checks come first: "security code" would otherwise be caught
            // by the OTP tokens, and filling a one-time code into a CVV box is
            // both useless and confusing.
            when {
                CARD_NUMBER_TOKENS.any { text.contains(it) } ->
                    if (cardNumberId == null) cardNumberId = id
                CARD_EXPIRY_TOKENS.any { text.contains(it) } ->
                    if (cardExpiryId == null) cardExpiryId = id
                CARD_CVV_TOKENS.any { text.contains(it) } ->
                    if (cardCvvId == null) cardCvvId = id
                CARD_HOLDER_TOKENS.any { text.contains(it) } ->
                    if (cardHolderId == null) cardHolderId = id
                PASSWORD_TOKENS.any { text.contains(it) } -> assignPassword(id, value)
                OTP_TOKENS.any { text.contains(it) } ->
                    if (otpId == null) otpId = id
                USERNAME_TOKENS.any { text.contains(it) } -> assignUsername(id, value)
            }
        }

        private fun assignUsername(id: AutofillId, value: String?) {
            if (usernameId == null) {
                usernameId = id
                value?.takeIf { it.isNotBlank() }?.let { values["username"] = it }
            }
        }

        private fun assignPassword(id: AutofillId, value: String?) {
            if (passwordId == null) {
                passwordId = id
                value?.takeIf { it.isNotBlank() }?.let { values["password"] = it }
            }
        }

        private fun isSettled(id: AutofillId): Boolean =
            usernameId == id || passwordId == id || otpId == id ||
                cardNumberId == id || cardExpiryId == id ||
                cardCvvId == id || cardHolderId == id

        private fun isPasswordInputType(inputType: Int): Boolean {
            if (inputType and InputType.TYPE_MASK_CLASS != InputType.TYPE_CLASS_TEXT &&
                inputType and InputType.TYPE_MASK_CLASS != InputType.TYPE_CLASS_NUMBER
            ) {
                return false
            }
            val variation = inputType and InputType.TYPE_MASK_VARIATION
            return variation == InputType.TYPE_TEXT_VARIATION_PASSWORD ||
                variation == InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD ||
                variation == InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD ||
                variation == InputType.TYPE_NUMBER_VARIATION_PASSWORD
        }

        private fun normalise(value: String): String =
            value.lowercase().replace(Regex("[^a-z0-9]"), "")

        fun build(): ParsedStructure = ParsedStructure(
            packageName = packageName,
            webDomain = webDomain,
            usernameId = usernameId,
            passwordId = passwordId,
            otpId = otpId,
            cardNumberId = cardNumberId,
            cardExpiryId = cardExpiryId,
            cardCvvId = cardCvvId,
            cardHolderId = cardHolderId,
            allIds = allIds,
            currentValues = values
        )
    }
}
