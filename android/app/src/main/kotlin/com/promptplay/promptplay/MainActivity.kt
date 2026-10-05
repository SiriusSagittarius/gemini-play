package com.promptplay.promptplay

import android.app.Activity
import android.content.Intent
import android.content.pm.ShortcutInfo
import android.content.pm.ShortcutManager
import android.graphics.BitmapFactory
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.provider.OpenableColumns
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Verknüpfungen auf dem Startbildschirm, die direkt ein Spiel öffnen, und die
 * Dateiauswahl für den Medien-Ordner (Gegenstück: ProjectShortcuts und
 * DeviceFiles in lib/project_tools.dart).
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pendingPick: MethodChannel.Result? = null
    private var pendingSave: MethodChannel.Result? = null
    private var pendingSaveBytes: ByteArray? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, FILES_CHANNEL).setMethodCallHandler { call, result ->
            @Suppress("DEPRECATION")
            when (call.method) {
                "pick" -> {
                    pendingPick?.success(null)
                    pendingPick = result
                    val pick = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = "*/*"
                        putExtra(Intent.EXTRA_ALLOW_MULTIPLE, true)
                    }
                    startActivityForResult(pick, PICK_REQUEST)
                }
                // „Speichern unter“: Android fragt nach Ort und Namen (Downloads, Drive …).
                "save" -> {
                    pendingSave?.success(null)
                    pendingSave = result
                    pendingSaveBytes = call.argument<ByteArray>("bytes")
                    val save = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                        addCategory(Intent.CATEGORY_OPENABLE)
                        type = call.argument<String>("mimeType") ?: "application/octet-stream"
                        putExtra(Intent.EXTRA_TITLE, call.argument<String>("name") ?: "PromptPlay")
                    }
                    startActivityForResult(save, SAVE_REQUEST)
                }
                else -> result.notImplemented()
            }
        }
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "pin" -> result.success(
                        pinShortcut(
                            call.argument<String>("id") ?: "",
                            call.argument<String>("title") ?: "PromptPlay",
                            call.argument<ByteArray>("icon"),
                        ),
                    )
                    "initialProject" -> {
                        result.success(intent?.getStringExtra(EXTRA_PROJECT))
                        intent?.removeExtra(EXTRA_PROJECT)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    @Deprecated("Ergebnis der Dateiauswahl")
    @Suppress("DEPRECATION")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == SAVE_REQUEST) return finishSave(resultCode, data?.data)
        if (requestCode != PICK_REQUEST) return
        val result = pendingPick ?: return
        pendingPick = null
        if (resultCode != Activity.RESULT_OK || data == null) return result.success(null)

        val uris = buildList {
            data.clipData?.let { clip -> for (i in 0 until clip.itemCount) add(clip.getItemAt(i).uri) }
            if (isEmpty()) data.data?.let { add(it) }
        }
        // Lesen im Hintergrund – Pakete können einige MB groß sein.
        Thread {
            val files = uris.mapNotNull { uri -> readFile(uri) }
            runOnUiThread { result.success(files) }
        }.start()
    }

    /** Schreibt die Datei an den gewählten Ort; `null` heißt abgebrochen. */
    private fun finishSave(resultCode: Int, uri: Uri?) {
        val result = pendingSave ?: return
        val bytes = pendingSaveBytes
        pendingSave = null
        pendingSaveBytes = null
        if (resultCode != Activity.RESULT_OK || uri == null || bytes == null) return result.success(null)
        Thread {
            val ok = try {
                contentResolver.openOutputStream(uri, "wt")?.use { it.write(bytes) } != null
            } catch (e: Exception) {
                false
            }
            runOnUiThread { result.success(ok) }
        }.start()
    }

    /** Liest eine gewählte Datei (höchstens 60 MB) als Name + Bytes. */
    private fun readFile(uri: Uri): Map<String, Any>? = try {
        var name = uri.lastPathSegment ?: "datei"
        contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
            if (cursor.moveToFirst()) cursor.getString(0)?.let { name = it }
        }
        contentResolver.openInputStream(uri)?.use { input ->
            val bytes = input.readBytes()
            if (bytes.size > MAX_PICK_BYTES) null else mapOf("name" to name, "bytes" to bytes)
        }
    } catch (e: Exception) {
        null
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        intent.getStringExtra(EXTRA_PROJECT)?.let { channel?.invokeMethod("openProject", it) }
    }

    private fun pinShortcut(id: String, title: String, icon: ByteArray?): Boolean {
        if (id.isEmpty() || Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val manager = getSystemService(ShortcutManager::class.java) ?: return false
        if (!manager.isRequestPinShortcutSupported) return false

        val launch = Intent(this, MainActivity::class.java).apply {
            action = Intent.ACTION_VIEW
            putExtra(EXTRA_PROJECT, id)
            addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        val bitmap = icon?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
        val shortcut = ShortcutInfo.Builder(this, "project-$id")
            .setShortLabel(title.take(25))
            .setLongLabel(title.take(60))
            .setIcon(
                if (bitmap != null) Icon.createWithAdaptiveBitmap(bitmap)
                else Icon.createWithResource(this, R.mipmap.ic_launcher),
            )
            .setIntent(launch)
            .build()
        return manager.requestPinShortcut(shortcut, null)
    }

    companion object {
        private const val CHANNEL = "promptplay/shortcuts"
        private const val FILES_CHANNEL = "promptplay/files"
        private const val EXTRA_PROJECT = "projectId"
        private const val PICK_REQUEST = 4711
        private const val SAVE_REQUEST = 4712
        private const val MAX_PICK_BYTES = 60 * 1024 * 1024
    }
}
