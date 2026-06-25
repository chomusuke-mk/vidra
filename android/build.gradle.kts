import com.android.build.api.dsl.CommonExtension
import org.gradle.api.JavaVersion
import org.gradle.api.tasks.compile.JavaCompile
import org.jetbrains.kotlin.gradle.tasks.KotlinCompile
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

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

val libraryJavaVersionString = libraryJavaVersion.majorVersion
val libraryJavaMajorVersion = libraryJavaVersionString.toInt()

fun CommonExtension.applyJavaCompatibility() {
    compileOptions.sourceCompatibility = libraryJavaVersion
    compileOptions.targetCompatibility = libraryJavaVersion
}


subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
    project.evaluationDependsOn(":app")
    if (project.name != "app") {
        val configureCompilationTargets: Project.() -> Unit = {
            
            tasks.withType(JavaCompile::class.java).configureEach {
                sourceCompatibility = libraryJavaVersionString
                targetCompatibility = libraryJavaVersionString
            }

            tasks.withType(KotlinCompile::class.java).configureEach {
                compilerOptions {
                    val currentTargetStr = jvmTarget.orNull?.target
                    val currentTarget = currentTargetStr?.toIntOrNull() ?: 0
                    
                    if (currentTarget < libraryJavaMajorVersion) {
                        jvmTarget.set(JvmTarget.fromTarget(libraryJavaVersionString))
                    }
                }
            }

            (extensions.findByName("android") as? CommonExtension)
                ?.applyJavaCompatibility()
        }

        if (state.executed) {
            configureCompilationTargets()
        } else {
            afterEvaluate { configureCompilationTargets() }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
