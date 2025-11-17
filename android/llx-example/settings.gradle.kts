pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
    plugins {
        id("com.android.application") version "8.8.0"
        id("com.android.library") version "8.8.0"
        id("org.jetbrains.kotlin.android") version "2.0.21"
        id("org.jetbrains.kotlin.plugin.compose") version "2.0.21"
    }
}

dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
        // 如使用本地 maven 发布的 AAR，可解开下一行
        // mavenLocal()
    }
}

rootProject.name = "llx-example"
include(":app")
// 同一个仓库中的兄弟模块
include(":llx-android")
project(":llx-android").projectDir = file("../llx-android")

