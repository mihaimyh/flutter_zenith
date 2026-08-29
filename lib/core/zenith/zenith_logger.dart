import 'dart:collection';

import 'package:flutter/foundation.dart' show debugPrint;

import 'zenith_container.dart';

/// Log severity levels.
enum ZenithLogLevel {
  /// Verbose diagnostic details.
  verbose,

  /// Debug information during development.
  debug,

  /// Informational operational events.
  info,

  /// Warnings indicating potential issues.
  warning,

  /// Errors encountered during execution.
  error,

  /// Fatal unrecoverable app crashes.
  fatal,
}

/// A structured log event containing message template, properties, timestamp, and exception details.
class ZenithLogEvent {
  /// Severity level of this event.
  final ZenithLogLevel level;

  /// Raw message template (e.g. "User {userId} checked out {amount}").
  final String template;

  /// Structured properties associated with this log event.
  final Map<String, dynamic> properties;

  /// Exact timestamp when the event occurred.
  final DateTime timestamp;

  /// Optional error object.
  final Object? error;

  /// Optional stack trace.
  final StackTrace? stackTrace;

  /// Creates a [ZenithLogEvent].
  ZenithLogEvent({
    required this.level,
    required this.template,
    required this.properties,
    required this.timestamp,
    this.error,
    this.stackTrace,
  });

  /// Evaluates the message template with property substitutions.
  String get formattedMessage {
    var result = template;
    properties.forEach((key, val) {
      result = result.replaceAll('{$key}', val.toString());
    });
    return result;
  }

  @override
  String toString() =>
      '[${level.name.toUpperCase()}] $timestamp - $formattedMessage';
}

/// Abstract destination interface for structured log events (e.g. Console, Sentry, Crashlytics, File).
abstract class ZenithLogSink {
  /// Emits a structured [ZenithLogEvent] to this sink.
  void emit(ZenithLogEvent event);
}

/// Standard console log sink using Flutter's [debugPrint].
class ConsoleSink implements ZenithLogSink {
  @override
  void emit(ZenithLogEvent event) {
    debugPrint(event.toString());
  }
}

/// In-memory ring buffer sink holding a fixed maximum capacity of recent logs.
///
/// Prevents out-of-memory growth by automatically evicting oldest logs when [maxCapacity] is reached.
class MemoryRingBufferSink implements ZenithLogSink {
  /// Maximum number of log events retained in RAM.
  final int maxCapacity;

  final DoubleLinkedQueue<ZenithLogEvent> _buffer =
      DoubleLinkedQueue<ZenithLogEvent>();

  /// Creates a [MemoryRingBufferSink].
  MemoryRingBufferSink({this.maxCapacity = 100});

  /// Unmodifiable view of currently retained log events (oldest first).
  List<ZenithLogEvent> get logs => List.unmodifiable(_buffer);

  @override
  void emit(ZenithLogEvent event) {
    if (_buffer.length >= maxCapacity) {
      _buffer.removeFirst(); // Evict oldest
    }
    _buffer.addLast(event);
  }

  /// Clears all retained log events.
  void clear() {
    _buffer.clear();
  }
}

/// A structured logging engine with automatic PII redaction and extensible sinks.
///
/// Equivalent to Serilog in .NET.
///
/// ```dart
/// final logger = ZenithLogger(sinks: [ConsoleSink(), MemoryRingBufferSink()]);
/// logger.info('User {userId} logged in', {'userId': '123'});
/// ```
class ZenithLogger {
  /// List of active sinks receiving log events.
  final List<ZenithLogSink> sinks;

  /// Keys matching these lowercase patterns will have values automatically redacted.
  final Set<String> _piiKeys = <String>{
    'password',
    'token',
    'auth_token',
    'secret',
    'creditcard',
    'ssn',
    'auth_header',
  };

  /// Creates a [ZenithLogger] with the given [sinks].
  ZenithLogger({List<ZenithLogSink>? sinks})
      : sinks = sinks ?? <ZenithLogSink>[ConsoleSink()];

  /// Logs an informational message.
  void info(
    String template, [
    Map<String, dynamic>? properties,
    Object? error,
    StackTrace? stackTrace,
  ]) {
    log(
      ZenithLogLevel.info,
      template,
      properties,
      error,
      stackTrace,
    );
  }

  /// Logs a warning message.
  void warning(
    String template, [
    Map<String, dynamic>? properties,
    Object? error,
    StackTrace? stackTrace,
  ]) {
    log(
      ZenithLogLevel.warning,
      template,
      properties,
      error,
      stackTrace,
    );
  }

  /// Logs an error message.
  void error(
    String template, [
    Map<String, dynamic>? properties,
    Object? error,
    StackTrace? stackTrace,
  ]) {
    log(
      ZenithLogLevel.error,
      template,
      properties,
      error,
      stackTrace,
    );
  }

  /// Core log emission method. Applies PII redaction to properties and broadcasts to sinks.
  void log(
    ZenithLogLevel level,
    String template, [
    Map<String, dynamic>? properties,
    Object? error,
    StackTrace? stackTrace,
  ]) {
    final sanitizedProperties = _redactPii(properties ?? const {});
    final event = ZenithLogEvent(
      level: level,
      template: template,
      properties: sanitizedProperties,
      timestamp: DateTime.now(),
      error: error,
      stackTrace: stackTrace,
    );

    for (final sink in sinks) {
      try {
        sink.emit(event);
      } catch (_) {}
    }
  }

  Map<String, dynamic> _redactPii(Map<String, dynamic> input) {
    final sanitized = Map<String, dynamic>.from(input);
    for (final entry in input.entries) {
      final lowerKey = entry.key.toLowerCase().replaceAll('_', '');
      if (_piiKeys.any((k) => lowerKey.contains(k))) {
        sanitized[entry.key] = '[REDACTED]';
      }
    }
    return sanitized;
  }
}

/// Extension on [ZenithContainer] and [ZenithRef] for structured logger access.
extension ZenithLoggerContainerX on ZenithContainer {
  /// Gets or creates the [ZenithLogger] for this container.
  ZenithLogger get logger {
    return getOrCreateNode<ZenithLogger>(
      '_zenith_logger_key',
      (ref) => ZenithLogger(),
    ).value;
  }
}

/// Extension on [ZenithRef] for logger access.
extension ZenithLoggerRefX on ZenithRef {
  /// Gets the [ZenithLogger] for this ref's container.
  ZenithLogger get logger => container.logger;
}
