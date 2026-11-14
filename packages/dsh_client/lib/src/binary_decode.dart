/// Decoding large wire payloads away from the caller's isolate.
///
/// A file read is delivered in 1 MiB windows. On a phone, base64-decoding one
/// window or scanning a multipart body can occupy the UI isolate long enough to
/// drop a frame; the same work in a short-lived isolate leaves the frame alone.
/// Small payloads stay inline: a spawn costs more than it saves there.
library;

import 'dart:isolate';

/// Payloads at or above this size are decoded on a worker isolate.
const int isolateDecodeThreshold = 256 * 1024;

/// Runs [decode] inline for small payloads and on a worker isolate otherwise.
/// The result must be sendable between isolates (bytes, maps, lists, records).
Future<T> decodeOffThread<T>(int payloadBytes, T Function() decode) {
  if (payloadBytes < isolateDecodeThreshold) return Future<T>.sync(decode);
  return Isolate.run(decode, debugName: 'dsh-decode');
}
