package net.nawt.zibo_games

import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import androidx.activity.result.contract.ActivityResultContracts
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * The Android side of `zibo/transfer` (`PLAN-transfer.md` §3.3): a players file
 * written through the system's save dialog and read back through its open
 * dialog. `ACTION_CREATE_DOCUMENT` and `ACTION_OPEN_DOCUMENT` take no
 * permission, so the release APK's "requests no permission" check still holds
 * (`PLAN.md` §9), and the parent, not the app, chooses where the file lives.
 *
 * `registerForActivityResult` must be called before the activity reaches
 * `STARTED`, so this is constructed from `MainActivity.configureFlutterEngine`
 * for the same reason `PhotoPickerPlugin` is.
 *
 * A players file holds a profile's drawings and can be tens of megabytes, so the
 * stream I/O runs on a worker thread; a `MethodChannel.Result` must be answered
 * on the main thread, hence the handler posting back.
 */
class TransferPlugin(private val activity: FragmentActivity) :
    MethodChannel.MethodCallHandler {

    /** The `Result` a `create` or `open` call is still waiting to answer, or null between calls. */
    private var pending: MethodChannel.Result? = null

    /** The bytes a `create` call will write once the parent has chosen a document. */
    private var pendingBytes: ByteArray? = null

    /** The name `create` suggested, the fallback when the provider reports none. */
    private var pendingName: String? = null

    private val io = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())

    private val createLauncher =
        activity.registerForActivityResult(
            ActivityResultContracts.CreateDocument("application/json")
        ) { uri ->
            val result = pending
            val bytes = pendingBytes
            val name = pendingName
            clearPending()
            if (result == null) return@registerForActivityResult
            if (uri == null || bytes == null) {
                // Dismissed without choosing a place — not an error; the Dart side
                // reads null as "the parent changed their mind".
                result.success(null)
                return@registerForActivityResult
            }
            io.execute {
                try {
                    // "wt", not the default "w": an existing document is chosen
                    // over, and "w" may leave the tail of a longer old file behind
                    // a shorter new one, which would corrupt the JSON.
                    activity.contentResolver.openOutputStream(uri, "wt")?.use {
                        it.write(bytes)
                    } ?: throw IllegalStateException("The document could not be opened.")
                    val shown = displayName(uri) ?: name
                    main.post { result.success(shown) }
                } catch (error: Exception) {
                    main.post { result.error("write_failed", error.message, null) }
                }
            }
        }

    private val openLauncher =
        activity.registerForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
            val result = pending
            clearPending()
            if (result == null) return@registerForActivityResult
            if (uri == null) {
                result.success(null)
                return@registerForActivityResult
            }
            io.execute {
                try {
                    val bytes =
                        activity.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                            ?: throw IllegalStateException("The document could not be opened.")
                    main.post { result.success(bytes) }
                } catch (error: Exception) {
                    main.post { result.error("read_failed", error.message, null) }
                }
            }
        }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "create" -> {
                val name = call.argument<String>("name")
                val bytes = call.argument<ByteArray>("bytes")
                if (name == null || bytes == null) {
                    result.error("bad_arguments", "create needs a name and bytes.", null)
                    return
                }
                if (!claim(result)) return
                pendingBytes = bytes
                pendingName = name
                launch(result) { createLauncher.launch(name) }
            }
            "open" -> {
                if (!claim(result)) return
                // "*/*" is last and is what makes a file selectable at all: some
                // document providers do not map `.json` to application/json and
                // would grey out a file the earlier types are meant to match.
                launch(result) {
                    openLauncher.launch(
                        arrayOf("application/json", "application/octet-stream", "text/plain", "*/*")
                    )
                }
            }
            else -> result.notImplemented()
        }
    }

    /** Records [result] as the one outstanding call, or answers `busy` and returns false. */
    private fun claim(result: MethodChannel.Result): Boolean {
        if (pending != null) {
            // The Dart side offers one transfer control at a time, so this is a
            // defensive answer, not an expected path.
            result.error("busy", "A file dialog is already open.", null)
            return false
        }
        pending = result
        return true
    }

    /**
     * Runs [start], which opens a system dialog. A device with no document
     * provider throws here; answering the call keeps `pending` from blocking
     * every later one.
     */
    private fun launch(result: MethodChannel.Result, start: () -> Unit) {
        try {
            start()
        } catch (error: Exception) {
            clearPending()
            result.error("unavailable", error.message, null)
        }
    }

    private fun clearPending() {
        pending = null
        pendingBytes = null
        pendingName = null
    }

    /** The name the document provider shows for [uri], or null if it reports none. */
    private fun displayName(uri: Uri): String? =
        activity.contentResolver
            .query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
            ?.use { cursor -> if (cursor.moveToFirst()) cursor.getString(0) else null }

    companion object {
        const val channelName = "zibo/transfer"
    }
}
