import 'dart:typed_data';

import 'package:flutter_zenith/core/zenith/zenith_zeroizable.dart';

export 'package:flutter_zenith/core/zenith/zenith_zeroizable.dart'
    show Zeroizable;

/// A secure byte buffer that wraps a [Uint8List] and implements [Zeroizable].
///
/// When [zeroize] is called (e.g. on scope disposal with `purgeZeroize: true`),
/// all bytes in the underlying buffer are overwritten with `0x00`. After
/// zeroization, [bytes] returns a zero-filled view and [isZeroized] is `true`.
///
/// ```dart
/// final token = ZenithSecureBytes(Uint8List.fromList([0xDE, 0xAD, 0xBE, 0xEF]));
/// userScope.container.getOrCreate(ZenithKey('token'), (_) => token);
///
/// manager.endScope('user_secure', purgeZeroize: true);
///
/// assert(token.isZeroized);                          // true
/// assert(token.bytes.every((b) => b == 0));          // true
/// ```
class ZenithSecureBytes implements Zeroizable {
  final Uint8List _buffer;
  bool _isZeroized = false;

  /// Creates a [ZenithSecureBytes] wrapping [rawBytes].
  ///
  /// The [rawBytes] list is used **directly** (not copied) so that
  /// [zeroize] overwrites the original allocation.
  ZenithSecureBytes(Uint8List rawBytes) : _buffer = rawBytes;

  /// The raw byte buffer.
  ///
  /// After [zeroize], all bytes will be `0x00`.
  Uint8List get bytes => _buffer;

  @override
  bool get isZeroized => _isZeroized;

  @override
  void zeroize() {
    if (_isZeroized) return;
    _buffer.fillRange(0, _buffer.length, 0x00);
    _isZeroized = true;
  }
}
