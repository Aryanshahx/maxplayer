package com.hypertechlabs.maxplayer

import android.annotation.SuppressLint
import android.os.Handler
import android.os.Looper
import android.os.Message
import android.util.Base64
import android.view.ViewGroup
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebView
import android.webkit.WebViewClient
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicInteger

/**
 * v48: bridge to the Puter cloud (puter.js) running inside a hidden WebView.
 *
 * Puter has no API keys and no native SDK - puter.js only works in a browser
 * context, so Max Player hosts an invisible 1x1 WebView that loads a tiny
 * page pulling puter.js from the official CDN. All AI-subtitle traffic then
 * flows through that page:
 *
 *   Kotlin (executor thread)                WebView JS
 *   ----------------------                  ------------------------
 *   read WAV -> base64 slices  --evalJS-->  window.mxFeed(id, b64)
 *   window.mxGo(id, model...)  --evalJS-->  Blob -> puter.ai.speech2txt
 *   latch released            <--MXP.*---   onChunk / onChunkError
 *
 * Auth uses Puter's "temporary user" flow (`attempt_temp_user_creation`), so
 * most people never see a form at all. If Puter does open its sign-in popup
 * window, we catch `onCreateWindow` and host that popup WebView in a
 * dialog - a ONE-TIME 30-second setup; the session afterwards persists in
 * WebView storage, so future runs are silent. The user pays their own usage
 * through their own (free) Puter account - Max Player never sees or
 * stores a key. Sign-out is offered from Dart and clears that session.
 *
 * Everything here is defensive: page load has a watchdog, every latch has a
 * timeout, JS calls happen only on the main thread, and a broken WebView is
 * torn down and rebuilt on the next attempt.
 */
class PuterBridge(private val activity: MainActivity) {

    /** Error type whose message is shown in the player snackbar. */
    class BridgeException(message: String) : Exception(message)

    private val main = Handler(Looper.getMainLooper())
    private val seq = AtomicInteger(1)

    private var webView: WebView? = null
    private var popup: WebView? = null
    private var popupDialog: android.app.AlertDialog? = null

    @Volatile private var pageReady = false
    @Volatile private var puterReady = false
    @Volatile private var loadFailed = false
    @Volatile private var readyLatch = CountDownLatch(2)

    @Volatile private var signInLatch = CountDownLatch(1)
    @Volatile private var signInOk = false
    @Volatile private var lastUser: String? = null

    @Volatile private var signOutLatch = CountDownLatch(1)

    /** One in-flight transcription per Puter call. */
    private class Pending(val latch: CountDownLatch) {
        @Volatile var srt: String? = null
        @Volatile var error: String? = null
    }

    private val pending = HashMap<Int, Pending>()

    // ------------------------------------------------------------------
    // Page content
    // ------------------------------------------------------------------

