# The autofill service and its activities are instantiated by the platform
# from the manifest, so nothing in the code graph references them and R8 would
# otherwise strip them.
-keep class com.sablekey.app.autofill.** { *; }
-keep class com.sablekey.app.MainActivity { *; }

# Flutter's embedding is likewise entered from native code.
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# flutter_secure_storage relies on the AndroidX security library, whose
# key providers are resolved reflectively.
-keep class androidx.security.crypto.** { *; }

# Keep the line numbers so a release crash report is readable, but strip the
# source file names.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile
