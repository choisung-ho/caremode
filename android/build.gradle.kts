// 필요한 도구들 가져오기
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
    id("com.google.gms.google-services") version "4.4.2" apply false
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// ▼▼▼ [수정됨] 최신 코틀린 문법 적용한 해결사 코드 ▼▼▼
subprojects {
    if (project.name == "flutter_notification_listener") {
        
        // 1. 안드로이드 설정 (이름표 붙이기 + 자바 1.8)
        project.pluginManager.withPlugin("com.android.library") {
            val android = project.extensions.getByType(com.android.build.gradle.LibraryExtension::class.java)
            android.namespace = "im.zoe.labs.flutter_notification_listener"
            android.compileOptions {
                sourceCompatibility = JavaVersion.VERSION_1_8
                targetCompatibility = JavaVersion.VERSION_1_8
            }
        }

        // 2. 코틀린 설정 (최신 문법 적용!)
        project.tasks.withType(KotlinCompile::class.java).configureEach {
            // 여기가 바뀌었음! (kotlinOptions -> compilerOptions)
            compilerOptions {
                jvmTarget.set(JvmTarget.JVM_1_8)
            }
        }
    }

    if (project.name == "shared_storage") {
        project.pluginManager.withPlugin("com.android.library") {
            val android = project.extensions.getByType(com.android.build.gradle.LibraryExtension::class.java)
            android.namespace = "io.crossingthestreams.shared_storage"
            android.compileOptions {
                sourceCompatibility = JavaVersion.VERSION_1_8
                targetCompatibility = JavaVersion.VERSION_1_8
            }
        }

        project.tasks.withType(KotlinCompile::class.java).configureEach {
            compilerOptions {
                jvmTarget.set(JvmTarget.JVM_1_8)
            }
        }

        // AGP 8: plugin manifest still sets package attr; strip it if present
        val userHome = System.getProperty("user.home")
        val manifestPath = "$userHome/AppData/Local/Pub/Cache/hosted/pub.dev/shared_storage-0.8.1/android/src/main/AndroidManifest.xml"
        val manifestFile = project.file(manifestPath)
        if (manifestFile.exists()) {
            val text = manifestFile.readText()
            if (text.contains("package=\"io.alexrintt.sharedstorage\"")) {
                manifestFile.writeText(
                    text.replace("package=\"io.alexrintt.sharedstorage\"", "")
                )
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}