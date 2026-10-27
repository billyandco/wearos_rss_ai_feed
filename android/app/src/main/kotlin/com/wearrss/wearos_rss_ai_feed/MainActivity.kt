package com.wearrss.wearos_rss_ai_feed

import android.content.Intent
import android.net.Uri
import androidx.wear.remote.interactions.RemoteActivityHelper
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ExecutionException

/**
 * Hosts the Flutter UI and exposes Wear OS' RemoteActivityHelper to Dart.
 *
 * Double-tapping an article sends an ACTION_VIEW + CATEGORY_BROWSABLE intent to
 * the paired phone, where it opens in the phone's default browser.
 */
class MainActivity : FlutterActivity() {
    private companion object {
        const val CHANNEL_NAME = "com.wearrss.wearos_rss_ai_feed/remote_activity"
        const val METHOD_OPEN_ON_PHONE = "openOnPhone"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL_NAME)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    METHOD_OPEN_ON_PHONE -> openOnPhone(call.argument<String>("url"), result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun openOnPhone(url: String?, result: MethodChannel.Result) {
        if (url.isNullOrBlank()) {
            result.error("invalid_url", "No article URL was provided.", null)
            return
        }

        val uri = Uri.parse(url)
        if (uri.scheme != "https" && uri.scheme != "http") {
            result.error("invalid_url", "Only http(s) article links can be opened.", null)
            return
        }

        val intent = Intent(Intent.ACTION_VIEW, uri).apply {
            addCategory(Intent.CATEGORY_BROWSABLE)
        }

        try {
            // The helper returns a Guava ListenableFuture (not a Play Services Task),
            // so completion is observed with addListener + get().
            val future = RemoteActivityHelper(applicationContext, applicationContext.mainExecutor)
                .startRemoteActivity(intent, null)

            future.addListener(
                {
                    try {
                        future.get()
                        result.success(true)
                    } catch (error: ExecutionException) {
                        result.error(
                            "open_failed",
                            error.cause?.message ?: "Could not reach your phone.",
                            null,
                        )
                    } catch (error: Exception) {
                        result.error(
                            "open_failed",
                            error.message ?: "Could not reach your phone.",
                            null,
                        )
                    }
                },
                applicationContext.mainExecutor,
            )
        } catch (error: Exception) {
            result.error(
                "open_failed",
                error.message ?: "Could not ask your phone to open this link.",
                null,
            )
        }
    }
}
