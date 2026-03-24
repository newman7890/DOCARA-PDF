package com.example.pdf_scanner_editor

import android.content.Intent
import android.net.Uri
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.pdfeditor/intent"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "getInitialPdf") {
                val path = handleIntent(intent)
                result.success(path)
            } else {
                result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        val path = handleIntent(intent)
        if (path != null) {
            flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                MethodChannel(messenger, CHANNEL).invokeMethod("onNewPdf", path)
            }
        }
    }

    private fun handleIntent(intent: Intent?): String? {
        if (intent == null) return null

        val uri: Uri? = when (intent.action) {
            Intent.ACTION_VIEW, Intent.ACTION_EDIT -> intent.data
            Intent.ACTION_SEND -> {
                if (android.os.Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_STREAM)
                }
            }
            else -> null
        }

        if (uri != null) {
            try {
                // Copy content:// URI to a local temp file the app can access
                val inputStream = contentResolver.openInputStream(uri) ?: return null

                // Detect extension based on MIME type
                var extension = ".pdf"
                val mimeType = contentResolver.getType(uri)
                if (mimeType != null) {
                    when (mimeType) {
                        "text/csv", "text/comma-separated-values" -> extension = ".csv"
                        "application/vnd.ms-excel" -> extension = ".xls"
                        "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" -> extension = ".xlsx"
                    }
                }

                val fileName = "imported_${System.currentTimeMillis()}$extension"
                val tempFile = File(cacheDir, fileName)
                FileOutputStream(tempFile).use { output ->
                    inputStream.copyTo(output)
                }
                inputStream.close()
                return tempFile.absolutePath
            } catch (e: Exception) {
                e.printStackTrace()
                return null
            }
        }
        return null
    }
}
