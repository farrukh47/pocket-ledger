package com.farrukh.pocket_ledger

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.util.Log

/**
 * Handles PackageInstaller callbacks for in-place app updates.
 * When confirmation is required, launches the system update confirmation UI.
 */
class UpdateInstallReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
        when (status) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                val confirm = if (android.os.Build.VERSION.SDK_INT >= 33) {
                    intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
                } else {
                    @Suppress("DEPRECATION")
                    intent.getParcelableExtra(Intent.EXTRA_INTENT)
                }
                if (confirm != null) {
                    confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    context.startActivity(confirm)
                }
            }
            PackageInstaller.STATUS_SUCCESS -> {
                Log.i(TAG, "Pocket Ledger update installed.")
            }
            else -> {
                val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE)
                Log.e(TAG, "Update failed ($status): $message")
            }
        }
    }

    companion object {
        const val ACTION = "com.farrukh.pocket_ledger.UPDATE_INSTALL"
        private const val TAG = "PocketLedgerUpdate"
    }
}
