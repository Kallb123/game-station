package net.nawt.zibo_games

import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// `FlutterFragmentActivity`, not the template's `FlutterActivity`: importing a
// photo (`PhotoPickerPlugin.kt`) needs `registerForActivityResult`, which is
// an `androidx.activity.ComponentActivity` API that plain `FlutterActivity`
// does not extend (`PLAN-phase-8.md` §3.3, §6 PR 6).
class MainActivity : FlutterFragmentActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PhotoPickerPlugin.channelName)
            .setMethodCallHandler(PhotoPickerPlugin(this))
    }
}
