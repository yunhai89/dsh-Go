import 'dart:typed_data';

/// One AEAD packet failed. [authenticationFailed] is a forged or damaged tag
/// (the peer's packet is invalid); other failures are local worker faults.
class AeadDecryptorException implements Exception {
  const AeadDecryptorException.authentication()
      : authenticationFailed = true,
        message = 'authentication failed';

  const AeadDecryptorException.internal(this.message)
      : authenticationFailed = false;

  final bool authenticationFailed;
  final String message;

  @override
  String toString() => 'AeadDecryptorException($message)';
}

/// Off-main packet encryption and decryption for SSH AEAD ciphers.
///
/// AES-GCM and OpenSSH ChaCha20-Poly1305 are pure-Dart pointycastle work. On a
/// phone, a few megabytes of SSH traffic would otherwise run that work on the
/// UI isolate and can starve input for seconds. The VM implementation lives in
/// [aead_decryptor_io.dart]; the web fallback processes packets inline.
abstract interface class AeadDecryptor {
  Future<Uint8List> encryptGcm({
    required Uint8List key,
    required Uint8List iv,
    required int sequence,
    required Uint8List aad,
    required Uint8List input,
  });

  Future<Uint8List> encryptChaCha({
    required Uint8List key,
    required int sequence,
    required Uint8List input,
  });

  Future<Uint8List> decryptGcm({
    required Uint8List key,
    required Uint8List iv,
    required int sequence,
    required Uint8List aad,
    required Uint8List input,
  });

  Future<Uint8List> decryptChaCha({
    required Uint8List key,
    required int sequence,
    required Uint8List input,
  });

  Future<void> close();
}
