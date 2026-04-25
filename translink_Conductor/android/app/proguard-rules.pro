## Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

## Supabase
-keepattributes Signature,Annotation,EnclosingMethod
-keep class io.github.jan.supabase.** { *; }
-keep class io.github.jan.supabase.postgrest.** { *; }
-keep class io.github.jan.supabase.storage.** { *; }
-keep class io.github.jan.supabase.gotrue.** { *; }
-keep class io.github.jan.supabase.realtime.** { *; }

## OkHttp3 / Retrofit / Okio
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn javax.annotation.**
-dontwarn org.conscrypt.**

## Google Maps & Play Services
-keep class com.google.android.gms.maps.** { *; }
-keep interface com.google.android.gms.maps.** { *; }
-keep class com.google.android.gms.common.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**
-dontwarn com.google.android.play.**

## Firebase (if used indirectly)
-dontwarn com.google.firebase.**
-keep class com.google.firebase.** { *; }

## Kotlin Coroutines & StdLib
-keep class kotlinx.coroutines.** { *; }
-keep class kotlin.** { *; }
-dontwarn kotlinx.coroutines.**
-dontwarn kotlin.**

## Geolocator / Geocoding
-keep class com.baseflow.geolocator.** { *; }
-keep class io.flutter.plugins.geocoding.** { *; }

## Local Notifications
-keep class com.dexterous.flutterlocalnotifications.** { *; }

## Share Plus
-keep class dev.fluttercommunity.plus.share.** { *; }

## General R8 rules for shrinking
-optimizationpasses 5
-allowaccessmodification
-dontpreverify
-ignorewarnings
-dontnote
-dontwarn **
