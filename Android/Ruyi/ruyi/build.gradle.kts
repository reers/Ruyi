plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    id("com.vanniktech.maven.publish")
}

android {
    namespace = "io.github.reers.ruyi"
    compileSdk = 35
    ndkVersion = "27.2.12479018"

    defaultConfig {
        minSdk = 24
        consumerProguardFiles("consumer-rules.pro")

        ndk {
            abiFilters += listOf("arm64-v8a")
        }

        externalNativeBuild {
            cmake {
                cppFlags += "-std=c++17"
                arguments += listOf(
                    "-DANDROID_STL=c++_shared",
                )
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    buildFeatures {
        // Consume Prefab headers / libthorvg.so from io.github.vnixx:thorvg.
        prefab = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    packaging {
        jniLibs {
            // Prefab links against thorvg; do not also ship its .so from this AAR.
            // Consumers get libthorvg.so from the transitive io.github.vnixx:thorvg AAR.
            excludes += setOf("**/libthorvg.so")
            pickFirsts += "**/libc++_shared.so"
        }
    }
}

dependencies {
    // Prefab C API only. JNI + Kotlin bridge live in this module.
    api("io.github.vnixx:thorvg:1.1.0")
}

mavenPublishing {
    // Central Portal (not legacy OSSRH). Manual "Publish" on the website after upload.
    // Override with gradle.properties: mavenCentralAutomaticPublishing=true
    publishToMavenCentral()
    signAllPublications()

    coordinates(
        groupId = providers.gradleProperty("GROUP").get(),
        artifactId = providers.gradleProperty("POM_ARTIFACT_ID").get(),
        version = providers.gradleProperty("VERSION_NAME").get(),
    )

    pom {
        name.set(providers.gradleProperty("POM_NAME").get())
        description.set(providers.gradleProperty("POM_DESCRIPTION").get())
        inceptionYear.set(providers.gradleProperty("POM_INCEPTION_YEAR").get())
        url.set(providers.gradleProperty("POM_URL").get())
        licenses {
            license {
                name.set(providers.gradleProperty("POM_LICENSE_NAME").get())
                url.set(providers.gradleProperty("POM_LICENSE_URL").get())
                distribution.set(providers.gradleProperty("POM_LICENSE_DIST").get())
            }
        }
        developers {
            developer {
                id.set(providers.gradleProperty("POM_DEVELOPER_ID").get())
                name.set(providers.gradleProperty("POM_DEVELOPER_NAME").get())
                url.set(providers.gradleProperty("POM_DEVELOPER_URL").get())
            }
        }
        scm {
            url.set(providers.gradleProperty("POM_SCM_URL").get())
            connection.set(providers.gradleProperty("POM_SCM_CONNECTION").get())
            developerConnection.set(providers.gradleProperty("POM_SCM_DEV_CONNECTION").get())
        }
    }
}
