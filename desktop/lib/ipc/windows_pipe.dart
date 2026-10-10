import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'transport.dart';

/// Named-pipe client for Windows using kernel32 through dart:ffi.
///
/// The handle is synchronous, so reads must never block a write: we only call ReadFile when
/// PeekNamedPipe says bytes are waiting, and poll every 20 ms.
class WindowsPipeTransport implements Transport {
  WindowsPipeTransport._(this._handle, this._k) {
    _timer = Timer.periodic(const Duration(milliseconds: 20), (_) => _poll());
  }

  final int _handle;
  final _Kernel32 _k;
  late final Timer _timer;
  final _controller = StreamController<String>();
  final _buffer = BytesBuilder();
  bool _closed = false;

  static const _genericRead = 0x80000000;
  static const _genericWrite = 0x40000000;
  static const _openExisting = 3;

  static Future<WindowsPipeTransport> connect(String name) async {
    final k = _Kernel32();
    final path = name.toNativeUtf16();
    try {
      final h = k.createFile(
        path,
        _genericRead | _genericWrite,
        0,
        nullptr,
        _openExisting,
        0,
        0,
      );
      if (h == -1) {
        throw StateError(
          'cannot open $name (error ${k.getLastError()}); is stepawayd running?',
        );
      }
      return WindowsPipeTransport._(h, k);
    } finally {
      calloc.free(path);
    }
  }

  @override
  Stream<String> get lines => _controller.stream;

  void _poll() {
    if (_closed) return;
    final avail = calloc<Uint32>();
    final read = calloc<Uint32>();
    try {
      while (true) {
        if (_k.peekNamedPipe(_handle, nullptr, 0, nullptr, avail, nullptr) ==
            0) {
          _fail();
          return;
        }
        final n = avail.value;
        if (n == 0) return;
        final buf = calloc<Uint8>(n);
        try {
          if (_k.readFile(_handle, buf, n, read, nullptr) == 0) {
            _fail();
            return;
          }
          _buffer.add(buf.asTypedList(read.value));
        } finally {
          calloc.free(buf);
        }
        _emitLines();
      }
    } finally {
      calloc.free(avail);
      calloc.free(read);
    }
  }

  void _emitLines() {
    final bytes = _buffer.takeBytes();
    var start = 0;
    for (var i = 0; i < bytes.length; i++) {
      if (bytes[i] == 0x0A) {
        _controller.add(
          utf8.decode(bytes.sublist(start, i), allowMalformed: true),
        );
        start = i + 1;
      }
    }
    if (start < bytes.length) _buffer.add(bytes.sublist(start));
  }

  void _fail() {
    if (_closed) return;
    _closed = true;
    _timer.cancel();
    _k.closeHandle(_handle);
    _controller.close();
  }

  @override
  void send(String line) {
    if (_closed) return;
    final data = utf8.encode('$line\n');
    final buf = calloc<Uint8>(data.length);
    final written = calloc<Uint32>();
    try {
      buf.asTypedList(data.length).setAll(0, data);
      if (_k.writeFile(_handle, buf, data.length, written, nullptr) == 0) {
        _fail();
      }
    } finally {
      calloc.free(buf);
      calloc.free(written);
    }
  }

  @override
  Future<void> close() async => _fail();
}

class _Kernel32 {
  _Kernel32() : _lib = DynamicLibrary.open('kernel32.dll') {
    createFile = _lib
        .lookupFunction<
          IntPtr Function(
            Pointer<Utf16>,
            Uint32,
            Uint32,
            Pointer,
            Uint32,
            Uint32,
            IntPtr,
          ),
          int Function(Pointer<Utf16>, int, int, Pointer, int, int, int)
        >('CreateFileW');
    readFile = _lib
        .lookupFunction<
          Int32 Function(
            IntPtr,
            Pointer<Uint8>,
            Uint32,
            Pointer<Uint32>,
            Pointer,
          ),
          int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer)
        >('ReadFile');
    writeFile = _lib
        .lookupFunction<
          Int32 Function(
            IntPtr,
            Pointer<Uint8>,
            Uint32,
            Pointer<Uint32>,
            Pointer,
          ),
          int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer)
        >('WriteFile');
    peekNamedPipe = _lib
        .lookupFunction<
          Int32 Function(
            IntPtr,
            Pointer,
            Uint32,
            Pointer,
            Pointer<Uint32>,
            Pointer,
          ),
          int Function(int, Pointer, int, Pointer, Pointer<Uint32>, Pointer)
        >('PeekNamedPipe');
    closeHandle = _lib
        .lookupFunction<Int32 Function(IntPtr), int Function(int)>(
          'CloseHandle',
        );
    getLastError = _lib.lookupFunction<Uint32 Function(), int Function()>(
      'GetLastError',
    );
  }

  final DynamicLibrary _lib;
  late final int Function(Pointer<Utf16>, int, int, Pointer, int, int, int)
  createFile;
  late final int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer)
  readFile;
  late final int Function(int, Pointer<Uint8>, int, Pointer<Uint32>, Pointer)
  writeFile;
  late final int Function(int, Pointer, int, Pointer, Pointer<Uint32>, Pointer)
  peekNamedPipe;
  late final int Function(int) closeHandle;
  late final int Function() getLastError;
}
