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
    project.configurations.all {
        resolutionStrategy.eachDependency {
            if (requested.group == "androidx.lifecycle") {
                useVersion("2.8.7")
            }
            if (requested.group == "org.jetbrains.kotlin") {
                useVersion("2.1.0")
            }
        }
    }
    afterEvaluate {
        val extension = extensions.findByName("android")
        if (extension is com.android.build.gradle.BaseExtension) {
            extension.compileSdkVersion(36)
            extension.defaultConfig {
                targetSdkVersion(35)
            }
            if (extension.namespace == null) {
                extension.namespace = "com.translink.driver.deps.${project.name.replace("-", "_")}"
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
