package com.farrukh.pocket_ledger

import android.app.Activity
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val io = Executors.newSingleThreadExecutor()
    private var pending: MethodChannel.Result? = null
    private var content: String? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pocket_ledger/documents")
            .setMethodCallHandler { call, result ->
                if (pending != null) {
                    result.error("busy", "A document operation is already open.", null)
                    return@setMethodCallHandler
                }
                try {
                    when (call.method) {
                        "save" -> {
                            val name = call.argument<String>("name")
                            val text = call.argument<String>("content")
                            val mime = call.argument<String>("mime")
                            if (name == null || text == null || mime !in listOf("text/csv", "application/json")) {
                                result.error("invalid", "Invalid file request.", null)
                                return@setMethodCallHandler
                            }
                            pending = result
                            content = text
                            val intent = Intent(Intent.ACTION_CREATE_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = mime
                                putExtra(Intent.EXTRA_TITLE, name)
                            }
                            startActivityForResult(intent, 1001)
                        }
                        "open" -> {
                            pending = result
                            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT).apply {
                                addCategory(Intent.CATEGORY_OPENABLE)
                                type = "application/json"
                            }
                            startActivityForResult(intent, 1002)
                        }
                        else -> result.notImplemented()
                    }
                } catch (_: Exception) {
                    pending = null
                    content = null
                    result.error("documents", "Could not open the document picker.", null)
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "pocket_ledger/install")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getVersion" -> {
                        try {
                            val packageInfo = packageManager.getPackageInfo(packageName, 0)
                            val version = packageInfo.versionName ?: "0.0.0"
                            val build = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                                packageInfo.longVersionCode
                            } else {
                                @Suppress("DEPRECATION")
                                packageInfo.versionCode.toLong()
                            }
                            result.success(
                                mapOf(
                                    "version" to version,
                                    "build" to build.toInt(),
                                ),
                            )
                        } catch (e: Exception) {
                            result.error("version", e.message ?: "Could not read app version.", null)
                        }
                    }
                    "installUpdate" -> {
                        val path = call.argument<String>("path")
                        if (path.isNullOrBlank()) {
                            result.error("invalid", "Missing update path.", null)
                            return@setMethodCallHandler
                        }
                        io.execute {
                            try {
                                installUpdateSession(File(path))
                                runOnUiThread {
                                    if (!isDestroyed) result.success(true)
                                }
                            } catch (e: Exception) {
                                runOnUiThread {
                                    if (!isDestroyed) {
                                        result.error(
                                            "install",
                                            e.message ?: "Could not start the in-app update.",
                                            null,
                                        )
                                    }
                                }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun installUpdateSession(file: File) {
        if (!file.exists() || file.length() < 1024L) {
            error("Update file is missing or incomplete.")
        }

        val installer = packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        params.setAppPackageName(packageName)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_REQUIRED)
        }

        val sessionId = installer.createSession(params)
        val session = installer.openSession(sessionId)
        try {
            file.inputStream().use { input ->
                session.openWrite("package", 0, file.length()).use { out ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        out.write(buffer, 0, count)
                    }
                    session.fsync(out)
                }
            }

            val callback = Intent(this, UpdateInstallReceiver::class.java).apply {
                action = UpdateInstallReceiver.ACTION
                setPackage(packageName)
            }
            val flags = PendingIntent.FLAG_UPDATE_CURRENT or
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    PendingIntent.FLAG_MUTABLE
                } else {
                    0
                }
            val pendingIntent = PendingIntent.getBroadcast(this, sessionId, callback, flags)
            session.commit(pendingIntent.intentSender)
        } catch (e: Exception) {
            session.abandon()
            throw e
        } finally {
            session.close()
        }
    }

    @Deprecated("Uses the FlutterActivity activity result bridge")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode != 1001 && requestCode != 1002) return
        val result = pending ?: return
        val uri = data?.data
        if (resultCode != Activity.RESULT_OK || uri == null) {
            pending = null
            content = null
            result.success(if (requestCode == 1001) false else null)
            return
        }
        val text = content
        io.execute {
            try {
                val value: Any = if (requestCode == 1001) {
                    contentResolver.openOutputStream(uri, "wt")!!.use {
                        it.write((text ?: error("Missing content")).toByteArray(Charsets.UTF_8))
                        it.flush()
                    }
                    true
                } else {
                    contentResolver.openInputStream(uri)!!.use { input ->
                        val output = ByteArrayOutputStream()
                        val buffer = ByteArray(8192)
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            if (output.size() + count > 5 * 1024 * 1024) error("Backup too large")
                            output.write(buffer, 0, count)
                        }
                        output.toString("UTF-8")
                    }
                }
                runOnUiThread {
                    pending = null
                    content = null
                    if (!isDestroyed) result.success(value)
                }
            } catch (_: Exception) {
                runOnUiThread {
                    pending = null
                    content = null
                    if (!isDestroyed) result.error("documents", "Could not read or write this document.", null)
                }
            }
        }
    }

    override fun onDestroy() {
        io.shutdown()
        super.onDestroy()
    }
}
