import 'dart:async';

import 'dart:typed_data';
import 'book_identity.dart';
import 'book_source/http.dart';
import 'online_component.dart';

/// Bounded cover cache. Source previews use local seeds only.
abstract final class LegacyCover {
  static final _cache = LegacyCoverCache(request: (_) => unavailableOnline());
  static final _direct = _DirectCoverCache();
  static Uint8List? peek(int aid, {String? url}) =>
      isCustomSourceBook(aid) ? _direct.peek(aid) : _cache.peek(aid);
  static Future<Uint8List> bytes(int aid, {String? url}) {
    if (isCustomSourceBook(aid) && url != null && _httpCover(url)) {
      return _direct.load(aid, url);
    }
    return _cache.load(aid);
  }

  static bool _httpCover(String url) {
    final uri = Uri.tryParse(url);
    return uri != null &&
        (uri.scheme == 'http' || uri.scheme == 'https') &&
        uri.host.isNotEmpty;
  }

  /// Explicit local fixtures never query a remote cover endpoint.
  static void seedLocalBytes(int aid, Uint8List bytes) =>
      _cache.seed(aid, bytes);
}

class LegacyCoverCache {
  LegacyCoverCache({
    required this.request,
    this.maxBytes = 16 * 1024 * 1024,
    this.maxEntries = 256,
    this.retryDelay = const Duration(seconds: 30),
    DateTime Function()? now,
  }) : now = now ?? DateTime.now,
       assert(maxBytes > 0 && maxEntries > 0);
  final Future<Uint8List?> Function(int) request;
  final int maxBytes, maxEntries;
  final Duration retryDelay;
  final DateTime Function() now;
  final _entries = <int, _CoverEntry>{};
  final _pending = <int, Future<Uint8List>>{};
  final _failures = <int, (DateTime, Future<Uint8List>)>{};
  int _encodedBytes = 0;
  int get encodedBytes => _encodedBytes;
  int get cachedEntries => _entries.length;
  int get pendingRequests => _pending.length;
  int get cachedFailures => _failures.length;

  _CoverEntry? _touch(int aid) {
    final entry = _entries.remove(aid);
    if (entry != null) _entries[aid] = entry;
    return entry;
  }

  Uint8List? peek(int aid) => _touch(aid)?.bytes;

  void seed(int aid, Uint8List bytes) {
    if (aid <= 0 || bytes.isEmpty) throw ArgumentError('Invalid local cover');
    final local = Uint8List.fromList(bytes).asUnmodifiableView();
    // A delayed older network response must not overwrite an explicit seed.
    _pending.remove(aid);
    _failures.remove(aid);
    _store(aid, _CoverEntry(local, Future.value(local)));
  }

  void _store(int aid, _CoverEntry entry) {
    final previous = _entries.remove(aid);
    if (previous != null) _encodedBytes -= previous.bytes.length;
    if (entry.bytes.length > maxBytes) return;
    _entries[aid] = entry;
    _encodedBytes += entry.bytes.length;
    while (_encodedBytes > maxBytes || _entries.length > maxEntries) {
      final removed = _entries.remove(_entries.keys.first)!;
      _encodedBytes -= removed.bytes.length;
    }
  }

  Future<Uint8List> load(int aid) {
    if (aid <= 0) return Future.error(ArgumentError('Invalid cover ID'));
    final entry = _touch(aid);
    if (entry != null) return entry.future;
    final failure = _failures[aid];
    if (failure != null && now().isBefore(failure.$1)) return failure.$2;
    _failures.remove(aid);
    final pending = _pending[aid];
    if (pending != null) return pending;
    final completer = Completer<Uint8List>();
    final future = completer.future;
    _pending[aid] = future;
    unawaited(() async {
      try {
        final image = await request(aid);
        if (image == null || image.isEmpty) throw const FormatException('封面为空');
        final bytes = image.asUnmodifiableView();
        if (identical(_pending[aid], future)) {
          _store(aid, _CoverEntry(bytes, future));
        }
        completer.complete(bytes);
      } catch (error, stack) {
        if (identical(_pending[aid], future)) {
          _failures[aid] = (now().add(retryDelay), future);
          // Failed IDs must not grow forever while browsing offline either.
          while (_failures.length > maxEntries) {
            _failures.remove(_failures.keys.first);
          }
        }
        completer.completeError(error, stack);
      } finally {
        if (identical(_pending[aid], future)) _pending.remove(aid);
      }
    }());
    return future;
  }
}

class _CoverEntry {
  const _CoverEntry(this.bytes, this.future);
  final Uint8List bytes;
  final Future<Uint8List> future;
}

/// Custom-source covers are ordinary http images, keyed by the stable book id.
class _DirectCoverCache {
  final _bytes = <int, Uint8List>{};
  final _pending = <int, Future<Uint8List>>{};

  Uint8List? peek(int id) => _bytes[id];

  Future<Uint8List> load(int id, String url) {
    final cached = _bytes[id];
    if (cached != null) return Future<Uint8List>.value(cached);
    return _pending[id] ??= () async {
      try {
        final bytes = await BookSourceHttp.shared.getBytes(url);
        if (bytes.isEmpty) throw const FormatException('封面为空');
        _bytes[id] = bytes;
        return bytes;
      } finally {
        _pending.remove(id);
      }
    }();
  }
}
