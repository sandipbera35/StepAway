import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'windows_pipe.dart';

/// A line-oriented duplex connection to the daemon.
abstract class Transport {
  /// Complete lines received from the daemon (without the trailing newline).
  Stream<String> get lines;
  void send(String line);
  Future<void> close();
}

typedef TransportFactory = Future<Transport> Function();

/// Where the daemon listens (docs: protocol/SPEC.md §4).
String defaultEndpoint() {
  final home = Platform.environment['STEPAWAY_HOME'];
  if (Platform.isWindows) {
    return r'\\.\pipe\stepaway-' + (Platform.environment['USERNAME'] ?? '');
  }
  if (home != null && home.isNotEmpty) return '$home/stepaway.sock';
  final runtime =
      Platform.environment['XDG_RUNTIME_DIR'] ?? Directory.systemTemp.path;
  return '$runtime/stepaway.sock';
}

Future<Transport> connectDefault() async {
  final endpoint = defaultEndpoint();
  if (Platform.isWindows) return WindowsPipeTransport.connect(endpoint);
  return UnixTransport.connect(endpoint);
}

class UnixTransport implements Transport {
  UnixTransport._(this._socket) {
    _socket
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          _controller.add,
          onDone: _controller.close,
          onError: (_) => _controller.close(),
        );
  }

  final Socket _socket;
  final _controller = StreamController<String>();

  static Future<UnixTransport> connect(String path) async {
    final s = await Socket.connect(
      InternetAddress(path, type: InternetAddressType.unix),
      0,
    );
    return UnixTransport._(s);
  }

  @override
  Stream<String> get lines => _controller.stream;

  @override
  void send(String line) => _socket.write('$line\n');

  @override
  Future<void> close() async {
    await _socket.close();
  }
}
