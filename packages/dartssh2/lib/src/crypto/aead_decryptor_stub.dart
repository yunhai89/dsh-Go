import 'dart:typed_data';

import 'aead_decryptor_base.dart';
import 'aead_decryptor_impl.dart';

/// Web (and any non-isolate platform) fallback: the packet is decrypted in
/// the caller's isolate, exactly as before. The VM build uses
/// `aead_decryptor_io.dart`.
class _InlineAeadDecryptor implements AeadDecryptor {
  @override
  Future<Uint8List> decryptGcm({
    required Uint8List key,
    required Uint8List iv,
    required int sequence,
    required Uint8List aad,
    required Uint8List input,
  }) async =>
      decryptAead(
        kind: aeadKindGcm,
        key: key,
        iv: iv,
        sequence: sequence,
        aad: aad,
        input: input,
      );

  @override
  Future<Uint8List> decryptChaCha({
    required Uint8List key,
    required int sequence,
    required Uint8List input,
  }) async =>
      decryptAead(
        kind: aeadKindChaCha,
        key: key,
        sequence: sequence,
        input: input,
      );

  @override
  Future<void> close() async {}
}

Future<AeadDecryptor> spawnAeadDecryptor() async => _InlineAeadDecryptor();
