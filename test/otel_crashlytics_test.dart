// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

import 'package:dartastic_opentelemetry/dartastic_opentelemetry.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:otel_firebase_crashlytics/otel_firebase_crashlytics.dart';

class _MemorySpanExporter implements SpanExporter {
  final List<Span> spans = [];
  bool _shutdown = false;

  @override
  Future<void> export(List<Span> s) async {
    if (_shutdown) return;
    spans.addAll(s);
  }

  @override
  Future<void> forceFlush() async {}

  @override
  Future<void> shutdown() async {
    _shutdown = true;
  }
}

/// A fake [FirebaseCrashlytics] that records calls. Implemented via
/// noSuchMethod so we don't need a real Firebase instance.
class _FakeCrashlytics implements FirebaseCrashlytics {
  final List<Map<String, Object?>> errors = [];
  final List<String> logs = [];
  String? userId;

  @override
  Future<void> recordError(
    dynamic exception,
    StackTrace? stack, {
    dynamic reason,
    Iterable<Object> information = const [],
    bool? printDetails,
    bool fatal = false,
  }) async {
    errors.add({
      'exception': exception,
      'stack': stack,
      'reason': reason,
      'fatal': fatal,
    });
  }

  @override
  Future<void> log(String message) async {
    logs.add(message);
  }

  @override
  Future<void> setUserIdentifier(String identifier) async {
    userId = identifier;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, Object> _attrs(Span span) =>
    {for (final a in span.attributes.toList()) a.key: a.value};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Crashlytics ↔ OTel bridge', () {
    late _MemorySpanExporter exporter;
    late _FakeCrashlytics crashlytics;

    setUp(() async {
      await OTel.reset();
      exporter = _MemorySpanExporter();
      await OTel.initialize(
        serviceName: 'crashlytics-otel-test',
        detectPlatformResources: false,
        spanProcessor: SimpleSpanProcessor(exporter),
      );
      crashlytics = _FakeCrashlytics();
    });

    tearDown(() async {
      await OTel.shutdown();
      await OTel.reset();
    });

    test('tracedRecordError adds exception event + forwards to Crashlytics',
        () async {
      await OTel.tracer().startActiveSpanAsync<void>(
        name: 'checkout',
        fn: (_) async {
          await tracedRecordError(
            StateError('out of stock'),
            StackTrace.current,
            crashlytics: crashlytics,
            reason: 'cart validation',
            fatal: false,
          );
        },
      );

      // OTel side: active span carries exception event + error attrs
      final span = exporter.spans.firstWhere((s) => s.name == 'checkout');
      final events = span.spanEvents ?? [];
      expect(events.any((e) => e.name == 'exception'), isTrue);
      final attrs = _attrs(span);
      expect(attrs['error.type'], equals('StateError'));
      expect(attrs['error.fatal'], equals(false));
      expect(attrs['error.reason'], equals('cart validation'));
      // Non-fatal — span status should NOT flip to Error.
      expect(span.status, isNot(equals(SpanStatusCode.Error)));

      // Crashlytics side: error was recorded
      expect(crashlytics.errors, hasLength(1));
      expect(crashlytics.errors.first['exception'], isA<StateError>());
      expect(crashlytics.errors.first['fatal'], equals(false));
    });

    test('fatal:true also flips span status to Error', () async {
      await OTel.tracer().startActiveSpanAsync<void>(
        name: 'op',
        fn: (_) async {
          await tracedRecordError(
            Exception('boom'),
            StackTrace.current,
            crashlytics: crashlytics,
            fatal: true,
          );
        },
      );

      final span = exporter.spans.firstWhere((s) => s.name == 'op');
      expect(span.status, equals(SpanStatusCode.Error));
    });

    test('no active span — Crashlytics still receives the error', () async {
      await tracedRecordError(
        Exception('orphan'),
        StackTrace.current,
        crashlytics: crashlytics,
      );
      expect(crashlytics.errors, hasLength(1));
      // No active span: no span emitted by this bridge.
      expect(exporter.spans, isEmpty);
    });

    test('tracedLog adds crashlytics.log event + forwards to Crashlytics',
        () async {
      await OTel.tracer().startActiveSpanAsync<void>(
        name: 'op',
        fn: (_) async {
          await tracedLog('breadcrumb', crashlytics: crashlytics);
        },
      );

      final span = exporter.spans.firstWhere((s) => s.name == 'op');
      final events = span.spanEvents ?? [];
      final log = events.firstWhere((e) => e.name == 'crashlytics.log');
      final logAttrs = {
        for (final a in (log.attributes?.toList() ?? <Attribute<Object>>[]))
          a.key: a.value,
      };
      expect(logAttrs['log.message'], equals('breadcrumb'));
      expect(crashlytics.logs, equals(['breadcrumb']));
    });

    test('tracedSetUserIdentifier attaches enduser.id by default', () async {
      await OTel.tracer().startActiveSpanAsync<void>(
        name: 'op',
        fn: (_) async {
          await tracedSetUserIdentifier(
            'user-42',
            crashlytics: crashlytics,
          );
        },
      );

      final span = exporter.spans.firstWhere((s) => s.name == 'op');
      expect(_attrs(span)['enduser.id'], equals('user-42'));
      expect(crashlytics.userId, equals('user-42'));
    });

    test('recordOnSpan:false omits enduser.id from span', () async {
      await OTel.tracer().startActiveSpanAsync<void>(
        name: 'op',
        fn: (_) async {
          await tracedSetUserIdentifier(
            'user-42',
            crashlytics: crashlytics,
            recordOnSpan: false,
          );
        },
      );
      final span = exporter.spans.firstWhere((s) => s.name == 'op');
      expect(_attrs(span).containsKey('enduser.id'), isFalse);
      // Crashlytics still receives the UID.
      expect(crashlytics.userId, equals('user-42'));
    });

    test('runWithoutCrashlyticsInstrumentationAsync bypasses OTel side',
        () async {
      await OTel.tracer().startActiveSpanAsync<void>(
        name: 'op',
        fn: (_) async {
          await runWithoutCrashlyticsInstrumentationAsync(() async {
            await tracedRecordError(
              StateError('quiet'),
              null,
              crashlytics: crashlytics,
            );
          });
        },
      );

      final span = exporter.spans.firstWhere((s) => s.name == 'op');
      final events = span.spanEvents ?? [];
      expect(events.any((e) => e.name == 'exception'), isFalse);
      // Crashlytics still records, regardless of OTel suppression.
      expect(crashlytics.errors, hasLength(1));
    });
  });
}
