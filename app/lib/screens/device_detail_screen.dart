import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_colorpicker/flutter_colorpicker.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';

import '../ble/connection_controller.dart';
import '../ble/led_controller.dart';

class DeviceDetailScreen extends ConsumerStatefulWidget {
  final String deviceId;
  final String? deviceName;
  const DeviceDetailScreen(
      {super.key, required this.deviceId, this.deviceName});

  @override
  ConsumerState<DeviceDetailScreen> createState() => _DeviceDetailScreenState();
}

class _DeviceDetailScreenState extends ConsumerState<DeviceDetailScreen> {
  ProviderSubscription<ConnectionStateModel>? _connectionSub;
  double _brightness = 255;
  double _rainbowInterval = 40;
  bool _accelEnabled = false;
  bool _outputEnabled = false;
  Color _frontColor = const Color(0xFFFF7828);
  Color _rearColor = const Color(0xFF2196F3);

  @override
  void initState() {
    super.initState();
    _connectionSub = ref.listenManual<ConnectionStateModel>(connectionProvider,
        (prev, next) {
      final wasConnected = prev?.status == DeviceConnectionState.connected;
      final isConnected = next.status == DeviceConnectionState.connected;
      if (!wasConnected && isConnected) {
        _outputEnabled = false;
        _accelEnabled = false;
        if (mounted) {
          setState(() {});
        }
        _sendCommand(
          () => ref.read(ledControllerProvider).applyIdleState(widget.deviceId),
        );
      } else if (wasConnected && !isConnected) {
        if (mounted) {
          setState(() {
            _outputEnabled = false;
            _accelEnabled = false;
          });
        }
      }
    });
    final connection = ref.read(connectionProvider.notifier);
    Future.microtask(() {
      if (!mounted) {
        return;
      }
      connection.connect(widget.deviceId);
    });
  }

