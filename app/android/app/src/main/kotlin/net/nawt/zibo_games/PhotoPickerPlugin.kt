package net.nawt.zibo_games

import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.fragment.app.FragmentActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * The Android side of `zibo/photos` (`PLAN-phase-8.md` §3.3): one photo, no
 * permission, through the system's own picker. `PickVisualMedia` uses the
 * Android photo picker where the device has one and falls back to
 * `ACTION_OPEN_DOCUMENT` by itself on an older one, so nothing here branches
 * on API level — that fallback is what makes API 26 work with no permission
 * and no version check of its own.
 *
 * `registerForActivityResult` must be called before the activity reaches
 * `STARTED`, so this is constructed from `MainActivity.configureFlutterEngine`
 * — itself called from `onCreate`, before that point — rather than lazily
 * from the first `pick` call.
 */
class PhotoPickerPlugin(private val activity: FragmentActivity) :
    MethodChannel.MethodCallHandler {

    /** The `Result` a `pick` call is still waiting to answer, or null between calls. */
    private var pending: MethodChannel.Result? = null

    private val launcher =
        activity.registerForActivityResult(ActivityResultContracts.PickVisualMedia()) { uri ->
            val result = pending
            pending = null
            if (result == null) return@registerForActivityResult
            if (uri == null) {
                // Dismissed with nothing chosen — not an error
                // (`PLAN-phase-8.md` §4.6: "or null if nothing was chosen").
                result.success(null)
                return@registerForActivityResult
            }
            try {
                val bytes =
                    activity.contentResolver.openInputStream(uri)?.use { it.readBytes() }
                result.success(bytes)
            } catch (error: Exception) {
                result.error("read_failed", error.message, null)
            }
        }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            // Always true: every Android device this app supports has a photo
            // library, and PickVisualMedia's own fallback is what makes that
            // true down to API 26 (`PLAN-phase-8.md` §3.3).
            "available" -> result.success(true)
            "pick" -> {
                if (pending != null) {
                    // A second call while one is already showing the picker —
                    // the Dart side offers one import control at a time, so
                    // this is a defensive answer, not an expected path.
                    result.error("busy", "A pick is already in progress.", null)
                    return
                }
                pending = result
                launcher.launch(
                    PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly)
                )
            }
            else -> result.notImplemented()
        }
    }

    companion object {
        const val channelName = "zibo/photos"
    }
}
