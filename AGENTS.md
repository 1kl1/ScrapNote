# Repository Guidelines

## Project Structure & Module Organization

This is a Flutter application targeting Android, iOS, macOS, Windows, and web.
Keep Dart application code in `lib/`; the current entry point is
`lib/main.dart`. Add feature code in focused files under `lib/` (for example,
`lib/features/notes/note_list.dart`) rather than expanding the entry point.
Put widget and unit tests in `test/`, mirroring the `lib/` path. Platform
runner configuration lives in `android/`, `ios/`, `macos/`, `windows/`, and
`web/`; change it only for platform-specific work. Treat generated Flutter
files such as `GeneratedPluginRegistrant.*` and `ephemeral/` content as
generated output.

## Build, Test, and Development Commands

- `flutter pub get` — install dependencies declared in `pubspec.yaml`.
- `flutter analyze` — run the configured Dart and Flutter lints.
- `flutter test` — run all tests in `test/`.
- `flutter run` — launch the app on a selected connected device or desktop
  target.
- `flutter build <target>` — create a release build, such as
  `flutter build web` or `flutter build apk`.

Run `flutter analyze` and `flutter test` before submitting changes. When
changing dependencies, commit the corresponding `pubspec.lock` update.

## Coding Style & Naming Conventions

Follow the `flutter_lints` rules in `analysis_options.yaml`; do not suppress a
lint without a short justification. Format edited Dart files with `dart format
lib test` (two-space indentation). Use `snake_case.dart` for filenames,
`PascalCase` for types and widgets, and `lowerCamelCase` for members and local
variables. Prefer small, `const` widgets where possible and give UI components
names that express their role, such as `NoteEditor`.

## Forui UI Library

Use [Forui](https://forui.dev/docs) for new shared UI controls and layouts.
The project uses `forui: ^0.25.0`, which is compatible with its Flutter 3.44
and Dart 3.12 toolchain; do not upgrade to Forui 0.26 without first upgrading
Flutter. Import `package:forui/forui.dart` and place `FTheme` below the root
`MaterialApp` before using `F*` widgets. Prefer Forui equivalents such as
`FScaffold`, `FButton`, `FTextField`, and `FCard` for new UI. Configure visual
changes through the shared Forui theme instead of one-off widget styling, and
consult the Forui documentation before introducing overlays or controllers.

## Testing Guidelines

Use the built-in `flutter_test` package. Name test files `*_test.dart` and
group tests by behavior, for example `group('NoteEditor', ...)`. Add a focused
test for every changed user-visible behavior or bug fix; use widget tests for
UI interactions and unit tests for non-widget logic. Keep tests deterministic
and independent of external services.

## Commit & Pull Request Guidelines

This checkout has no Git history, so no established commit convention can be
derived. Use concise imperative subjects, preferably Conventional Commit style:
`feat: add note editor` or `fix: preserve draft text`. Keep commits focused.
Pull requests should explain the change and testing performed, link relevant
issues, and include screenshots or recordings for visible UI changes. Note any
platform-specific validation or follow-up work.
