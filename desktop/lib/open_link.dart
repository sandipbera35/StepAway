import 'dart:io';

/// Opens [url] in the default browser. Returns false when this platform has no way to do it,
/// so the caller can copy the link instead.
Future<bool> openLink(String url) async {
  try {
    final ProcessResult r;
    if (Platform.isLinux) {
      r = await Process.run('xdg-open', [url]);
    } else if (Platform.isWindows) {
      r = await Process.run('rundll32', ['url.dll,FileProtocolHandler', url]);
    } else {
      return false;
    }
    return r.exitCode == 0;
  } on ProcessException {
    return false;
  }
}
