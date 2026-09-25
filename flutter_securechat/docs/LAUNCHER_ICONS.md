# Launcher icons

Android and iOS use the existing Elcim artwork from
`assets/images/new_logo.png`. The source artwork is unchanged.

- Android: five legacy densities, plus adaptive foreground/background layers.
  Round launchers use the same adaptive resource. Notification icons are unchanged.
- iOS: all sizes in the existing AppIcon catalog, including the opaque
  1024-pixel store icon. System corner masks are not baked into transparency.

The generated PNGs are committed source resources. Normal builds, including
air-gapped builds, do not require an additional package or image tool.

Only when regenerating artwork, install ImageMagick (`convert`) and run:

```sh
dart tool/generate_launcher_icons.dart
dart tool/generate_launcher_icons.dart --check
flutter test test/launcher_icons_test.dart
```

The generator removes transparent source margins, preserves aspect ratio,
and reads the iOS catalog as JSON. Tests check dimensions, nonblank artwork,
iOS opacity, Android density resources and manifest references.
