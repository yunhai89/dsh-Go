import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:pointycastle/export.dart' show InvalidCipherTextException;

import 'aead_decryptor_base.dart';
import 'aead_decryptor_impl.dart';

/// VM implementation: one long-lived isolate decrypts SSH packets.
///
/// The isolate is created per transport, on the first AEAD packet. Requests are
/// small typed-data messages; packet order is preserved by the transport
/// awaiting each response.
Future<AeadDecryptor> spawnAeadDecryptor() => _IsolateAeadDecryptor.start();

class _IsolateAeadDecryptor implements AeadDecryptor {
  _IsolateAeadDecryptor._(
    this._isolate,
    this._receive,
    this._subscription,
    this._send,
  );

  final Isolate _isolate;
  final ReceivePort _receive;
  final StreamSubscription<Object?> _subscription;
  final SendPort _send;

  final _pending = <int, Completer<Uint8List>>{};
  int _next = 0;
  bool _closed = false;
  Object? _failure;

  static Future<_IsolateAeadDecryptor> start() async {
    final receive = ReceivePort();
    final ready = Completer<SendPort>();
    _IsolateAeadDecryptor? worker;
    late final StreamSubscription<Object?> subscription;

    void failPending(Object error) {
      final instance = worker;
      if (instance == null) return;
      instance._failure ??= error;
      for (final request in instance._pending.values) {
        if (!request.isCompleted) request.completeError(error);
      }
      instance._pending.clear();
    }

    subscription = receive.listen(
      (message) {
        if (message is SendPort) {
          if (!ready.isCompleted) ready.complete(message);
          return;
        }
        if (message == null) {
          // The isolate exited. Nothing can answer the outstanding requests.
          if (!ready.isCompleted) {
            ready.completeError(
              StateError('SSH AEAD worker exited during startup'),
            );
          }
          failPending(StateError('SSH AEAD worker exited'));
          return;
        }
        if (message is! List || message.isEmpty || message[0] is! int) return;
        final request = worker?._pending.remove(message[0]);
        if (request == null || request.isCompleted) return;
        final data = message.length > 1 ? message[1] : null;
        if (data is Uint8List) {
          request.complete(data);
          return;
        }
        final problem = message.length > 2 ? message[2] : null;
        if (problem == 'auth') {
          request.completeError(const AeadDecryptorException.authentication());
        } else {
          final detail = message.length > 3 ? message[3] : null;
          request.completeError(
            AeadDecryptorException.internal(
              detail is String ? detail : 'AEAD worker failed',
            ),
          );
        }
      },
      // An isolate exit arrives on the same port as null; keep the listener
      // alive until close so outstanding requests settle once.
      cancelOnError: false,
    );

    final Isolate isolate;
    try {
      isolate = await Isolate.spawn(
        _aeadWorkerMain,
        receive.sendPort,
        debugName: 'dsh-ssh-aead',
        onExit: receive.sendPort,
      );
    } catch (error) {
      await subscription.cancel();
      receive.close();
      rethrow;
    }

    final SendPort send;
    try {
      send = await ready.future.timeout(const Duration(seconds: 10));
    } catch (error) {
      isolate.kill(priority: Isolate.immediate);
      await subscription.cancel();
      receive.close();
      rethrow;
    }

    return worker = _IsolateAeadDecryptor._(
      isolate,
      receive,
      subscription,
      send,
    );
  }

  @override
  Future<Uint8List> decryptGcm({
    required Uint8List key,
    required Uint8List iv,
    required int sequence,
    required Uint8List aad,
    required Uint8List input,
  }) =>
      _request([aeadKindGcm, key, iv, sequence, aad, input]);

  @override
  Future<Uint8List> decryptChaCha({
    required Uint8List key,
    required int sequence,
    required Uint8List input,
  }) =>
      _request([aeadKindChaCha, key, null, sequence, null, input]);

  Future<Uint8List> _request(List<Object?> body) {
    final failure = _failure;
    if (_closed) return Future.error(StateError('SSH AEAD worker is closed'));
    if (failure != null) return Future.error(failure);
    final id = ++_next;
    final request = Completer<Uint8List>();
    _pending[id] = request;
    _send.send([id, ...body]);
    return request.future;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _send.send(const ['close']);
    isolateKill();
    await _subscription.cancel();
    _receive.close();
    for (final request in _pending.values) {
      if (!request.isCompleted) {
        request.completeError(StateError('SSH AEAD worker closed'));
      }
    }
    _pending.clear();
  }

  void isolateKill() => _isolate.kill(priority: Isolate.immediate);
}

void _aeadWorkerMain(SendPort main) {
  final inbox = ReceivePort();
  main.send(inbox.sendPort);
  inbox.listen((message) {
    if (message is! List || message.isEmpty) return;
    if (message[0] == 'close') {
      inbox.close();
      return;
    }
    final id = message[0];
    if (id is! int) return;
    try {
      final data = decryptAead(
        kind: message[1] as int,
        key: message[2] as Uint8List,
        iv: message[3] as Uint8List?,
        sequence: message[4] as int,
        aad: message[5] as Uint8List?,
        input: message[6] as Uint8List,
      );
      main.send([id, data]);
    } on InvalidCipherTextException {
      main.send([id, null, 'auth']);
    } catch (error) {
      main.send([id, null, 'internal', '$error']);
    }
  });
}
