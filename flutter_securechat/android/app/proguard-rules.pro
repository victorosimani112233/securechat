# Keep metadata used by platform/plugin reflection while allowing R8 to rename
# and shrink application implementation classes.
-keepattributes RuntimeVisibleAnnotations,RuntimeInvisibleAnnotations,AnnotationDefault,Signature,InnerClasses,EnclosingMethod

# Flutter entry points are discovered from Android manifests and generated
# registrants. R8 already retains manifest components; these rules preserve
# only native callback names that are invoked across JNI.
-keepclasseswithmembers,includedescriptorclasses class * {
    native <methods>;
}

# Workmanager starts this worker by class name from its Android manifest.
-keep class dev.fluttercommunity.workmanager.** extends androidx.work.ListenableWorker { *; }