  @override
  void dispose() {
    final led = ref.read(ledControllerProvider);
    final connection = ref.read(connectionProvider.notifier);
    _connectionSub?.close();
    Future.microtask(() => led.applyIdleState(widget.deviceId));
    connection.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final connectionState = ref.watch(connectionProvider);
    final ledController = ref.watch(ledControllerProvider);
    final connected = connectionState.status == DeviceConnectionState.connected;
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.deviceName ?? widget.deviceId),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Connect'),
              Tab(text: 'Colors'),
              Tab(text: 'Effects'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _buildConnectionTab(
                context, connectionState, connected, ledController),
            _buildColorTab(context, connected, ledController),
            _buildEffectTab(context, connected, ledController, connectionState),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionTab(
    BuildContext context,
    ConnectionStateModel state,
    bool connected,
    LedController led,
  ) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('Status: '),
              Text(
                state.status.name,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              ElevatedButton(
                onPressed: connected
                    ? null
                    : () => ref
                        .read(connectionProvider.notifier)
                        .connect(widget.deviceId),
                child: const Text('Connect'),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: connected
                    ? () => _sendCommand(() async {
                          await led.applyIdleState(widget.deviceId);
                          await ref
                              .read(connectionProvider.notifier)
                              .disconnect();
                        })
                    : null,
                child: const Text('Disconnect'),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Enable Output'),
            subtitle:
                const Text('Output is gated until a color or effect is set'),
            value: _outputEnabled,
            onChanged: connected
                ? (value) {
                    final previousOutput = _outputEnabled;
                    final previousAccel = _accelEnabled;
                    setState(() {
                      _outputEnabled = value;
                      if (!value) {
                        _accelEnabled = false;
                      }
                    });
                    _sendCommand(() async {
                      await led.setOutputEnabled(widget.deviceId, value);
                      if (!value) {
                        await led.stopRainbow(widget.deviceId);
                        await led.setAccelMode(widget.deviceId, false);
                      }
                    }, onError: () {
                      if (!mounted) return;
                      setState(() {
                        _outputEnabled = previousOutput;
                        _accelEnabled = previousAccel;
                      });
                    });
                  }
                : null,
          ),
          const Spacer(),
          if (state.message != null)
            Text(
              state.message!,
              style: const TextStyle(color: Colors.red),
            ),
        ],
      ),
    );
  }

  Widget _buildColorTab(
    BuildContext context,
    bool connected,
    LedController led,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double circleSize = math
            .min(constraints.maxWidth, 260.0)
            .clamp(160.0, 260.0)
            .toDouble();

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Brightness'),
                  Text(_brightness.round().toString()),
                ],
              ),
              Slider(
                value: _brightness,
                min: 0,
                max: 255,
                divisions: 255,
                label: _brightness.round().toString(),
                onChanged: connected
                    ? (value) => setState(() => _brightness = value)
                    : null,
                onChangeEnd: connected
                    ? (value) => _sendCommand(() async {
                          await led.setBrightness(
                              widget.deviceId, value.round());
                        })
                    : null,
              ),
              const SizedBox(height: 24),
              _buildColorSection(
                context,
                title: 'Front (D9)',
                color: _frontColor,
                onChanged: (color) => setState(() => _frontColor = color),
                onApply: connected
                    ? () => _sendCommand(() async {
                          await _ensureOutputEnabled(led);
                          final rgb = _rgbComponents(_frontColor);
                          await led.setFrontColor(
                              widget.deviceId, rgb[0], rgb[1], rgb[2]);
                        })
                    : null,
                onOff: connected
                    ? () => _sendCommand(() async {
                          await _ensureOutputEnabled(led);
                          await led.setFrontColor(widget.deviceId, 0, 0, 0);
                        })
                    : null,
                enabled: connected,
                circleSize: circleSize,
              ),
              const SizedBox(height: 24),
              _buildColorSection(
                context,
                title: 'Rear (D10)',
                color: _rearColor,
                onChanged: (color) => setState(() => _rearColor = color),
                onApply: connected
                    ? () => _sendCommand(() async {
                          await _ensureOutputEnabled(led);
                          final rgb = _rgbComponents(_rearColor);
                          await led.setRearColor(
                              widget.deviceId, rgb[0], rgb[1], rgb[2]);
                        })
                    : null,
                onOff: connected
                    ? () => _sendCommand(() async {
                          await _ensureOutputEnabled(led);
                          await led.setRearColor(widget.deviceId, 0, 0, 0);
                        })
                    : null,
                enabled: connected,
                circleSize: circleSize,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEffectTab(
    BuildContext context,
    bool connected,
    LedController led,
    ConnectionStateModel state,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double gattHeight =
            (constraints.maxHeight * 0.35).clamp(140.0, 260.0).toDouble();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Rainbow'),
              Row(
                children: [
                  Expanded(
                    child: Slider(
                      value: _rainbowInterval,
                      min: 10,
                      max: 200,
                      divisions: 38,
                      label: '${_rainbowInterval.round()} ms',
                      onChanged: connected
                          ? (value) => setState(() => _rainbowInterval = value)
                          : null,
                    ),
                  ),
                  SizedBox(
                    width: 70,
                    child: Text(
                      '${_rainbowInterval.round()} ms',
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  FilledButton(
                    onPressed: connected
                        ? () => _sendCommand(() async {
                              await _ensureOutputEnabled(led);
                              await led.startRainbow(
                                widget.deviceId,
                                intervalMs: _rainbowInterval.round(),
                              );
                              if (mounted) {
                                setState(() => _accelEnabled = false);
                              }
                            })
                        : null,
                    child: const Text('Start'),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton(
                    onPressed: connected
                        ? () =>
                            _sendCommand(() => led.stopRainbow(widget.deviceId))
                        : null,
                    child: const Text('Stop'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Acceleration mode'),
                subtitle: const Text('Enable IMU-based color change'),
                value: _accelEnabled,
                onChanged: connected
                    ? (value) {
                        final previous = _accelEnabled;
                        setState(() => _accelEnabled = value);
                        _sendCommand(() async {
                          if (value) {
                            await _ensureOutputEnabled(led);
                          }
                          await led.setAccelMode(widget.deviceId, value);
                        }, onError: () {
                          if (mounted) {
                            setState(() => _accelEnabled = previous);
                          }
                        });
                      }
                    : null,
              ),
              const SizedBox(height: 12),
              const Text('Discovered GATT:'),
              const SizedBox(height: 8),
              SizedBox(
                height: gattHeight,
                child: _buildGattList(state),
              ),
              if (state.message != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    state.message!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildColorSection(
    BuildContext context, {
    required String title,
    required Color color,
    required ValueChanged<Color> onChanged,
    required VoidCallback? onApply,
    required VoidCallback? onOff,
    required bool enabled,
    required double circleSize,
  }) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        Center(
          child: Opacity(
            opacity: enabled ? 1 : 0.4,
            child: IgnorePointer(
              ignoring: !enabled,
              child: SizedBox(
                width: circleSize,
                height: circleSize,
                child: ColorPicker(
                  pickerColor: color,
                  paletteType: PaletteType.hueWheel,
                  colorPickerWidth: circleSize,
                  enableAlpha: false,
                  displayThumbColor: true,
                  pickerAreaBorderRadius:
                      const BorderRadius.all(Radius.circular(999)),
                  portraitOnly: true,
                  onColorChanged: onChanged,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            FilledButton(
              onPressed: onApply,
              child: const Text('Apply'),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              onPressed: onOff,
              child: const Text('OFF'),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _ensureOutputEnabled(LedController led) async {
    if (_outputEnabled) {
      return;
    }
    await led.setOutputEnabled(widget.deviceId, true);
    if (mounted) {
      setState(() => _outputEnabled = true);
    }
  }

  Future<void> _sendCommand(
    Future<void> Function() action, {
    VoidCallback? onError,
  }) async {
    try {
      await action();
    } catch (e, st) {
      debugPrint('LED command failed: $e');
      debugPrintStack(stackTrace: st);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Command failed: $e')),
      );
      onError?.call();
    }
  }

  List<int> _rgbComponents(Color color) {
    int channel(double component) => (component * 255.0).round().clamp(0, 255);
    return [
      channel(color.r),
      channel(color.g),
      channel(color.b),
    ];
  }

  Widget _buildGattList(ConnectionStateModel st) {
    if (st.services.isEmpty) {
      return const Center(child: Text('No services discovered yet'));
    }
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: st.services.length,
      itemBuilder: (context, i) {
        final s = st.services[i];
        return ExpansionTile(
          title: Text(s.uuid),
          children: s.characteristics
              .map(
                (c) => ListTile(
                  dense: true,
                  title: Text(c.uuid),
                  subtitle: Text([
                    if (c.canRead) 'R',
                    if (c.canWrite) 'W',
                    if (c.canNotify) 'N',
                    if (c.canIndicate) 'I',
                  ].join(' ')),
                ),
              )
              .toList(),
        );
      },
    );
  }
}
