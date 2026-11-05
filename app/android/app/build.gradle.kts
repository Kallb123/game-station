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

    // Two audiences, one app. `store` is the public build and changes nothing;
    // `private` is the same app with the private quiz packs bundled
    // (PLAN-phase-10-quiz.md §4.9). Application id, label and signing are the
    // same for both, on purpose: it is one app, net.nawt.zibo_games, with one
    // save, so a tablet moving between the two keeps its players.
    //
    // The private build goes to the family's tablets through the Amazon
    // Appstore's Live App Testing track. Amazon's console warns when a testing
    // build's version code is below the live app's, and its documentation
    // requires a test build that is promoted to live to have a version code at
    // least the live one's. With equal codes, a later public release (store N+1)
    // would outrank the private N on a testing tablet and be offered there as an
    // update over it, and the tablet would lose the private packs. Adding 50,000
    // keeps every private build above the store build of the same commit and
    // above every earlier release.
    //
    // The cost is one-way: Android will not install a lower versionCode over a
    // higher one, so a tablet leaves the testing track for the public build only
    // by uninstalling, after exporting its players (PLAN-transfer.md).
    //
    // Once Android has flavours, a Flutter Android build without `--flavor` no
    // longer finds a single APK (the Flutter tool looks for app-release.apk and
    // the files are now app-store-release.apk and app-private-release.apk), so
    // every Android command passes `--flavor store` or `--flavor private`.
    flavorDimensions += "audience"
    productFlavors {
        create("store") {
            dimension = "audience"
        }
        create("private") {
            dimension = "audience"
            versionCode = flutter.versionCode + 50000
        }
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

dependencies {
    // `PhotoPickerPlugin.kt`'s `PickVisualMedia` contract needs
    // `androidx.activity` 1.6.0+ for `registerForActivityResult`
    // (`PLAN-phase-8.md` §3.3) — pinned explicitly rather than relying on
    // whatever version the Flutter engine's own transitive dependency
    // happens to resolve to.
    implementation("androidx.activity:activity-ktx:1.9.3")
}
