import 'dart:async';
import 'dart:convert';

import 'transport.dart';

class RpcException implements Exception {
  RpcException(this.code, this.message);
  final int code;
  final String message;
  @override
  String toString() => message;
}

class Notification {
  const Notification(this.method, this.params);
  final String method;
  final Map<String, dynamic> params;
}

/// JSON-RPC 2.0 client with automatic reconnection.
class RpcClient {
  RpcClient({
    TransportFactory? factory,
    this.retryDelay = const Duration(seconds: 2),
  }) : _factory = factory ?? connectDefault;

  final TransportFactory _factory;
  final Duration retryDelay;
  Transport? _transport;
  StreamSubscription<String>? _sub;
  int _nextId = 1;
  final _pending = <int, Completer<dynamic>>{};
  final _notifications = StreamController<Notification>.broadcast();
  final _connected = StreamController<bool>.broadcast();
  bool _isConnected = false;
  bool _stopped = false;
  Timer? _retry;

  bool get isConnected => _isConnected;
  Stream<Notification> get notifications => _notifications.stream;
  Stream<bool> get connection => _connected.stream;

  Future<void> start() async {
    _stopped = false;
    await _connect();
  }

  Future<void> _connect() async {
    if (_stopped || _isConnected) return;
    try {
      final t = await _factory();
      _transport = t;
      _sub = t.lines.listen(
        _onLine,
        onDone: _onClosed,
        onError: (_) => _onClosed(),
      );
      _setConnected(true);
    } catch (_) {
      _scheduleRetry();
    }
  }

  void _setConnected(bool v) {
    if (_isConnected == v) return;
    _isConnected = v;
    _connected.add(v);
  }

  void _scheduleRetry() {
    if (_stopped) return;
    _retry?.cancel();
    _retry = Timer(retryDelay, _connect);
  }

  void _onClosed() {
    _sub?.cancel();
    _transport = null;
    _setConnected(false);
    for (final c in _pending.values) {
      c.completeError(
        RpcException(-1, 'Connection to the StepAway service was lost'),
      );
    }
    _pending.clear();
    _scheduleRetry();
  }

  void _onLine(String line) {
    if (line.trim().isEmpty) return;
    final Object? msg;
    try {
      msg = jsonDecode(line);
    } catch (_) {
      return;
    }
    if (msg is! Map<String, dynamic>) return;
    final id = msg['id'];
    if (id is int && _pending.containsKey(id)) {
      final c = _pending.remove(id)!;
      final err = msg['error'];
      if (err is Map) {
        c.completeError(
          RpcException(
            (err['code'] as num?)?.toInt() ?? -1,
            '${err['message']}',
          ),
        );
      } else {
        c.complete(msg['result']);
      }
    } else if (msg['method'] is String) {
      final p = msg['params'];
      _notifications.add(
        Notification(
          msg['method'] as String,
          p is Map<String, dynamic> ? p : {},
        ),
      );
    }
  }

  Future<dynamic> call(String method, [Map<String, dynamic>? params]) {
    final t = _transport;
    if (t == null) {
      return Future.error(
        RpcException(-1, 'The StepAway service is not running'),
      );
    }
    final id = _nextId++;
    final c = Completer<dynamic>();
    _pending[id] = c;
    t.send(
      jsonEncode({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': ?params,
      }),
    );
    return c.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () {
        _pending.remove(id);
        throw RpcException(-1, 'The StepAway service did not answer');
      },
    );
  }

  Future<void> stop() async {
    _stopped = true;
    _retry?.cancel();
    await _sub?.cancel();
    await _transport?.close();
    _transport = null;
    _setConnected(false);
  }
}
