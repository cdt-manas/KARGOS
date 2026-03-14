package com.example.app

import android.accessibilityservice.AccessibilityService
import android.content.Intent
import android.view.KeyEvent
import android.view.accessibility.AccessibilityEvent

class VolumeKeyService : AccessibilityService() {

    private var pressCount = 0
    private var lastPressTime = 0L
    private val MAX_INTERVAL_MS = 800L // 800ms window for triple press
    private val REQUIRED_PRESSES = 3

    override fun onKeyEvent(event: KeyEvent): Boolean {
        if (event.keyCode == KeyEvent.KEYCODE_VOLUME_UP && event.action == KeyEvent.ACTION_DOWN) {
            val now = System.currentTimeMillis()

            if (now - lastPressTime > MAX_INTERVAL_MS) {
                // Too slow — reset counter
                pressCount = 1
            } else {
                pressCount++
            }
            lastPressTime = now

            if (pressCount >= REQUIRED_PRESSES) {
                pressCount = 0
                launchApp()
            }
        }
        // Return false to let the system handle volume normally
        return false
    }

    private fun launchApp() {
        val intent = packageManager.getLaunchIntentForPackage(packageName)
        intent?.let {
            it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            startActivity(it)
        }
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // Not used — we only need key event filtering
    }

    override fun onInterrupt() {
        // Required override
    }
}
