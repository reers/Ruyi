plugins {
    id("com.android.library") version "8.7.3" apply false
    id("com.android.application") version "8.7.3" apply false
    id("org.jetbrains.kotlin.android") version "2.0.21" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.0.21" apply false
    // 0.34.x supports AGP 8.7 + Central Portal; 0.37+ requires AGP 8.13+.
    id("com.vanniktech.maven.publish") version "0.34.0" apply false
}
