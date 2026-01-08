plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

configurations.all {
    resolutionStrategy.eachDependency {
        if (requested.group == "androidx.lifecycle") {
            useVersion("2.8.7")
        }
    }
}

android {
    namespace = "com.translink.driver.translink_driver"
    compileSdk = project.property("project.compileSdkVersion").toString().toInt()
    ndkVersion = flutter.ndkVersion

    lint {
        checkReleaseBuilds = false
        abortOnError = false
    }

    compileOptions {
        sourceCompatibility = JavaVersion.toVersion(project.property("project.javaVersion").toString().toInt())
        targetCompatibility = JavaVersion.toVersion(project.property("project.javaVersion").toString().toInt())
        isCoreLibraryDesugaringEnabled = true
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.fromTarget(project.property("project.javaVersion").toString()))
        }
    }

    defaultConfig {
        applicationId = "com.translink.driver.translink_driver"
        minSdk = flutter.minSdkVersion
        targetSdk = project.property("project.targetSdkVersion").toString().toInt()
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    packaging {
        resources {
            excludes.add("**/LICENSE*")
            excludes.add("**/META-INF/*.version")
        }
    }

    // Expert workaround: Ensure APKs are copied to the Flutter build directory if the plugin fails to do so.
    applicationVariants.all {
        val variant = this
        val outputDir = File(project.projectDir, "../../build/app/outputs/flutter-apk")
        
        variant.outputs.all {
            val output = this as com.android.build.gradle.internal.api.BaseVariantOutputImpl
            variant.assembleProvider.get().doLast {
                copy {
                    from(output.outputFile)
                    into(outputDir)
                    rename { "app-${variant.buildType.name}.apk" }
                }
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
