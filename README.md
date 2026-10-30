# Pocket Ledger

An offline Flutter Android app for recording daily income and expenses and reviewing monthly results. Currency is PKR throughout; this version does not mix or convert currencies.

## Included

- Add, edit and delete dated income/expense entries with categories and optional notes.
- Dashboard: monthly income, expenses, net savings, savings rate and daily spending bars.
- Month/year selector, entry filters and recent transactions.
- Reports: spending by category and a six-month income/expense/net overview.
- Export selected month to CSV using Android's Save dialog.
- Save and restore a complete JSON backup using Android's document picker.
- Local SQLite persistence; no account, server, ads, analytics or ongoing network requirement.
- Light Material 3 UI, empty/error/loading states, duplicate-submit protection and accessible action labels.

## Build on Windows

Install Flutter, Android Studio and its Android SDK. Flutter 3.29.3 / Dart 3.7 is the intended baseline. Use `flutter doctor` to finish setup and `flutter doctor --android-licenses` if prompted.

Open PowerShell in this project's root:

```powershell
powershell -ExecutionPolicy Bypass -File .\tool\setup.ps1
dart format lib test
flutter analyze
flutter test
flutter run
```

Setup uses Flutter's official generator to fill in Android build files, launcher icons and the Gradle wrapper while retaining this project's existing Dart code, manifest and native document bridge. Run setup before opening the Android subproject. It needs internet for the Flutter/Android dependencies on first use. Do not add `--overwrite` to the generator command.

On macOS/Linux use `bash tool/setup.sh` instead of the PowerShell command.

Create an installable APK:

```powershell
flutter build apk --debug
```

Find it at `build/app/outputs/flutter-apk/app-debug.apk`. Copy to your Android phone and open it to install. This is a development-signed APK for personal testing. Keep the same signing identity for upgrades; uninstalling to change signing identity removes app-local records. Save a backup before changing builds or phones.

For distribution, configure a private release signing key using Flutter's Android release guide, then run `flutter build apk --release`. Do not publish the key. Android minimum/target SDK values come from the generated Flutter Android template and resolved plugin requirements.

## GitHub releases and in-app updates

Repository: [farrukh47/pocket-ledger](https://github.com/farrukh47/pocket-ledger)

1. Push to `main` runs CI (analyze, test, release APK artifact).
2. Open **Actions → Release APK → Run workflow** and choose patch/minor/major.
   - First run publishes the current `pubspec.yaml` version (for example `1.0.0+1`).
   - Later runs auto-bump the version and create a tagged GitHub Release with `pocket-ledger-<version>+<build>.apk`.
3. In the app, open **⋮ → Check for updates** to download and install the latest release.

Local and CI builds share `android/app/shared-keystore.jks` so updates install over the previous APK without uninstalling.

## Using it

1. Tap **Add entry**, choose income or expense, enter an amount, category and date, then save.
2. Use the month arrows or tap the month heading to browse any month.
3. Tap an entry to edit it; its menu also has Delete with confirmation.
4. Open **Reports** for category totals and the six-month overview.
5. Use the top-right menu for CSV export, full backup or restore.

Dashboard net is the selected month's income minus expenses, not a bank-account or carried-forward balance. Dates are local calendar dates; no UTC conversion shifts entries between days. Amounts support two decimal places, stored as integer paisa rather than floating point. Enter `1250.50`, without commas. Future-dated entries are allowed within 2000–2100.

## Data and recovery

SQLite lives in Android's private app storage. The app database is not separately encrypted and there is no app PIN or biometric lock. Device access is protected by your Android screen lock. Automatic Android backup is disabled in the supplied manifest. Manual JSON/CSV exports are plaintext and go only where you choose in the Android picker.

**Save a full backup regularly, particularly before uninstalling or changing phones.** Restore validates the entire file before replacing records in one transaction. You must confirm replacement. A failed validation leaves current data intact. Backup format v1 supports PKR, a maximum of 20,000 entries and a 5 MiB JSON file; oversized exports are rejected rather than creating a file the app cannot restore. CSV is a monthly report and cannot be restored as a backup. For a recovery rehearsal, save JSON, restore it on a separate emulator/test install and compare counts and totals.

## Structure

- `lib/domain/entry.dart`: validation, exact money, date-only values and report calculations.
- `lib/data/ledger_repository.dart`: parameterized SQLite CRUD, schema v1, backups and CSV.
- `lib/data/document_service.dart`: Flutter boundary to Android document dialogs.
- `lib/ui/`: dashboard/reports, list and entry form.
- `android/.../MainActivity.kt`: document picker and bounded background file I/O.
- `test/`: domain, SQLite integration and dashboard tests.

This is a single-user local application. Server APIs, HTTP status codes, authentication, multi-tenancy and web hosting are not applicable. The trust boundaries are form input, backup files and the Android document provider. Controls include strict backup field/type validation, length/size limits, integer-money constraints, bound SQL parameters, transactional restore, CSV formula protection and user-confirmed destructive operations.

## Verification status

Executed here: Dart grammar parsing for all source/test files; embedded SQLite schema and real SQLite month-boundary/integrity checks; YAML/XML parsing and shell syntax checks; package content inspection.

Not executed here: Flutter dependency resolution, Dart type analysis, Flutter unit/widget tests, Android compilation, device UI/accessibility checks or file-picker end-to-end tests. Flutter and the Android SDK are absent in this environment. Run the commands above or the included workflow before relying on the app. No APK is included.

The source includes direct dependency versions; a transitive `pubspec.lock` is generated by setup. Commit that lockfile after a successful dependency resolution to preserve future builds. No placeholder transactions are inserted.

References: [Flutter SQLite cookbook](https://docs.flutter.dev/cookbook/persistence/sqlite), [Android deployment](https://docs.flutter.dev/deployment/android).
