// lib/core/logging/logger_service.dart
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart' as logger_pkg;

enum LogLevel { debug, info, warn, error }

class LoggerService {
  final String _className;
  late final logger_pkg.Logger _logger;
  LogLevel currentLogLevel = kDebugMode ? LogLevel.debug : LogLevel.info;

  LoggerService(this._className) {
    _logger = logger_pkg.Logger(
      printer: logger_pkg.PrettyPrinter(
        methodCount: 1,
        errorMethodCount: 5,
        lineLength: 100,
        colors: true,
        printEmojis: true,
        printTime: true,
      ),
      // Set minimum log level for different environments
      level: kDebugMode ? logger_pkg.Level.debug : logger_pkg.Level.info,
    );
  }

  bool get isDebugEnabled => currentLogLevel.index <= LogLevel.debug.index;
  bool get isInfoEnabled => currentLogLevel.index <= LogLevel.info.index;
  bool get isWarnEnabled => currentLogLevel.index <= LogLevel.warn.index;
  bool get isErrorEnabled => currentLogLevel.index <= LogLevel.error.index;

  void _log(LogLevel level, String tag, String message,
      [dynamic error, StackTrace? stackTrace]) {
    if (level.index >= currentLogLevel.index) {
      final timestamp = DateTime.now().toIso8601String();
      String logMessage =
          '$timestamp [${level.toString().split('.').last.toUpperCase()}] [$_className] $tag: $message';
      
      switch (level) {
        case LogLevel.debug:
          _logger.d("$_className: $tag - $message", error: error, stackTrace: stackTrace);
          break;
        case LogLevel.info:
          _logger.i("$_className: $tag - $message", error: error, stackTrace: stackTrace);
          break;
        case LogLevel.warn:
          _logger.w("$_className: $tag - $message", error: error, stackTrace: stackTrace);
          break;
        case LogLevel.error:
          _logger.e("$_className: $tag - $message", error: error, stackTrace: stackTrace);
          break;
      }
    }
  }

  // Legacy methods for compatibility with old usage
  void debug(String tag, String message) {
    _log(LogLevel.debug, tag, message);
  }

  void info(String tag, String message) {
    _log(LogLevel.info, tag, message);
  }

  void warn(String tag, String message, {dynamic error, StackTrace? stackTrace}) {
    _log(LogLevel.warn, tag, message, error, stackTrace);
  }

  void error(String tag, String message, [dynamic error, StackTrace? stackTrace]) {
    _log(LogLevel.error, tag, message, error, stackTrace);
  }

  // New methods matching the logger_service1.dart syntax for compatibility
  void d(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.d("$_className: $message", error: error, stackTrace: stackTrace);
  }

  void i(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.i("$_className: $message", error: error, stackTrace: stackTrace);
  }

  void w(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.w("$_className: $message", error: error, stackTrace: stackTrace);
  }

  void e(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.e("$_className: $message", error: error, stackTrace: stackTrace);
  }

  void v(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.v("$_className: $message", error: error, stackTrace: stackTrace);
  }

  void wtf(dynamic message, [dynamic error, StackTrace? stackTrace]) {
    _logger.f("$_className: $message", error: error, stackTrace: stackTrace);
  }
}