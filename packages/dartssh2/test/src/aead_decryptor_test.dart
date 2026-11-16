import 'dart:typed_data';

import 'package:dartssh2/src/crypto/aead_decryptor.dart';
import 'package:dartssh2/src/utils/int.dart';
import 'package:dartssh2/src/utils/openssh_chacha20_poly1305.dart';
import 'package:pointycastle/export.dart';
import 'package:test/test.dart';

Uint8List _bytes(int length, int seed) =>
    Uint8List.fromList([for (var i = 0; i < length; i++) (seed + i) & 0xff]);

Uint8List _gcmEncrypt({
  required Uint8List key,
  required Uint8List iv,
  required int sequence,
  required Uint8List aad,
  required Uint8List plaintext,
}) {
  final nonce = Uint8List.fromList(iv);
  ByteData.sublistView(nonce).addToUint64Split(4, sequence);
  final cipher = GCMBlockCipher(AESEngine())
    ..init(true, AEADParameters(KeyParameter(key), 128, nonce, aad));
  return cipher.process(plaintext);
}

void main() {
  test('background GCM decrypts a packet and rejects a bad tag', () async {
    final key = _bytes(32, 1);
    final iv = _bytes(12, 2);
    final aad = _bytes(4, 3);
    final plaintext = _bytes(2048, 4);
    final encrypted = _gcmEncrypt(
        key: key, iv: iv, sequence: 7, aad: aad, plaintext: plaintext);

    final worker = await spawnAeadDecryptor();
    addTearDown(worker.close);
    final decoded = await worker.decryptGcm(
        key: key, iv: iv, sequence: 7, aad: aad, input: encrypted);
    expect(decoded, orderedEquals(plaintext));

    final damaged = Uint8List.fromList(encrypted)..[encrypted.length - 1] ^= 1;
    await expectLater(
      worker.decryptGcm(
          key: key, iv: iv, sequence: 7, aad: aad, input: damaged),
      throwsA(isA<AeadDecryptorException>().having(
          (e) => e.authenticationFailed, 'authenticationFailed', isTrue)),
    );
  });

  test('background ChaCha20-Poly1305 decrypts a packet', () async {
    final key = _bytes(64, 9);
    final sequence = 3;
    // packet_length, padding_length, payload, padding: aligned to 8 bytes.
    final packet = Uint8List.fromList([0, 0, 0, 9, 3, 1, 2, 3, 4, 5, 6, 7, 8]);
    final encrypted =
        OpenSSHChaCha20Poly1305(key).encryptPacket(packet, sequence);

    final worker = await spawnAeadDecryptor();
    addTearDown(worker.close);
    final decoded = await worker.decryptChaCha(
        key: key, sequence: sequence, input: encrypted);
    expect(decoded, orderedEquals(packet));
  });

  test('closing the worker settles outstanding requests', () async {
    final worker = await spawnAeadDecryptor();
    await worker.close();
    await expectLater(
      worker.decryptGcm(
        key: _bytes(32, 1),
        iv: _bytes(12, 2),
        sequence: 0,
        aad: Uint8List(4),
        input: _bytes(32, 3),
      ),
      throwsA(isA<StateError>()),
    );
  });
}
