package dev.basalt.mrgym

import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.drawable.Icon
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Hosts Flutter and a small "quick access" channel: launcher shortcuts (Mark attendance,
 * Add member) and the home-screen widget's data.
 */
class MainActivity : FlutterActivity() {
  private var channel: MethodChannel? = null
  private var pendingAction: String? = null

  override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
    super.configureFlutterEngine(flutterEngine)
    pendingAction = actionOf(intent)
    channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
      setMethodCallHandler { call, result ->
        when (call.method) {
          "takeAction" -> {
            result.success(pendingAction)
            pendingAction = null
          }
          "installShortcuts" -> result.success(installShortcuts())
          "updateWidget" -> {
            GymWidget.save(this@MainActivity, call.argument<String>("json") ?: "{}")
            result.success(null)
          }
          else -> result.notImplemented()
        }
      }
    }
  }

  override fun onNewIntent(intent: Intent) {
    super.onNewIntent(intent)
    val action = actionOf(intent) ?: return
    setIntent(intent)
    val ch = channel
    if (ch == null) pendingAction = action else ch.invokeMethod("action", action)
  }

  private fun actionOf(intent: Intent?): String? = intent?.getStringExtra(EXTRA_ACTION)

  private fun installShortcuts(): Boolean {
    if (Build.VERSION.SDK_INT < 25) return false
    val manager = getSystemService(ShortcutManager::class.java) ?: return false
    fun shortcut(id: String, label: String, icon: Int) = ShortcutInfo.Builder(this, id)
      .setShortLabel(label)
      .setIcon(Icon.createWithResource(this, icon))
      .setIntent(Intent(Intent.ACTION_MAIN).setClass(this, MainActivity::class.java).putExtra(EXTRA_ACTION, id)
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP))
      .build()
    return runCatching {
      manager.dynamicShortcuts = listOf(
        shortcut("checkin", "Mark attendance", R.drawable.ic_shortcut_checkin),
        shortcut("add-member", "Add member", R.drawable.ic_shortcut_add_member),
      )
      true
    }.getOrDefault(false)
  }

  companion object {
    const val CHANNEL = "dev.basalt.gymdesk/quick"
    const val EXTRA_ACTION = "gymdesk.action"
  }
}
