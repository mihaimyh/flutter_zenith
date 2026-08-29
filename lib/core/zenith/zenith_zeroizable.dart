/// Interface for objects that hold sensitive memory buffers (cryptographic
/// keys, tokens, PII) and must overwrite them with zeros on disposal.
///
/// Implement this on any class managed by a [ZenithContainer] that should
/// be cryptographically cleared when container disposal occurs with
/// `purgeZeroize: true`.
abstract interface class Zeroizable {
  /// Overwrites the sensitive data with zero bytes.
  ///
  /// After [zeroize] returns, [isZeroized] must be `true`.
  void zeroize();

  /// Whether this object has already been zeroized.
  bool get isZeroized;
}
