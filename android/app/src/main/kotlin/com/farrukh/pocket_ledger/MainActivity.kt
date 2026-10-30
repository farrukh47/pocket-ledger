package com.farrukh.pocket_ledger

import android.app.Activity
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageInstaller
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
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
                        val source = File(path)
                        runOnUiThread {
                            try {
                                if (!source.exists() || source.length() < 1024L) {
                                    result.error("invalid", "Update file is missing or incomplete.", null)
                                    return@runOnUiThread
                                }
                                ensureInstallPermission()
                                val staged = stageApk(source)
                                openPackageInstallerUi(staged)
                                result.success(true)
                            } catch (primary: Exception) {
                                try {
                                    val staged = stageApk(source)
                                    installWithSession(staged)
                                    result.success(true)
                                } catch (secondary: Exception) {
                                    result.error(
                                        "install",
                                        secondary.message
                                            ?: primary.message
                                            ?: "Could not open the update installer.",
                                        null,
                                    )
                                }
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun ensureInstallPermission() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (packageManager.canRequestPackageInstalls()) return
        startActivity(
            Intent(
                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                Uri.parse("package:$packageName"),
            ).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
        error("Allow “Install unknown apps” for Pocket Ledger, then tap Check for updates again.")
    }

    /** Copy into app files so FileProvider + MIUI can always read it. */
    private fun stageApk(source: File): File {
        val dir = File(filesDir, "updates").apply { mkdirs() }
        val staged = File(dir, "pending-update.apk")
        if (staged.absolutePath != source.absolutePath) {
            source.copyTo(staged, overwrite = true)
        }
        if (!staged.exists() || staged.length() < 1024L) {
            error("Could not prepare the update file.")
        }
        return staged
    }

    /** Opens the system installer so the user can confirm updating this app. */
    private fun openPackageInstallerUi(file: File) {
        val uri: Uri = FileProvider.getUriForFile(
            this,
            "${applicationContext.packageName}.fileprovider",
            file,
        )

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            putExtra(Intent.EXTRA_NOT_UNKNOWN_SOURCE, true)
            putExtra(Intent.EXTRA_RETURN_RESULT, false)
        }

        val resolvers = packageManager.queryIntentActivities(intent, PackageManager.MATCH_DEFAULT_ONLY)
        for (info in resolvers) {
            grantUriPermission(
                info.activityInfo.packageName,
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION,
            )
        }

        val preferred = listOf(
            "com.google.android.packageinstaller",
            "com.android.packageinstaller",
            "com.miui.packageinstaller",
            "com.miui.global.packageinstaller",
        )
        for (pkg in preferred) {
            if (resolvers.none { it.activityInfo.packageName == pkg }) continue
            try {
                grantUriPermission(pkg, uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
                startActivity(Intent(intent).setPackage(pkg))
                return
            } catch (_: Exception) {
                // Try the next known installer.
            }
        }

        if (resolvers.isEmpty()) {
            @Suppress("DEPRECATION")
            val install = Intent(Intent.ACTION_INSTALL_PACKAGE).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                putExtra(Intent.EXTRA_NOT_UNKNOWN_SOURCE, true)
            }
            startActivity(install)
            return
        }

        startActivity(Intent.createChooser(intent, "Install Pocket Ledger update"))
    }

    /** Fallback: PackageInstaller session (some devices prefer this path). */
    private fun installWithSession(file: File) {
        val installer = packageManager.packageInstaller
        val params = PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL)
        params.setAppPackageName(packageName)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            params.setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_REQUIRED)
        }

        val sessionId = installer.createSession(params)
        installer.openSession(sessionId).use { session ->
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