    /**
     * The tiny bridge page. Notes:
     *  - puter.js loads from the official CDN and reports via onload/onerror.
     *  - mxFeed receives base64 slices (audio/wav 16 kHz mono). Slice length
     *    is kept on a 4-char base64 boundary, so parts simply concatenate.
     *  - mxGo builds ONE Blob and asks Puter for SRT directly - the response
     *    text IS the .srt document for the audio slice we sent.
     *  - mxSignIn tries the silent temporary-user creation first; Puter only
     *    shows its popup when that is not enough.
     *  - All MXP.* callbacks come back on the JS bridge thread - they only
     *    set volatile fields and release latches, so they are thread-safe.
     *  - No `$` interpolation is used inside (Kotlin reads this verbatim).
     */
    private val pageHtml = """
<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<script src="https://js.puter.com/v2/"
        onload="window.MXP && MXP.onPuterReady();"
        onerror="window.MXP && MXP.onPuterError();"></script>
</head>
<body style="background:#111;color:#555;font-family:sans-serif">
<div id="mxLabel">Max Player cloud bridge</div>
<script>
var mxParts = {};
var mxDropped = {};

window.mxFeed = function(id, b64) {
    if (!mxParts[id]) mxParts[id] = [];
    mxParts[id].push(b64);
};

window.mxGo = async function(id, model, lang, translate) {
    try {
        var parts = mxParts[id] || [];
        delete mxParts[id];
        var bin = atob(parts.join(''));
        var bytes = new Uint8Array(bin.length);
        for (var i = 0; i < bin.length; i++) {
            bytes[i] = bin.charCodeAt(i);
        }
        var blob = new Blob([bytes], { type: 'audio/wav' });
        var opts = { model: model, response_format: 'srt' };
        if (lang && lang !== 'auto') opts.language = lang;
        if (translate) opts.translate = true;
        var res = await puter.ai.speech2txt(blob, opts);
        if (mxDropped[id]) { delete mxDropped[id]; return; }
        var srt = (typeof res === 'string') ? res
            : (res && (res.text || res.srt)) ? (res.text || res.srt) : '';
        MXP.onChunk(id, String(srt));
    } catch (e) {
        if (mxDropped[id]) { delete mxDropped[id]; return; }
        var m = (e && (e.message || e.error)) ? (e.message || e.error) : ('' + e);
        MXP.onChunkError(id, String(m).slice(0, 240));
    }
};

window.mxDrop = function(id) {
    mxDropped[id] = true;
    delete mxParts[id];
};

window.mxStatus = function() {
    try { return puter.auth.isSignedIn() ? 'signed' : 'anon'; }
    catch (e) { return 'error'; }
};

window.mxSignIn = async function() {
    try {
        if (puter.auth.isSignedIn()) {
            MXP.onSignIn(true, 'ready');
            return;
        }
        await puter.auth.signIn({ attempt_temp_user_creation: true });
        var u = null;
        try { u = await puter.auth.getUser(); } catch (e0) {}
        var label = (u && (u.username || u.email))
            ? String(u.username || u.email) : 'guest';
        MXP.onSignIn(true, label);
    } catch (e) {
        var code = (e && (e.error || e.code)) ? String(e.error || e.code)
            : ((e && e.message) ? String(e.message) : 'cancelled');
        MXP.onSignIn(false, code.slice(0, 120));
    }
};

window.mxSignOut = async function() {
    try { await puter.auth.signOut(); } catch (e) {}
    MXP.onSignedOut();
};

MXP.onPageReady();
</script>
</body>
</html>
""".trimIndent()

    // ------------------------------------------------------------------
    // JS bridge object (called from the page; runs on a bridge thread)
    // ------------------------------------------------------------------

    @Suppress("unused")
    private inner class JsApi {
        @JavascriptInterface
        fun onPageReady() {
            pageReady = true
            readyLatch.countDown()
        }

        @JavascriptInterface
        fun onPuterReady() {
            puterReady = true
            readyLatch.countDown()
        }

        @JavascriptInterface
        fun onPuterError() {
            loadFailed = true
            releaseReadyLatch()
        }

        @JavascriptInterface
        fun onSignIn(ok: Boolean, label: String?) {
            signInOk = ok
            if (ok && !label.isNullOrBlank()) lastUser = label
            signInLatch.countDown()
            if (ok) closePopupOnMain()
        }

        @JavascriptInterface
        fun onSignedOut() {
            lastUser = null
            signOutLatch.countDown()
        }

        @JavascriptInterface
        fun onChunk(id: Int, srt: String) {
            complete(id, srt, null)
        }

        @JavascriptInterface
        fun onChunkError(id: Int, message: String) {
            complete(id, null, message)
        }
    }

    private fun complete(id: Int, srt: String?, error: String?) {
        val p: Pending?
        synchronized(pending) {
            p = pending[id]
        }
        if (p != null) {
            p.srt = srt
            p.error = error
            p.latch.countDown()
        }
    }

    private fun releaseReadyLatch() {
        readyLatch.countDown()
        readyLatch.countDown()
    }

    // ------------------------------------------------------------------
    // WebView lifecycle (main thread only)
    // ------------------------------------------------------------------

