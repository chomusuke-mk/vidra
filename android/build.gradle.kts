import com.android.build.api.dsl.CommonExtension
import org.gradle.api.JavaVersion
import org.gradle.api.tasks.compile.JavaCompile
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile

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

val minimumSupportedJavaVersion = JavaVersion.VERSION_17
val desiredLibraryJavaVersion = JavaVersion.VERSION_21
val libraryJavaVersion = if (desiredLibraryJavaVersion < minimumSupportedJavaVersion) {
    minimumSupportedJavaVersion
} else {
    desiredLibraryJavaVersion
}
val libraryJavaMajorVersion = libraryJavaVersion.majorVersion.toInt()
val libraryJavaVersionString = libraryJavaMajorVersion.toString()

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

fun CommonExtension<*, *, *, *, *, *>.applyJavaCompatibility() {
    compileOptions {
        sourceCompatibility = libraryJavaVersion
        targetCompatibility = libraryJavaVersion
    }
}

subprojects {
    val configureCompilationTargets: Project.() -> Unit = {
        tasks.withType(JavaCompile::class.java).configureEach {
            if (project.name == "app") {
                return@configureEach
            }
            sourceCompatibility = libraryJavaVersionString
            targetCompatibility = libraryJavaVersionString
        }

        tasks.withType(KotlinCompile::class.java).configureEach {
            if (project.name == "app") {
                return@configureEach
            }
            val currentTarget = kotlinOptions.jvmTarget?.toIntOrNull()
            if (currentTarget == null || currentTarget < libraryJavaMajorVersion) {
                kotlinOptions.jvmTarget = libraryJavaVersionString
            }
        }

        if (project.name != "app") {
            (extensions.findByName("android") as? CommonExtension<*, *, *, *, *, *>)
                ?.applyJavaCompatibility()
        }
    }

    if (state.executed) {
        configureCompilationTargets()
    } else {
        afterEvaluate { configureCompilationTargets() }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
