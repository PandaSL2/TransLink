buildscript {
    extra["kotlin_version"] = "2.1.0"
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Standard Flutter build directory layout is used.


subprojects {
    val projectCompileSdkVersion = project.property("project.compileSdkVersion").toString().toInt()
    val projectTargetSdkVersion = project.property("project.targetSdkVersion").toString().toInt()
    val projectJavaVersion = project.property("project.javaVersion").toString().toInt()

    project.configurations.all {
        resolutionStrategy.eachDependency {
            if (requested.group == "androidx.lifecycle") {
                useVersion("2.8.7")
            }
            if (requested.group == "org.jetbrains.kotlin") {
                useVersion("2.1.0")
            }
            if (requested.group == "androidx.core" && (requested.name == "core" || requested.name == "core-ktx")) {
                useVersion("1.13.1")
            }
            if (requested.group == "androidx.browser" && requested.name == "browser") {
                useVersion("1.8.0")
            }
        }
    }
    afterEvaluate {
        val extension = extensions.findByName("android")
        if (extension is com.android.build.gradle.BaseExtension) {
            extension.compileSdkVersion(projectCompileSdkVersion)
            extension.defaultConfig {
                targetSdkVersion(projectTargetSdkVersion)
            }
            if (extension.namespace == null) {
                extension.namespace = "com.translink.passenger.deps.${project.name.replace("-", "_")}"
            }
            extension.compileOptions {
                sourceCompatibility = JavaVersion.toVersion(projectJavaVersion)
                targetCompatibility = JavaVersion.toVersion(projectJavaVersion)
            }
        }
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>().configureEach {
            compilerOptions {
                jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.fromTarget(projectJavaVersion.toString()))
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