    @SuppressLint("SetJavaScriptEnabled", "AddJavascriptInterface")
    private fun createWebViewOnMain() {
        destroyWebViewOnMain()
        val wv = try {
            WebView(activity)
        } catch (t: Throwable) {
            loadFailed = true
            releaseReadyLatch()
            return
        }
        val s = wv.settings
        s.javaScriptEnabled = true
        s.domStorageEnabled = true
        s.setSupportMultipleWindows(true)
        s.mediaPlaybackRequiresUserGesture = false
        try {
            CookieManager.getInstance().setAcceptThirdPartyCookies(wv, true)
        } catch (_: Throwable) {
            // Very old WebViews without CookieManager support just keep
            // first-party cookies - the Puter session still works.
        }
        wv.addJavascriptInterface(JsApi(), "MXP")
        wv.webViewClient = object : WebViewClient() {}
        wv.webChromeClient = object : WebChromeClient() {
            override fun onCreateWindow(
                view: WebView?,
                isDialog: Boolean,
                isUserGesture: Boolean,
                resultMsg: Message?
            ): Boolean {
                return openPopupOnMain(resultMsg)
            }

            override fun onCloseWindow(window: WebView?) {
                closePopupOnMain()
            }
        }
        webView = wv
        // A detached WebView throttles JS on some devices; attach it 1x1.
        try {
            activity.addContentView(wv, ViewGroup.LayoutParams(1, 1))
        } catch (_: Throwable) {
        }
        wv.loadDataWithBaseURL(
            "https://maxplayer-cloud.local/", pageHtml, "text/html", "utf-8", null
        )
        // Watchdog: if the page or puter.js stall, fail fast so the caller
        // can report "no internet" instead of hanging forever.
        main.postDelayed({
            if (webView === wv && !(pageReady && puterReady) && !loadFailed) {
                loadFailed = true
                releaseReadyLatch()
                destroyWebViewOnMain()
            }
        }, 25000)
    }

    private fun destroyWebViewOnMain() {
        closePopupOnMain()
        val wv = webView ?: return
        webView = null
        try {
            (wv.parent as? ViewGroup)?.removeView(wv)
            wv.stopLoading()
            wv.destroy()
        } catch (_: Throwable) {
        }
    }

    /** Hosts Puter's sign-in popup window in a dialog (one-time setup). */
    @SuppressLint("SetJavaScriptEnabled")
    private fun openPopupOnMain(resultMsg: Message?): Boolean {
        val p = try {
            WebView(activity)
        } catch (t: Throwable) {
            return false
        }
        p.settings.javaScriptEnabled = true
        p.settings.domStorageEnabled = true
        p.webViewClient = WebViewClient()
        p.webChromeClient = object : WebChromeClient() {
            override fun onCloseWindow(window: WebView?) {
                closePopupOnMain()
            }
        }
        popup = p
        val dlg = try {
            android.app.AlertDialog.Builder(activity)
                .setTitle("Puter - one-time setup")
                .setView(p)
                .setNegativeButton("Cancel") { d, _ -> d.dismiss() }
                .create()
        } catch (t: Throwable) {
            popup = null
            p.destroy()
            return false
        }
        dlg.setOnDismissListener { closePopupOnMain() }
        popupDialog = dlg
        val transport = resultMsg?.obj as? WebView.WebViewTransport
        if (transport == null) {
            closePopupOnMain()
            return false
        }
        transport.webView = p
        resultMsg.sendToTarget()
        try {
            dlg.show()
        } catch (_: Throwable) {
            // Activity is finishing etc. - the JS promise will reject with
            // auth_window_closed, which reports cleanly to the player.
        }
        return true
    }

    private fun closePopupOnMain() {
        val dlg = popupDialog
        popupDialog = null
        if (dlg != null) {
            try { dlg.dismiss() } catch (_: Throwable) {}
        }
        val p = popup
        popup = null
        if (p != null) {
            try {
                (p.parent as? ViewGroup)?.removeView(p)
                p.destroy()
            } catch (_: Throwable) {
            }
        }
    }

    // ------------------------------------------------------------------
    // Public API (called from MainActivity's executor threads)
    // ------------------------------------------------------------------

