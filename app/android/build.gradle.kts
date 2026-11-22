allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Every plugin builds its native code with the app's NDK, the one Flutter pins
// (`flutter.ndkVersion` in app/build.gradle.kts), rather than whichever NDK its
// own build.gradle names. minisound_ffi 3.0.0 names r23b (23.1.7779620), and
// from AGP 9.5 the SDK installer refuses that archive outright: a symlink in it
// trips the zip-slip check ("would escape the output directory"), so the build
// fails while configuring the plugin. One NDK for the whole build also saves CI
// downloading a second one on every run.
//
// finalizeDsl runs after the plugin's own `android {}` block, so this replaces
// its value instead of being replaced by it. :app is already evaluated by then
// (the evaluationDependsOn above), so its NDK version is final.
subprojects {
    pluginManager.withPlugin("com.android.library") {
        extensions.configure<com.android.build.api.variant.LibraryAndroidComponentsExtension> {
            finalizeDsl { library ->
                library.ndkVersion =
                    project(":app")
                        .extensions
                        .getByType<com.android.build.api.dsl.ApplicationExtension>()
                        .ndkVersion
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
