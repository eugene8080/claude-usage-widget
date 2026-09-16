package com.usage.claudewidget.auth

import android.annotation.SuppressLint
import android.app.Activity
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.Message
import android.util.Log
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import android.widget.Toast
import com.usage.claudewidget.data.Const
import com.usage.claudewidget.data.CookieHarvester
import com.usage.claudewidget.data.Storage
import com.usage.claudewidget.widget.UsageWidget
import com.usage.claudewidget.work.RefreshScheduler
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

/**
 * One-time interactive login. Loads claude.ai in a WebView; once a sessionKey cookie
 * appears, harvests cookies + the WebView's User-Agent, then finishes.
 */
class LoginActivity : Activity() {

    private lateinit var container: FrameLayout
    private lateinit var webView: WebView

    /** The sign-in provider's popup window, while one is open. */
    private var popup: WebView? = null

    private val storage by lazy { Storage.get(this) }
    private var captured = false
    private val main = Handler(Looper.getMainLooper())

    /**
     * claude.ai is a single-page app: after the sign-in redirect it routes on the client,
     * and onPageFinished never fires again. Waiting on that callback alone means a
     * successful login can sit unharvested in the cookie jar forever, which looks like a
     * page that has hung. Poll instead — the sessionKey arriving is what matters, not
     * whether the page ever renders anything.
     */
    private val pollForSession = object : Runnable {
        override fun run() {
            tryCapture()
            if (!captured) main.postDelayed(this, POLL_MS)
        }
    }

    /** A blank page with no explanation is the worst outcome; say something eventually. */
    private val hintIfStuck = Runnable {
        if (!captured) {
            Toast.makeText(
                this,
                "Still waiting for sign-in. If the page is blank, press back and try " +
                    "signing in with email instead.",
                Toast.LENGTH_LONG,
            ).show()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        CookieManager.getInstance().setAcceptCookie(true)

        container = FrameLayout(this)
        webView = newWebView()
        container.addView(webView, MATCH, MATCH)
        setContentView(container)

        // Persist the exact UA so cf_clearance stays valid for headless fetches.
        storage.userAgent = webView.settings.userAgentString
        webView.loadUrl(Const.LOGIN_URL)

        main.postDelayed(pollForSession, POLL_MS)
        main.postDelayed(hintIfStuck, HINT_MS)
    }

    /**
     * @param isProvider true for a sign-in provider's popup. Google refuses OAuth in an
     *   embedded WebView and the `; wv` token in the default User-Agent is the giveaway,
     *   so the popup announces itself as plain Chrome. The main claude.ai WebView keeps
     *   its stock UA untouched: cf_clearance is minted against that exact string and is
     *   replayed verbatim by the headless refresh, so rewriting it there would invalidate
     *   the Cloudflare token for every later fetch.
     */
    @SuppressLint("SetJavaScriptEnabled")
    private fun newWebView(isProvider: Boolean = false): WebView = WebView(this).apply {
        CookieManager.getInstance().setAcceptThirdPartyCookies(this, true)
        settings.javaScriptEnabled = true
        settings.domStorageEnabled = true
        // Google and the other providers hand off through a popup. Without these the
        // WebView silently refuses to open it, leaving a blank page and no way forward.
        settings.setSupportMultipleWindows(true)
        settings.javaScriptCanOpenWindowsAutomatically = true
        if (isProvider) {
            settings.userAgentString = deWebView(settings.userAgentString)
            // The provider's verdict on the UA is the open question in this flow; leave
            // the string it was handed in the log so a failure can be read, not guessed.
            Log.i(TAG, "popup UA: ${settings.userAgentString}")
        }

        webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView, url: String) = tryCapture()

            override fun onReceivedError(
                view: WebView,
                request: WebResourceRequest,
                error: WebResourceError,
            ) {
                if (!request.isForMainFrame) return
                Log.w(TAG, "load error ${error.errorCode} ${error.description} @ ${request.url}")
                report("Couldn't load the page: ${error.description}")
            }

            /**
             * A provider that rejects the handshake answers with an HTTP error and a
             * branded "something went wrong" page, so the status code never reaches the
             * user and onReceivedError never fires. Log it — the status and the URL are
             * the whole diagnosis for a sign-in that dead-ends.
             *
             * Only the popup's failure is worth a toast. Cloudflare serves claude.ai's
             * "Performing security verification" interstitial with a 403, so toasting the
             * main frame would fire an alarm on every normal first sign-in (verified on
             * an emulator: `W ClaudeLogin: HTTP 403 @ https://claude.ai/login`, after
             * which the challenge resolves and login proceeds).
             */
            override fun onReceivedHttpError(
                view: WebView,
                request: WebResourceRequest,
                errorResponse: WebResourceResponse,
            ) {
                if (!request.isForMainFrame) return
                val status = errorResponse.statusCode
                Log.w(TAG, "HTTP $status ${errorResponse.reasonPhrase} @ ${request.url}")
                if (isProvider) {
                    report("Sign-in provider returned HTTP $status. Try signing in with email.")
                }
            }
        }

