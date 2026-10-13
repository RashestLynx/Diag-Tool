import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gamepads/gamepads.dart';

import 'stick_analysis.dart';
import 'stick_pad.dart';

class ControllerScreen extends StatefulWidget {
  const ControllerScreen({super.key});

  @override
  State<ControllerScreen> createState() => _ControllerScreenState();
}

class _ControllerScreenState extends State<ControllerScreen> {
  final _state = NormalizedGamepadState();
  StreamSubscription<NormalizedGamepadEvent>? _events;
  StreamSubscription<GamepadConnectionEvent>? _connections;

  List<GamepadController> _pads = [];
  String? _selectedId;
  bool _loading = true;

  // Drift test
  Timer? _testTimer;
  StickDriftRecorder? _leftRec;
  StickDriftRecorder? _rightRec;
  int _testTicksLeft = 0;
  StickDriftResult? _leftResult;
  StickDriftResult? _rightResult;

  bool get _supported =>
      !kIsWeb &&
      (Platform.isAndroid || Platform.isIOS || Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  @override
  void initState() {
    super.initState();
    if (_supported) _init();
  }

  Future<void> _init() async {
    try {
      _events = Gamepads.normalizedEvents.listen((e) {
        if (e.gamepadId != _selectedId) return;
        _state.update(e);
        if (mounted) setState(() {});
      });
      _connections = Gamepads.connectionEvents.listen((_) => _refresh());
    } catch (_) {
      // Stream not available on this platform/build.
    }
    await _refresh();
  }

  Future<void> _refresh() async {
    List<GamepadController> pads = [];
    try {
      pads = await Gamepads.list();
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      // Dispose controllers we no longer show (they each hold a subscription).
      for (final p in _pads) {
        if (!pads.any((q) => q.id == p.id)) p.dispose();
      }
      _pads = pads;
      if (_selectedId == null || !pads.any((p) => p.id == _selectedId)) {
        _selectedId = pads.isEmpty ? null : pads.first.id;
        _resetTest();
      }
      _loading = false;
    });
  }

  ControllerBrand get _brand {
    final pad = _selectedPad;
    if (pad == null) return ControllerBrand.generic;
    return classifyController(vendorId: pad.vendorId, name: pad.name);
  }

  GamepadController? get _selectedPad {
    for (final p in _pads) {
      if (p.id == _selectedId) return p;
    }
    return null;
  }

  void _resetTest() {
    _testTimer?.cancel();
    _testTimer = null;
    _leftRec = _rightRec = null;
    _leftResult = _rightResult = null;
    _testTicksLeft = 0;
  }

