package dev.basalt.mrgym

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import org.json.JSONObject

/** Home-screen widget: today's check-ins, fees due and overdue, and this month's collection. */
class GymWidget : AppWidgetProvider() {
  override fun onUpdate(context: Context, manager: AppWidgetManager, ids: IntArray) {
    val views = render(context)
    ids.forEach { manager.updateAppWidget(it, views) }
  }

  companion object {
    private const val PREFS = "gymdesk_widget"

    fun save(context: Context, json: String) {
      context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString("data", json).apply()
      val manager = AppWidgetManager.getInstance(context)
      val ids = manager.getAppWidgetIds(ComponentName(context, GymWidget::class.java))
      if (ids.isNotEmpty()) {
        val views = render(context)
        ids.forEach { manager.updateAppWidget(it, views) }
      }
    }

    private fun render(context: Context): RemoteViews {
      val data = runCatching { JSONObject(context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("data", "{}") ?: "{}") }
        .getOrDefault(JSONObject())
      val v = RemoteViews(context.packageName, R.layout.gym_widget)
      v.setTextViewText(R.id.widget_gym, data.optString("gym", "Gymdesk"))
      v.setTextViewText(R.id.widget_checkins, data.optInt("checkins", 0).toString())
      v.setTextViewText(R.id.widget_due, data.optInt("due", 0).toString())
      v.setTextViewText(R.id.widget_overdue, data.optInt("overdue", 0).toString())
      v.setTextViewText(R.id.widget_revenue, data.optString("revenue", "—"))
      val open = Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
      v.setOnClickPendingIntent(R.id.widget_root, PendingIntent.getActivity(context, 31, open, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))
      val checkin = Intent(context, MainActivity::class.java).putExtra(MainActivity.EXTRA_ACTION, "checkin")
        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
      v.setOnClickPendingIntent(R.id.widget_checkin_button, PendingIntent.getActivity(context, 32, checkin, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT))
      return v
    }
  }
}
