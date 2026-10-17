# OpenSpend

Expense tracker for iOS 17.4+ (SwiftUI, SwiftData, App Intents, WidgetKit). Accounts are either local-only or synced two-way with a tab in a Google Sheet.

## Build

```sh
brew install xcodegen
xcodegen generate
open OpenSpend.xcodeproj
```

Before the first run, edit `project.yml`:

| Setting | Value |
|---|---|
| `APP_BUNDLE_ID` | your bundle id |
| `APP_GROUP` | `group.<your bundle id>`. Register it in your Apple Developer account. |
| `GOOGLE_CLIENT_ID` | iOS OAuth client id (see below) |
| `GOOGLE_REVERSED_CLIENT_ID` | the same id reversed: `com.googleusercontent.apps.<id>` |
| `DEVELOPMENT_TEAM` | your team id |

Add an app icon to `OpenSpend/Assets.xcassets/AppIcon.appiconset` (1024×1024).

## Google Cloud setup

1. Create a project at console.cloud.google.com.
2. Enable the **Google Sheets API** and **Google Drive API**.
3. Set up the OAuth consent screen. Add the scopes `spreadsheets` and `drive.metadata.readonly`. Add yourself as a test user while the app is in testing.
4. Create Credentials › OAuth client ID › **iOS**, using your bundle id. Copy the client id into `project.yml`.

`drive.metadata.readonly` only lists spreadsheet names. Publishing the app needs Google verification because `spreadsheets` is a sensitive scope.

## How sync works

- Each account links to one tab. Row 1 is the header. You map Title, Amount and Date (required) and Currency, Category, Payment Method, Notes and Tags (optional) to columns.
- The app adds a `OpenSpend ID` column to match rows. Don't edit it. Rows typed in by hand get an ID on the next sync.
- Every sync reads the whole tab, in chunks set by Advanced › Rows per request. It pushes local changes first, then pulls. When the same row was edited in both places, the local edit wins.
- Offline edits are queued (shown with a sync icon) and retried. Sync runs on launch, on foreground (at most once a minute), on pull-to-refresh, after each edit, and through background app refresh.
- Removing an account or spreadsheet link never deletes anything in Google Sheets.

## Tests

`OpenSpendTests` covers amount parsing and the sheet row codec. Run them with ⌘U.

## Download the IPA

Every push to `main` builds an unsigned `OpenSpend.ipa` and publishes it as the `latest` pre-release under GitHub Releases. Pushing a `v*` tag (for example `git tag v1.0.0 && git push --tags`) creates a versioned release.

The IPA is unsigned, so install it with a sideloading tool that signs it for you: AltStore, Sideloadly or TrollStore. When the tool signs it without the app group, the widget can't see the app's data, but the app itself works normally.
