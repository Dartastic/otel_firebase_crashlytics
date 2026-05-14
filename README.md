# otel_firebase_crashlytics

OpenTelemetry bridge for
[`package:firebase_crashlytics`](https://pub.dev/packages/firebase_crashlytics),
built on the
[Dartastic OpenTelemetry SDK](https://pub.dev/packages/dartastic_opentelemetry).

Records crashes both to Crashlytics **and** as OTel `exception`
events on the currently active span — so the same exception that
lands in Crashlytics also lands in the trace, in the span where
it happened. One call, two destinations.

```dart
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:otel_firebase_crashlytics/otel_firebase_crashlytics.dart';

final crashlytics = FirebaseCrashlytics.instance;

try {
  await checkout();
} catch (e, st) {
  await tracedRecordError(
    e, st,
    crashlytics: crashlytics,
    reason: 'cart validation',
    fatal: false,
  );
}

await tracedLog('user confirmed cart', crashlytics: crashlytics);
await tracedSetUserIdentifier(user.uid, crashlytics: crashlytics);
```

## What lands where

When called inside an active span (`tracer.startActiveSpan` or
similar):

| Action | OTel span | Crashlytics |
|---|---|---|
| `tracedRecordError` (non-fatal) | `exception` event with type/message/stack; `error.type`, `error.fatal=false`, `error.reason` attributes | `recordError(fatal: false)` |
| `tracedRecordError` (fatal) | same + span status `Error` | `recordError(fatal: true)` |
| `tracedRecordFlutterError` | same as recordError, with `reason` derived from `details.context` | `recordFlutterError(fatal:)` |
| `tracedLog` | `crashlytics.log` event with `log.message` attribute | `log(message)` |
| `tracedSetUserIdentifier` | `enduser.id` attribute on the active span (opt-out via `recordOnSpan: false`) | `setUserIdentifier(id)` |

When **no** active span is present, the OTel side becomes a
no-op — Crashlytics still receives the call. Helpers degrade
gracefully so you can sprinkle them anywhere without worrying
about whether you're inside a traced scope.

## Self-recursion guard

```dart
await runWithoutCrashlyticsInstrumentationAsync(() async {
  await tracedRecordError(e, st, crashlytics: crashlytics);
});
```

Inside the helper's zone the **OTel side** becomes a passthrough;
Crashlytics still records normally. Use this if you have a span
processor that's emitting Crashlytics signals on its own (e.g.,
to avoid double-counting in dashboards).

## Why a bridge instead of an extension?

The helpers are top-level functions taking `crashlytics:` as a
named parameter rather than extension methods on
`FirebaseCrashlytics`. Reasons:

- It makes the dependency explicit at the call site — no implicit
  reliance on `FirebaseCrashlytics.instance` you can't inject in
  tests.
- The behavior is genuinely two-sided (OTel side + Crashlytics
  side), not a wrapped call. Top-level is clearer about that.
- Easier to unit-test with a `FirebaseCrashlytics` fake (see this
  package's tests for an example).

## Caveats

- The wrapper calls `Context.current.span` once at the top of each
  helper; if the active span changes after that (which would be
  unusual inside a synchronous frame), the recorded events stay
  on the original span. That's intentional — you're recording
  the error in the context where it was caught.
- This package does NOT install a `SpanProcessor` that
  automatically forwards every OTel exception to Crashlytics.
  That would be a different package; this one is the
  user-driven bridge.
- The wrapper does not call `getTracer` — it doesn't open new
  spans, it decorates the existing one. `OTel.initialize()` must
  still have run (so `Context.current` is meaningful).

## License

Apache 2.0 — see `LICENSE`.
