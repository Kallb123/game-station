import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing material, when there is any. `android/key.properties` names a
// keystore and its passwords; CI writes it from repository secrets before the
// build, and a local release build can write one by hand. Neither the file nor
// the keystore is in the repository — both are gitignored. See README.md.
//
// Absent, the release build falls back to Flutter's debug key, so a clean
// checkout still builds. That fallback is the reason this exists: every machine
// generates its own debug key, and Android refuses to install an update signed
// by a different certificate, so consecutive CI builds of the same app could not
// be installed over one another without uninstalling first.
val signingPropertiesFile = rootProject.file("key.properties")
val hasReleaseKey = signingPropertiesFile.exists()

val signingProperties =
    Properties().apply {
        if (hasReleaseKey) {
            signingPropertiesFile.inputStream().use { load(it) }
        }
    }

// All four or none. A file naming three of them would otherwise fall through to
// the debug key and look exactly like a success, which is the failure this
// whole config exists to stop happening quietly.
if (hasReleaseKey) {
    val required = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
    val missing = required.filter { signingProperties.getProperty(it).isNullOrBlank() }
    require(missing.isEmpty()) {
        "android/key.properties is missing ${missing.joinToString(", ")}. " +
            "Give it all of ${required.joinToString(", ")}, " +
            "or delete the file to build with the debug key."
    }
}

android {
    namespace = "net.nawt.zibo_games"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "net.nawt.zibo_games"
        // Android 8.0. PLAN.md §1 sets the supported matrix at Android 8+, and
        // Flutter's default (API 24) would have Play offer the app to Android 7
        // devices that are never tested against.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Declared only when there is a key to declare. An empty config would
        // fail at signing time with a null-path error rather than falling back.
        if (hasReleaseKey) {
            create("release") {
                // Resolved against android/, so key.properties may name the
                // keystore relative to itself; an absolute path also works.
                val keystore = rootProject.file(signingProperties.getProperty("storeFile"))
                require(keystore.exists()) {
                    "android/key.properties names a keystore at ${keystore.path}, " +
                        "which does not exist."
                }

                storeFile = keystore
                storePassword = signingProperties.getProperty("storePassword")
                keyAlias = signingProperties.getProperty("keyAlias")
                keyPassword = signingProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (hasReleaseKey) {
                    signingConfigs.getByName("release")
                } else {
                    signingConfigs.getByName("debug")
                }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