        webChromeClient = object : WebChromeClient() {
            override fun onCreateWindow(
                view: WebView,
                isDialog: Boolean,
                isUserGesture: Boolean,
                resultMsg: Message,
            ): Boolean {
                // Give the provider a real second window rather than reusing this one, so
                // a flow that posts a result back to its opener and then closes still works.
                popup?.let { closePopup(it) }
                val child = newWebView(isProvider = true)
                popup = child
                container.addView(child, MATCH, MATCH)
                (resultMsg.obj as WebView.WebViewTransport).webView = child
                resultMsg.sendToTarget()
                return true
            }

            override fun onCloseWindow(window: WebView) {
                if (window === popup) closePopup(window)
            }
        }
    }

    private fun closePopup(view: WebView) {
        container.removeView(view)
        view.destroy()
        if (popup === view) popup = null
        // The popup closing is usually the last step of the handshake.
        tryCapture()
    }

    /**
     * Strip the two markers that identify an embedded WebView — the `; wv` token and the
     * `Version/x.y` segment Chrome only emits when embedded — leaving an otherwise
     * untouched Chrome UA.
     */
    private fun deWebView(ua: String): String = ua
        .replace("; wv)", ")")
        .replace(Regex(""" Version/\d+(\.\d+)*"""), "")

    private fun report(message: String) {
        if (!captured) Toast.makeText(this, message, Toast.LENGTH_LONG).show()
    }

    private fun tryCapture() {
        if (captured) return
        val cookies = CookieManager.getInstance().getCookie(Const.BASE) ?: return
        if (!cookies.contains("${Const.COOKIE_SESSION}=")) return

        captured = true
        main.removeCallbacks(pollForSession)
        main.removeCallbacks(hintIfStuck)
        CookieManager.getInstance().flush()
        CookieHarvester.harvest(storage)

        // Discover org + first snapshot, then schedule periodic refresh.
        CoroutineScope(Dispatchers.Main).launch {
            RefreshScheduler.ensurePeriodic(this@LoginActivity)
            RefreshScheduler.refreshNow(this@LoginActivity)
            UsageWidget.updateAll(this@LoginActivity)
            Toast.makeText(this@LoginActivity, "Signed in", Toast.LENGTH_SHORT).show()
            setResult(Activity.RESULT_OK)
            finish()
        }
    }

    @Suppress("DEPRECATION")
    override fun onBackPressed() {
        val open = popup
        when {
            open != null -> closePopup(open)
            webView.canGoBack() -> webView.goBack()
            else -> super.onBackPressed()
        }
    }

    override fun onDestroy() {
        main.removeCallbacks(pollForSession)
        main.removeCallbacks(hintIfStuck)
        popup?.let { container.removeView(it); it.destroy() }
        popup = null
        if (::webView.isInitialized) webView.destroy()
        super.onDestroy()
    }

    private companion object {
        const val TAG = "ClaudeLogin"
        const val POLL_MS = 750L
        const val HINT_MS = 45_000L
        const val MATCH = ViewGroup.LayoutParams.MATCH_PARENT
    }
}
