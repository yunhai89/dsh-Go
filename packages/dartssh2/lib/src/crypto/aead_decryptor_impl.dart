import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../utils/int.dart';
import '../utils/openssh_chacha20_poly1305.dart';

/// Wire kinds for the background AEAD worker.
const aeadKindGcm = 0;
const aeadKindChaCha = 1;

/// Decrypts one AEAD packet. Runs inside the crypto isolate (or inline on
/// platforms without isolates).
Uint8List decryptAead({
  required int kind,
  required Uint8List key,
  Uint8List? iv,
  required int sequence,
  Uint8List? aad,
  required Uint8List input,
}) {
  if (kind == aeadKindGcm) {
    final nonce = _nonceForSequence(iv!, sequence);
    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(key), 128, nonce, aad!));
    return cipher.process(input);
  }
  if (kind == aeadKindChaCha) {
    return OpenSSHChaCha20Poly1305(key).decryptPacket(input, sequence);
  }
  throw ArgumentError.value(kind, 'kind', 'unknown AEAD kind');
}

Uint8List _nonceForSequence(Uint8List iv, int sequence) {
  if (iv.length != 12) {
    throw ArgumentError.value(
      iv.length,
      'iv.length',
      'AEAD IV must be 12 bytes long',
    );
  }
  final nonce = Uint8List.fromList(iv);
  ByteData.sublistView(nonce).addToUint64Split(4, sequence);
  return nonce;
}