    /** Ensures the bridge page + puter.js are loaded; true when usable. */
    fun awaitReady(timeoutMs: Long): Boolean {
        if (loadFailed) {
            // Previous load failed -> rebuild from scratch once per call.
            pageReady = false
            puterReady = false
            loadFailed = false
            readyLatch = CountDownLatch(2)
            main.post { createWebViewOnMain() }
        } else if (webView == null) {
            readyLatch = CountDownLatch(2)
            main.post { createWebViewOnMain() }
        }
        return try {
            readyLatch.await(timeoutMs, TimeUnit.MILLISECONDS) &&
                pageReady && puterReady && !loadFailed
        } catch (e: InterruptedException) {
            false
        }
    }

    private fun evalOnMain(js: String) {
        main.post {
            try {
                webView?.evaluateJavascript(js, null)
            } catch (_: Throwable) {
            }
        }
    }

    /** Synchronous JS evaluation with a short timeout (bridge thread). */
    private fun evalSync(js: String, timeoutMs: Long): String? {
        if (!awaitReady(25000)) return null
        val latch = CountDownLatch(1)
        val out = arrayOfNulls<String>(1)
        main.post {
            try {
                webView?.evaluateJavascript(js) { v ->
                    out[0] = v
                    latch.countDown()
                }
            } catch (t: Throwable) {
                latch.countDown()
            }
        }
        return try {
            if (latch.await(timeoutMs, TimeUnit.MILLISECONDS)) out[0] else null
        } catch (e: InterruptedException) {
            null
        }
    }

    /** 'signed' | 'anon' | 'error' | null when the bridge is unavailable. */
    fun statusSync(): String? {
        val raw = evalSync("window.mxStatus ? window.mxStatus() : 'error'", 8000)
        // evaluateJavascript wraps string results in JSON quotes.
        return raw?.removePrefix("\"")?.removeSuffix("\"")
    }

    fun lastUserLabel(): String? = lastUser

