plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
    id("com.vanniktech.maven.publish")
}

android {
    namespace = "io.github.reers.ruyi"
    compileSdk = 35

    defaultConfig {
        minSdk = 24
        consumerProguardFiles("consumer-rules.pro")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    api("io.github.vnixx:thorvg:0.0.1")
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
