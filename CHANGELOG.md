# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0-beta.1-wip]

### Added

- `tracedRecordError(exception, stack, crashlytics:, ...)` — adds
  the exception to the currently active OTel span (as the
  standard `exception` event via `recordException` + sets
  `error.type` / `error.fatal` / `error.reason` attributes) AND
  forwards it to `FirebaseCrashlytics.recordError`. When
  `fatal: true`, the span status is also set to `Error`.
- `tracedRecordFlutterError(details, crashlytics:, fatal:)` — same
  behavior for Flutter framework errors.
- `tracedLog(message, crashlytics:)` — adds a
  `crashlytics.log` event with `log.message` to the active span
  AND forwards to `FirebaseCrashlytics.log`. The breadcrumb that
  lands in Crashlytics also appears as a span event in the
  trace.
- `tracedSetUserIdentifier(identifier, crashlytics:,
  recordOnSpan: true)` — sets the Crashlytics user ID AND
  attaches it to the active span as `enduser.id`. Pass
  `recordOnSpan: false` to keep the UID out of OTel traces if
  treated as PII.
- `runWithoutCrashlyticsInstrumentation` /
  `runWithoutCrashlyticsInstrumentationAsync` — zone-scoped
  helpers that bypass the OTel side. Crashlytics still receives
  the data; only the bridge to OTel is silenced.
- When no active span is present, all helpers degrade
  gracefully: Crashlytics still receives the call, the OTel
  side becomes a no-op.
- Tests cover the full bridge (exception event + error.* attrs
  + span status on fatal), no-active-span graceful behavior,
  breadcrumb logs, user ID propagation (both directions and the
  opt-out), and suppression scope.
