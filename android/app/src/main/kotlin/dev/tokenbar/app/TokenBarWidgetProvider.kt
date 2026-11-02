package dev.tokenbar.app

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences
import android.content.res.ColorStateList
import android.graphics.Color
import android.os.Build
import android.view.View
import android.widget.RemoteViews
import es.antonborri.home_widget.HomeWidgetLaunchIntent
import es.antonborri.home_widget.HomeWidgetProvider

/** Home screen widget; data is written by lib/services/home_widget_bridge.dart. */
class TokenBarWidgetProvider : HomeWidgetProvider() {
    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
        widgetData: SharedPreferences,
    ) {
        for (id in appWidgetIds) {
            appWidgetManager.updateAppWidget(id, buildViews(context, widgetData))
        }
    }

    private fun buildViews(context: Context, data: SharedPreferences): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.tokenbar_widget)
        views.setOnClickPendingIntent(
            R.id.widget_root,
            HomeWidgetLaunchIntent.getActivity(context, MainActivity::class.java),
        )
        views.setTextViewText(R.id.widget_updated, data.getString("tb_updated", "") ?: "")
        views.removeAllViews(R.id.widget_rows)

        val count = readInt(data, "tb_count", 0).coerceIn(0, MAX_ROWS)
        views.setViewVisibility(R.id.widget_empty, if (count == 0) View.VISIBLE else View.GONE)
        for (i in 0 until count) {
            val row = RemoteViews(context.packageName, R.layout.tokenbar_widget_row)
            val session = readInt(data, "tb_${i}_session", -1)
            val weekly = readInt(data, "tb_${i}_weekly", -1)
            row.setTextViewText(R.id.row_name, data.getString("tb_${i}_name", "") ?: "")
            row.setTextViewText(R.id.row_session, percentText(session))
            row.setTextColor(R.id.row_session, quotaColor(session))
            row.setProgressBar(R.id.row_bar, 100, session.coerceAtLeast(0), false)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                // Tint the bar like the app does (green / amber / red); older Android keeps green.
                row.setColorStateList(
                    R.id.row_bar,
                    "setProgressTintList",
                    ColorStateList.valueOf(quotaColor(session)),
                )
            }
            row.setTextViewText(
                R.id.row_detail,
                listOfNotNull(
                    if (weekly >= 0) "周 $weekly%" else null,
                    data.getString("tb_${i}_detail", null)?.takeIf { it.isNotEmpty() },
                ).joinToString(" · "),
            )
            views.addView(R.id.widget_rows, row)
        }
        return views
    }

    private fun readInt(data: SharedPreferences, key: String, fallback: Int): Int =
        try {
            data.getInt(key, fallback)
        } catch (_: ClassCastException) {
            data.getLong(key, fallback.toLong()).toInt()
        }

    private fun percentText(value: Int) = if (value < 0) "—" else "$value%"

    private fun quotaColor(remaining: Int): Int = when {
        remaining < 0 -> Color.parseColor("#9CA3AF")
        remaining > 50 -> Color.parseColor("#34D399")
        remaining > 20 -> Color.parseColor("#FBBF24")
        else -> Color.parseColor("#F87171")
    }

    companion object {
        private const val MAX_ROWS = 4
    }
}
