plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    id("maven-publish")
}

android {
    namespace = "com.inferx.llx"
    compileSdk = 36

    defaultConfig {
        minSdk = 24
        targetSdk = 36

        consumerProguardFiles("consumer-rules.pro")

        externalNativeBuild {
            cmake {
                // Release 优化与与 llama.android 对齐的开关
                arguments += listOf(
                    "-DCMAKE_BUILD_TYPE=Release",
                    "-DLLAMA_CURL=OFF",
                    "-DLLAMA_BUILD_COMMON=ON",
                    "-DGGML_LLAMAFILE=OFF"
                )
                cppFlags += listOf("-std=c++17", "-O3", "-fvisibility=hidden")
            }
        }
        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    buildTypes {
        debug {
            isMinifyEnabled = false
        }
        release {
            isMinifyEnabled = false
        }
    }

    externalNativeBuild {
        cmake {
            path = file("CMakeLists.txt")
            version = "3.22.1"
        }
    }

    buildFeatures {
        buildConfig = false
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = "11"
    }

    publishing {
        singleVariant("release") {
            withSourcesJar()
        }
        singleVariant("debug") {
            withSourcesJar()
        }
    }
}

dependencies {
    implementation(kotlin("stdlib"))
}

publishing {
    publications {
        create<MavenPublication>("release") {
            groupId = "ai.inferx"
            artifactId = "llx-android"
            version = "0.1.0"
            afterEvaluate {
                from(components["release"])
            }
        }
    }
}