  void _startDriftTest() {
    _leftRec = StickDriftRecorder();
    _rightRec = StickDriftRecorder();
    _leftResult = _rightResult = null;
    _testTicksLeft = 50; // ~3s at 60ms per tick
    _testTimer?.cancel();
    _testTimer = Timer.periodic(const Duration(milliseconds: 60), (t) {
      _leftRec!.add(
          _state.axisValue(GamepadAxis.leftStickX), _state.axisValue(GamepadAxis.leftStickY));
      _rightRec!.add(
          _state.axisValue(GamepadAxis.rightStickX), _state.axisValue(GamepadAxis.rightStickY));
      _testTicksLeft--;
      if (_testTicksLeft <= 0) {
        t.cancel();
        setState(() {
          _leftResult = _leftRec!.result();
          _rightResult = _rightRec!.result();
        });
      } else {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _events?.cancel();
    _connections?.cancel();
    _testTimer?.cancel();
    for (final p in _pads) {
      p.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_supported) {
      return _centered(Icons.sports_esports_outlined, 'Controller test needs a real device',
          'Open the app on a phone or computer, then connect your controller by USB or Bluetooth.');
    }
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_pads.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.12),
            _centered(
              Icons.videogame_asset_off,
              'No controller found',
              'Connect a PS5 (DualSense) or Xbox controller by USB cable or Bluetooth, '
                  'then pull down to refresh.\n\n'
                  'Bluetooth pairing: hold the pairing button until the light flashes '
                  '(PS5: Create + PS; Xbox: the small button on top).',
              action: FilledButton.icon(
                  onPressed: _refresh, icon: const Icon(Icons.refresh), label: const Text('Refresh')),
            ),
          ],
        ),
      );
    }
    return _tester(context);
  }

  Widget _tester(BuildContext context) {
    final names = brandNames(_brand);
    final testing = _testTimer?.isActive ?? false;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _padPicker(context, names),
        const SizedBox(height: 12),
        _driftTestCard(context, testing),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _stickCard(context, 'Left stick', true, _leftResult)),
            const SizedBox(width: 12),
            Expanded(child: _stickCard(context, 'Right stick', false, _rightResult)),
          ],
        ),
        const SizedBox(height: 12),
        _triggerCard(context),
        const SizedBox(height: 12),
        _buttonsCard(context, names),
      ],
    );
  }

  Widget _padPicker(BuildContext context, ({String label, String a, String b, String x, String y, String view}) names) {
    final scheme = Theme.of(context).colorScheme;
    final icon = switch (_brand) {
      ControllerBrand.playstation => Icons.sports_esports,
      ControllerBrand.xbox => Icons.sports_esports,
      ControllerBrand.generic => Icons.videogame_asset,
    };
    return Card(
      color: scheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(icon, size: 28, color: scheme.onSecondaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${names.label} controller',
                      style: TextStyle(color: scheme.onSecondaryContainer, fontSize: 12)),
                  Text(_selectedPad?.name ?? 'Controller',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold, color: scheme.onSecondaryContainer),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
            if (_pads.length > 1)
              DropdownButton<String>(
                value: _selectedId,
                underline: const SizedBox.shrink(),
                items: [
                  for (final p in _pads)
                    DropdownMenuItem(value: p.id, child: Text(p.name, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (id) => setState(() {
                  _selectedId = id;
                  _resetTest();
                }),
              ),
          ],
        ),
      ),
    );
  }

  Widget _driftTestCard(BuildContext context, bool testing) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.troubleshoot),
                const SizedBox(width: 8),
                Text('Stick drift test', style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              testing
                  ? 'Let go of both sticks and don’t touch them…'
                  : 'Take your thumbs off both sticks, then start. Drift is when a stick '
                      'reports movement while you’re not touching it.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            if (testing)
              Row(children: [
                Expanded(child: LinearProgressIndicator(value: 1 - _testTicksLeft / 50)),
                const SizedBox(width: 12),
                Text('${(_testTicksLeft * 0.06).ceil()}s'),
              ])
            else
              FilledButton.icon(
                onPressed: _startDriftTest,
                icon: const Icon(Icons.play_arrow),
                label: Text(_leftResult == null ? 'Start test' : 'Test again'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _stickCard(BuildContext context, String title, bool left, StickDriftResult? result) {
    final x = _state.axisValue(left ? GamepadAxis.leftStickX : GamepadAxis.rightStickX);
    final y = _state.axisValue(left ? GamepadAxis.leftStickY : GamepadAxis.rightStickY);
    final pressed = _state.isPressed(left ? GamepadButton.leftStick : GamepadButton.rightStick);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text(title, style: Theme.of(context).textTheme.titleSmall
                        ?.copyWith(fontWeight: FontWeight.w600))),
                if (pressed) const Icon(Icons.radio_button_checked, size: 16),
              ],
            ),
            const SizedBox(height: 8),
            AspectRatio(
              aspectRatio: 1,
              child: StickPad(
                x: x,
                y: y,
                deadZone: result == null ? 0 : result.recommendedDeadZonePercent / 100,
                driftRing: result?.maxMagnitude ?? 0,
              ),
            ),
            const SizedBox(height: 8),
            Text('X ${x.toStringAsFixed(2)}   Y ${y.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.bodySmall),
            if (result != null) ...[
              const SizedBox(height: 6),
              _verdictChip(context, result),
            ],
          ],
        ),
      ),
    );
  }

  Widget _verdictChip(BuildContext context, StickDriftResult r) {
    final scheme = Theme.of(context).colorScheme;
    final (color, text) = switch (r.verdict) {
      DriftVerdict.healthy => (const Color(0xFF2E7D32), 'No drift (${r.driftPercent}%)'),
      DriftVerdict.minor => (const Color(0xFFE09400), 'Slight wander (${r.driftPercent}%)'),
      DriftVerdict.drift => (scheme.error, 'Stick drift (${r.driftPercent}%)'),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
          child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12)),
        ),
        const SizedBox(height: 6),
        Text(_driftAdvice(r), style: Theme.of(context).textTheme.bodySmall),
      ],
    );
  }

  String _driftAdvice(StickDriftResult r) {
    return switch (r.verdict) {
      DriftVerdict.healthy =>
        'Rests ${r.direction == 'centred' ? 'dead centre' : 'near centre'}. Stick is fine.',
      DriftVerdict.minor =>
        'Drifts slightly ${r.direction}. Try: blow compressed air around the stick base, '
            'or raise the in-game dead zone to about ${r.recommendedDeadZonePercent}%.',
      DriftVerdict.drift =>
        'Clear drift ${r.direction}. A ${r.recommendedDeadZonePercent}% dead zone hides it in games, '
            'but the real fix is cleaning or replacing the stick module (or a warranty claim).',
    };
  }

  Widget _triggerCard(BuildContext context) {
    final lt = _state.axisValue(GamepadAxis.leftTrigger);
    final rt = _state.axisValue(GamepadAxis.rightTrigger);
    final brand = _brand == ControllerBrand.playstation;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Triggers', style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            _triggerBar(context, brand ? 'L2' : 'LT', lt),
            const SizedBox(height: 10),
            _triggerBar(context, brand ? 'R2' : 'RT', rt),
            const SizedBox(height: 6),
            Text('Press each trigger fully - the bar should reach 100%.',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }

  Widget _triggerBar(BuildContext context, String label, double v) {
    return Row(
      children: [
        SizedBox(width: 34, child: Text(label, style: const TextStyle(fontWeight: FontWeight.w600))),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(value: v, minHeight: 14),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(width: 44, child: Text('${(v * 100).round()}%', textAlign: TextAlign.right)),
      ],
    );
  }

  Widget _buttonsCard(BuildContext context, ({String label, String a, String b, String x, String y, String view}) names) {
    final items = <(String, GamepadButton)>[
      (names.a, GamepadButton.a),
      (names.b, GamepadButton.b),
      (names.x, GamepadButton.x),
      (names.y, GamepadButton.y),
      (_brand == ControllerBrand.playstation ? 'L1' : 'LB', GamepadButton.leftBumper),
      (_brand == ControllerBrand.playstation ? 'R1' : 'RB', GamepadButton.rightBumper),
      ('Up', GamepadButton.dpadUp),
      ('Down', GamepadButton.dpadDown),
      ('Left', GamepadButton.dpadLeft),
      ('Right', GamepadButton.dpadRight),
      (names.view, GamepadButton.back),
      ('Start', GamepadButton.start),
      (_brand == ControllerBrand.playstation ? 'PS' : 'Guide', GamepadButton.home),
      ('L3', GamepadButton.leftStick),
      ('R3', GamepadButton.rightStick),
      if (_brand == ControllerBrand.playstation) ('Touchpad', GamepadButton.touchpad),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Buttons', style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text('Press each button - a dead button won’t light up.',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [for (final (label, btn) in items) _buttonChip(context, label, _state.isPressed(btn))],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buttonChip(BuildContext context, String label, bool pressed) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 80),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: pressed ? scheme.primary : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              color: pressed ? scheme.onPrimary : scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600)),
    );
  }

  Widget _centered(IconData icon, String title, String body, {Widget? action}) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: scheme.primary),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.headlineSmall, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(body,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: scheme.onSurfaceVariant)),
            if (action != null) ...[const SizedBox(height: 24), action],
          ],
        ),
      ),
    );
  }
}