    /**
     * Interactive sign-in: silent temp-user creation first; Puter's popup
     * (when needed) is hosted in a dialog. Blocks the caller (executor
     * thread) until the flow resolves or [timeoutMs] passes.
     */
    fun signInSync(timeoutMs: Long): Boolean {
        if (!awaitReady(25000)) return false
        val st = statusSync()
        if (st == "signed") return true
        signInOk = false
        signInLatch = CountDownLatch(1)
        main.post {
            val wv = webView ?: return@post
            try {
                (wv.parent as? ViewGroup)?.removeView(wv)
                activity.addContentView(wv, ViewGroup.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT,
                    ViewGroup.LayoutParams.MATCH_PARENT
                ))
            } catch (_: Throwable) {}
            val js = """
(function(){
  var o=document.createElement('div');
  o.id='mxSO';
  o.style.cssText='position:fixed;top:0;left:0;width:100%;height:100%;background:#1a1a24;display:flex;flex-direction:column;align-items:center;justify-content:center;z-index:9999;color:#fff;font-family:sans-serif;';
  o.innerHTML='<div style="text-align:center;max-width:320px;padding:20px">'
    +'<div style="font-size:48px;margin-bottom:16px">\u2601\uFE0F</div>'
    +'<h2 style="margin:0 0 8px">One-time free setup</h2>'
    +'<p style="color:#aaa;font-size:14px;line-height:1.4;margin:0 0 24px">'
    +'AI subtitles use the Puter cloud. Tap below to sign in \u2014 '
    +'a free temporary account is created automatically.</p>'
    +'<button id="mxSB" style="background:#22D3EE;color:#111;font-size:18px;'
    +'font-weight:bold;padding:14px 32px;border:none;border-radius:12px;'
    +'cursor:pointer">Continue</button><br><br>'
    +'<a href="#" id="mxCB" style="color:#666;font-size:14px;'
    +'text-decoration:none">Cancel</a></div>';
  document.body.appendChild(o);
  document.getElementById('mxSB').addEventListener('click',async function(){
    this.disabled=true;this.textContent='Signing in\u2026';this.style.opacity='0.5';
    try{
      if(puter.auth.isSignedIn()){
        var u=null;try{u=await puter.auth.getUser();}catch(e){}
        MXP.onSignIn(true,(u&&(u.username||u.email))?String(u.username||u.email):'guest');
        return;
      }
      await puter.auth.signIn({attempt_temp_user_creation:true});
      var u=null;try{u=await puter.auth.getUser();}catch(e){}
      MXP.onSignIn(true,(u&&(u.username||u.email))?String(u.username||u.email):'guest');
    }catch(e){
      var c=(e&&(e.error||e.code))?String(e.error||e.code):((e&&e.message)?String(e.message):'cancelled');
      MXP.onSignIn(false,c.slice(0,120));
    }
  });
  document.getElementById('mxCB').addEventListener('click',function(e){
    e.preventDefault();MXP.onSignIn(false,'cancelled');
  });
})()
""".trimIndent()
            wv.evaluateJavascript(js, null)
        }
        return try {
            signInLatch.await(timeoutMs, TimeUnit.MILLISECONDS) && signInOk
        } catch (e: InterruptedException) {
            false
        } finally {
            main.post {
                val wv = webView ?: return@post
                wv.evaluateJavascript(
                    "var o=document.getElementById('mxSO');if(o)o.remove();", null)
                try {
                    (wv.parent as? ViewGroup)?.removeView(wv)
                    activity.addContentView(wv, ViewGroup.LayoutParams(1, 1))
                } catch (_: Throwable) {}
            }
        }
    }

    /** Clears the persisted Puter session (WebView storage stays intact). */
    fun signOutSync(timeoutMs: Long): Boolean {
        if (!awaitReady(25000)) return false
        signOutLatch = CountDownLatch(1)
        evalOnMain("window.mxSignOut && window.mxSignOut();")
        return try {
            signOutLatch.await(timeoutMs, TimeUnit.MILLISECONDS)
        } catch (e: InterruptedException) {
            false
        }
    }

    /**
     * Sends [wav] to Puter for transcription and returns the .srt text of
     * that slice. Runs on an executor thread; throws [BridgeException] with
     * a short user-readable reason on failure. 16 kHz mono WAV at
     * [WAV_SLICE_BYTES]-per-eval slices keeps each JS message small.
     */
    fun transcribeBlocking(
        wav: File,
        model: String,
        language: String,
        translate: Boolean,
        timeoutMs: Long = 300000
    ): String {
        if (!awaitReady(25000)) {
            throw BridgeException("cloud bridge did not load - check internet")
        }
        val id = seq.getAndIncrement()
        val p = Pending(CountDownLatch(1))
        synchronized(pending) { pending[id] = p }
        try {
            val b64 = try {
                Base64.encodeToString(wav.readBytes(), Base64.NO_WRAP)
            } catch (t: Throwable) {
                throw BridgeException("could not read the extracted audio")
            }
            var off = 0
            while (off < b64.length) {
                val end = minOf(off + B64_SLICE, b64.length)
                evalOnMain("window.mxFeed($id, '" + b64.substring(off, end) + "');")
                off = end
            }
            val tr = if (translate) "true" else "false"
            evalOnMain("window.mxGo($id, '$model', '$language', $tr);")
            val done = try {
                p.latch.await(timeoutMs, TimeUnit.MILLISECONDS)
            } catch (e: InterruptedException) {
                false
            }
            if (!done) {
                evalOnMain("window.mxDrop($id);")
                throw BridgeException("cloud answer took too long - try again")
            }
            val srt = p.srt
            if (srt != null) return srt
            throw BridgeException(p.error ?: "cloud transcription failed")
        } finally {
            synchronized(pending) { pending.remove(id) }
            evalOnMain("window.mxDrop($id);")
        }
    }

    /** Cancellation from the player: every in-flight call ends as cancelled. */
    fun cancelAll() {
        val ids = synchronized(pending) { pending.keys.toList() }
        for (id in ids) {
            complete(id, null, "cancelled")
            evalOnMain("window.mxDrop($id);")
        }
        closePopupOnMain()
    }

    /** Full teardown (e.g. user pressed Cancel during sign-in). */
    fun shutdown() {
        cancelAll()
        main.post {
            destroyWebViewOnMain()
            pageReady = false
            puterReady = false
            loadFailed = false
        }
    }

    private companion object {
        /** 768 KB per JS message, divisible by 4 (base64 boundary). */
        const val B64_SLICE = 768 * 1024
    }
}
