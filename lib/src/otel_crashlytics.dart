// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';

import 'crashlytics_suppression.dart';

/// Records [exception] on the currently active span as the
/// standard OTel `exception` event (via [APISpan.recordException]),
/// AND forwards it to [crashlytics] via `recordError`. The two
/// systems stay in sync without you having to call both.
///
/// On the active span: `exception` event with `exception.type`,
/// `exception.message`, `exception.stacktrace`; plus
/// `error.type`, `error.fatal`, and (when supplied)
/// `error.reason` as span attributes.
///
/// On Crashlytics: standard error record with [reason] /
/// [information] attached.
///
/// If there's no active span (or the active span is invalid),
/// only Crashlytics receives the error — the OTel side becomes a
/// no-op.
///
/// [fatal] is passed through to Crashlytics; when `true`, the
/// span status is also set to `Error`.
Future<void> tracedRecordError(
  Object exception,
  StackTrace? stack, {
  required FirebaseCrashlytics crashlytics,
  Object? reason,
  Iterable<DiagnosticsNode> information = const [],
  bool fatal = false,
}) async {
  if (crashlyticsInstrumentationSuppressed()) {
    return crashlytics.recordError(
      exception,
      stack,
      reason: reason,
      information: information,
      fatal: fatal,
    );
  }
  final activeSpan = Context.current.span;
  if (activeSpan != null && activeSpan.isValid) {
    activeSpan.recordException(exception, stackTrace: stack);
    if (fatal) {
      activeSpan.setStatus(SpanStatusCode.Error, exception.toString());
    }
    activeSpan.addAttributes(OTel.attributes([
      OTel.attributeString(
        ErrorResource.errorType.key,
        exception.runtimeType.toString(),
      ),
      OTel.attributeBool('error.fatal', fatal),
      if (reason != null)
        OTel.attributeString('error.reason', reason.toString()),
    ]));
  }
  return crashlytics.recordError(
    exception,
    stack,
    reason: reason,
    information: information,
    fatal: fatal,
  );
}

/// Records [details] on the currently active span and forwards
/// to [FirebaseCrashlytics.recordFlutterError].
Future<void> tracedRecordFlutterError(
  FlutterErrorDetails details, {
  required FirebaseCrashlytics crashlytics,
  bool fatal = false,
}) async {
  if (crashlyticsInstrumentationSuppressed()) {
    return crashlytics.recordFlutterError(details, fatal: fatal);
  }
  await tracedRecordError(
    details.exception,
    details.stack,
    crashlytics: crashlytics,
    reason: details.context?.toString(),
    information: details.informationCollector?.call() ?? const [],
    fatal: fatal,
  );
}

/// Adds [message] as an event named `crashlytics.log` on the
/// active span and forwards to [FirebaseCrashlytics.log]. The
/// breadcrumb that lands in Crashlytics also lands in the trace.
Future<void> tracedLog(
  String message, {
  required FirebaseCrashlytics crashlytics,
}) async {
  if (crashlyticsInstrumentationSuppressed()) return crashlytics.log(message);
  final activeSpan = Context.current.span;
  if (activeSpan != null && activeSpan.isValid) {
    activeSpan.addEventNow(
      'crashlytics.log',
      OTel.attributesFromMap(<String, Object>{'log.message': message}),
    );
  }
  return crashlytics.log(message);
}

/// Sets the Crashlytics user identifier AND (when [recordOnSpan]
/// is `true`) attaches it to the active span as `enduser.id`.
/// Set `recordOnSpan: false` if UIDs are treated as PII in your
/// traces.
Future<void> tracedSetUserIdentifier(
  String identifier, {
  required FirebaseCrashlytics crashlytics,
  bool recordOnSpan = true,
}) async {
  if (crashlyticsInstrumentationSuppressed()) {
    return crashlytics.setUserIdentifier(identifier);
  }
  final activeSpan = Context.current.span;
  if (recordOnSpan && activeSpan != null && activeSpan.isValid) {
    activeSpan.addAttributes(OTel.attributes([
      OTel.attributeString(Enduser.enduserId.key, identifier),
    ]));
  }
  return crashlytics.setUserIdentifier(identifier);
}
