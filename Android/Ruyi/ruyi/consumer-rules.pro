# Keep Ruyi JNI bridge entry points when consumers minify.
-keep class io.github.reers.ruyi.ThorVG { *; }
-keepclassmembers class io.github.reers.ruyi.ThorVG {
    native <methods>;
}
