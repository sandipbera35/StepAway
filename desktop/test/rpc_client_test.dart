import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:stepaway_desktop/ipc/rpc_client.dart';
import 'package:stepaway_desktop/ipc/transport.dart';

class FakeTransport implements Transport {
  final _in = StreamController<String>();
  final sent = <Map<String, dynamic>>[];
  @override
  Stream<String> get lines => _in.stream;
  @override
  void send(String line) => sent.add(jsonDecode(line) as Map<String, dynamic>);
  @override
  Future<void> close() async => _in.close();
  void feed(Map<String, dynamic> m) => _in.add(jsonEncode(m));
  void drop() => _in.close();
}

void main() {
  test('correlates responses and errors by id', () async {
    final t = FakeTransport();
    final c = RpcClient(factory: () async => t);
    await c.start();
    final ok = c.call('status');
    final bad = expectLater(
      c.call('nope'),
      throwsA(isA<RpcException>().having((e) => e.code, 'code', -32601)),
    );
    expect(t.sent.map((m) => m['method']), ['status', 'nope']);
    t.feed({
      'jsonrpc': '2.0',
      'id': t.sent[1]['id'],
      'error': {'code': -32601, 'message': 'unknown method'},
    });
    t.feed({
      'jsonrpc': '2.0',
      'id': t.sent[0]['id'],
      'result': {'state': 'NEAR'},
    });
    expect((await ok)['state'], 'NEAR');
    await bad;
    await c.stop();
  });

  test('delivers notifications and ignores garbage', () async {
    final t = FakeTransport();
    final c = RpcClient(factory: () async => t);
    await c.start();
    final got = c.notifications.first;
    t._in.add('not json');
    t.feed({
      'jsonrpc': '2.0',
      'method': 'stateChanged',
      'params': {'to': 'LOCKED'},
    });
    final n = await got;
    expect(n.method, 'stateChanged');
    expect(n.params['to'], 'LOCKED');
    await c.stop();
  });

  test('fails calls when the connection drops, then reconnects', () async {
    final first = FakeTransport();
    final second = FakeTransport();
    final queue = [first, second];
    final c = RpcClient(
      factory: () async => queue.removeAt(0),
      retryDelay: const Duration(milliseconds: 20),
    );
    await c.start();
    final pending = c.call('status');
    first.drop();
    await expectLater(pending, throwsA(isA<RpcException>()));
    expect(c.isConnected, isFalse);
    await c.connection.firstWhere((v) => v);
    expect(c.isConnected, isTrue);
    await c.stop();
  });

  test('call without a connection fails cleanly', () async {
    final c = RpcClient(
      factory: () async => throw StateError('down'),
      retryDelay: const Duration(hours: 1),
    );
    await c.start();
    await expectLater(c.call('status'), throwsA(isA<RpcException>()));
    await c.stop();
  });
}
