// Licensed under the Apache License, Version 2.0
// Copyright 2025, Mindful Software LLC, All rights reserved.

/// OpenTelemetry bridge for `package:firebase_crashlytics`.
///
/// Records crashes both to Crashlytics and as OTel `exception`
/// events on the currently active span — so the same exception
/// that lands in Crashlytics also lands in your trace, in the
/// span where it happened.
library;

export 'src/crashlytics_suppression.dart';
export 'src/otel_crashlytics.dart';
