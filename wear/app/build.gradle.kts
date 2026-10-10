plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "io.github.sandipbera35.stepaway.wear"
    compileSdk = 35

    defaultConfig {
        applicationId = "io.github.sandipbera35.stepaway.wear"
        minSdk = 30
        targetSdk = 34
        versionCode = 102
        versionName = "0.1.2"
    }

    buildFeatures {
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            // Debug signing keeps `assembleRelease` usable for testing; real releases are signed separately.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

dependencies {
    // Compose for Wear OS (Apache-2.0). No Google Play Services anywhere.
    implementation(platform("androidx.compose:compose-bom:2025.01.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.wear.compose:compose-material:1.4.1")
    implementation("androidx.wear.compose:compose-foundation:1.4.1")
    implementation("androidx.activity:activity-compose:1.10.1")
    implementation("androidx.core:core-ktx:1.15.0")

    testImplementation("junit:junit:4.13.2")
    testImplementation("com.google.code.gson:gson:2.11.0")
}
