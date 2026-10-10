import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:stepaway_ui/stepaway_ui.dart';

class MemStore implements ThemeStore {
  ThemeMode? saved;
  @override
  Future<ThemeMode?> load() async => saved;
  @override
  Future<void> save(ThemeMode mode) async => saved = mode;
}

Widget app(Widget child, {ThemeMode mode = ThemeMode.light}) => MaterialApp(
  theme: StepAwayTheme.light(),
  darkTheme: StepAwayTheme.dark(),
  themeMode: mode,
  builder: (c, w) => GlassBackground(child: w!),
  home: Scaffold(body: Center(child: child)),
);

void main() {
  test('screen sizes switch at 720 and 1000 logical pixels', () {
    expect(screenSizeFor(360), ScreenSize.compact);
    expect(screenSizeFor(719.9), ScreenSize.compact);
    expect(screenSizeFor(720), ScreenSize.medium);
    expect(screenSizeFor(999), ScreenSize.medium);
    expect(screenSizeFor(1000), ScreenSize.expanded);
  });

  testWidgets(
    'ResponsiveBuilder reports the space it is given, not the screen',
    (t) async {
      ScreenSize? seen;
      await t.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 500,
              child: ResponsiveBuilder(
                builder: (c, size, box) {
                  seen = size;
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      expect(seen, ScreenSize.compact);
    },
  );

  testWidgets('NoScrollbarBehavior scrolls without drawing a scrollbar', (
    t,
  ) async {
    await t.pumpWidget(
      MaterialApp(
        scrollBehavior: const NoScrollbarBehavior(),
        home: Scaffold(
          body: ListView(
            children: [
              for (var i = 0; i < 60; i++)
                SizedBox(height: 60, child: Text('row $i')),
            ],
          ),
        ),
      ),
    );
    expect(find.byType(Scrollbar), findsNothing);
    await t.drag(
      find.byType(ListView),
      const Offset(0, -300),
      kind: PointerDeviceKind.mouse,
    );
    await t.pump();
    expect(
      find.text('row 0'),
      findsNothing,
      reason: 'dragging with a mouse still scrolls',
    );
  });

  motionTests();
  test('theme controller remembers the choice and restores it', () async {
    final store = MemStore();
    final a = ThemeController(store: store);
    expect(a.mode, ThemeMode.system);
    await a.setMode(ThemeMode.dark);
    expect(store.saved, ThemeMode.dark);
    final b = ThemeController(store: store);
    await b.init();
    expect(b.mode, ThemeMode.dark);
  });

  test('theme mode encoding round-trips and rejects garbage', () {
    for (final m in ThemeMode.values) {
      expect(ThemeController.decode(ThemeController.encode(m)), m);
    }
    expect(ThemeController.decode('purple'), isNull);
    expect(ThemeController.decode(null), isNull);
  });

  testWidgets(
    'glass card, button and segmented control render in both themes',
    (t) async {
      ThemeMode picked = ThemeMode.system;
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        await t.pumpWidget(
          app(
            StatefulBuilder(
              builder: (c, set) => Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const GlassCard(child: Text('hello')),
                  GradientButton(label: 'Go', onPressed: () {}),
                  GlassSegmented<ThemeMode>(
                    value: picked,
                    options: const [
                      GlassSegment(
                        ThemeMode.system,
                        'System',
                        Icons.brightness_auto,
                      ),
                      GlassSegment(ThemeMode.light, 'Light', Icons.light_mode),
                      GlassSegment(ThemeMode.dark, 'Dark', Icons.dark_mode),
                    ],
                    onChanged: (m) => set(() => picked = m),
                  ),
                  const StepAwayLogo(),
                  const StatusOrb(color: Colors.green, icon: Icons.check),
                ],
              ),
            ),
            mode: mode,
          ),
        );
        expect(find.text('hello'), findsOneWidget);
        await t.tap(find.byKey(const Key('segment-Dark')));
        await t.pump();
        expect(picked, ThemeMode.dark);
        picked = ThemeMode.system;
      }
    },
  );

  testWidgets('disabled gradient button ignores taps', (t) async {
    var taps = 0;
    await t.pumpWidget(
      app(
        Column(
          children: [
            GradientButton(label: 'On', onPressed: () => taps++),
            const GradientButton(label: 'Off'),
          ],
        ),
      ),
    );
    await t.tap(find.text('On'));
    await t.tap(find.text('Off'));
    expect(taps, 1);
  });
}

void motionTests() {
  testWidgets('Reveal fades its child in and settles', (t) async {
    await t.pumpWidget(app(const Reveal(index: 3, child: Text('card'))));
    FadeTransition fade() => t.widget<FadeTransition>(
      find
          .descendant(
            of: find.byType(Reveal),
            matching: find.byType(FadeTransition),
          )
          .first,
    );
    expect(fade().opacity.value, 0);
    await t.pumpAndSettle();
    expect(fade().opacity.value, 1);
    expect(find.text('card'), findsOneWidget);
  });

  testWidgets('AnimatedNumber counts to the new value', (t) async {
    double shown = 0;
    Widget w(double v) => app(
      AnimatedNumber(
        value: v,
        builder: (c, x) {
          shown = x;
          return Text(x.toStringAsFixed(1));
        },
      ),
    );
    await t.pumpWidget(w(1));
    await t.pumpAndSettle();
    await t.pumpWidget(w(5));
    await t.pump(const Duration(milliseconds: 100));
    expect(shown, greaterThan(1));
    expect(shown, lessThan(5));
    await t.pumpAndSettle();
    expect(shown, 5);
  });

  testWidgets('FadeSlideSwitcher swaps pages', (t) async {
    Widget w(int i) =>
        app(FadeSlideSwitcher(pageKey: i, child: Text('page $i')));
    await t.pumpWidget(w(0));
    await t.pumpWidget(w(1));
    await t.pumpAndSettle();
    expect(find.text('page 1'), findsOneWidget);
    expect(find.text('page 0'), findsNothing);
  });

  testWidgets('Ripples only animate while active', (t) async {
    await t.pumpWidget(
      app(
        const Ripples(
          color: Colors.green,
          active: false,
          child: Icon(Icons.check),
        ),
      ),
    );
    await t.pumpAndSettle(); // would time out if an animation were running
    await t.pumpWidget(
      app(
        const Ripples(
          color: Colors.green,
          active: true,
          child: Icon(Icons.check),
        ),
      ),
    );
    await t.pump(const Duration(milliseconds: 500));
    expect(t.hasRunningAnimations, isTrue);
    await t.pumpWidget(app(const SizedBox()));
  });

  testWidgets('PopIn and Pressable render and respond', (t) async {
    var taps = 0;
    await t.pumpWidget(
      app(
        Pressable(
          onTap: () => taps++,
          child: const PopIn(child: Text('ok')),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.tap(find.text('ok'));
    expect(taps, 1);
  });
}
