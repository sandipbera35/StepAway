import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:stepaway_ui/stepaway_ui.dart';

import 'controller.dart';
import 'native.dart';
import 'strings.dart';

/// Preview the computer, ask the user to compare the code, save, then celebrate.
Future<void> runPairingFlow(
  BuildContext context,
  AppController app,
  String uri,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final preview = await _preview(app, uri);
  if (preview == null) {
    messenger.showSnackBar(const SnackBar(content: Text(S.invalidLink)));
    return;
  }
  if (!context.mounted) return;
  HapticFeedback.selectionClick();
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: const Text(S.confirmTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.computer_rounded),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  preview.name.isEmpty ? 'Computer' : preview.name,
                  style: Theme.of(c).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Center(
            child: Reveal(
              child: Text(
                preview.code,
                key: const Key('verification-code'),
                style: Theme.of(c).textTheme.displaySmall
                    ?.copyWith(letterSpacing: 8),
              ),
            ),
          ),
          const SizedBox(height: 16),
          const Text(S.confirmBody),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: const Text(S.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(c, true),
          child: const Text(S.pair),
        ),
      ],
    ),
  );
  if (ok != true) return;
  await app.savePairing(uri);
  HapticFeedback.mediumImpact();
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (_) => const _PairedDialog(),
  );
}

Future<PairingPreview?> _preview(AppController app, String uri) async {
  try {
    return await app.native.previewPairing(uri);
  } catch (_) {
    return null;
  }
}

class _PairedDialog extends StatefulWidget {
  const _PairedDialog();

  @override
  State<_PairedDialog> createState() => _PairedDialogState();
}

class _PairedDialogState extends State<_PairedDialog> {
  @override
  Widget build(BuildContext context) {
    final c = AppColors.of(context);
    return AlertDialog(
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          PopIn(
            child: StatusOrb(
              color: c.success,
              icon: Icons.check_rounded,
              size: 96,
            ),
          ),
          const SizedBox(height: 22),
          Text(S.pairedTitle, style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 8),
          const Text(S.pairedBody, textAlign: TextAlign.center),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text(S.done),
        ),
      ],
    );
  }
}
