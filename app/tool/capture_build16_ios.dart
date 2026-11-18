// Capture-only entry point. Never use this entry point for a store build.
// Product widgets are imported unchanged; only device data and viewport vary.
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_reactive_ble/flutter_reactive_ble.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path_provider/path_provider.dart';

import 'package:septronics/app/product_ui_state.dart';
import 'package:septronics/ble/led_ui_state.dart';
import 'package:septronics/ble/models.dart';
import 'package:septronics/ble/scan_controller.dart';
import 'package:septronics/ble/stock_controller.dart';
import 'package:septronics/main.dart';
import 'package:septronics/screens/bluetooth_setting_screen.dart';
import 'package:septronics/screens/led_setting_screen.dart';
import 'package:septronics/screens/splash_screen.dart';
import 'package:septronics/screens/stock_select_screen.dart';

class CaptureStock extends StockController {
  CaptureStock(super.ref) {
    state = const StockState(
      loaded: true,
      a: StockSideState(
        device: BleDevice(id: 'capture-a', name: 'Noxel-1'),
        status: DeviceConnectionState.connected,
      ),
      b: StockSideState(
        device: BleDevice(id: 'capture-b', name: 'Noxel-2'),
        status: DeviceConnectionState.connected,
      ),
    );
  }
}

class CaptureScan extends ScanController {
  CaptureScan(super.ref);
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  assert(sceptronicScreenshotMode, 'Requires SCEPTRONIC_SCREENSHOT=true');
  runApp(const CaptureHost());
}

class CaptureHost extends StatefulWidget {
  const CaptureHost({super.key});
  @override
  State<CaptureHost> createState() => _CaptureHostState();
}

class _CaptureHostState extends State<CaptureHost> {
  final boundary = GlobalKey();
  late final ProviderContainer providers;
  Size logical = const Size(440, 956);
  int screen = 0;
  int generation = 0;

  static const profiles = <(String, int, int, double)>[
    ('6.9-inch', 1320, 2868, 3),
    ('6.3-inch', 1206, 2622, 3),
    ('6.1-inch', 1170, 2532, 3),
    ('5.5-inch', 1242, 2208, 3),
    ('ipad-13-inch', 2064, 2752, 2),
    ('ipad-12.9-inch', 2048, 2732, 2),
    ('ipad-11-inch', 1668, 2420, 2),
  ];
  static const names = [
    '01-stock-select.png',
    '02-color-setting.png',
    '03-bluetooth-setting.png',
    '04-splash.png',
  ];

  @override
  void initState() {
    super.initState();
    providers = ProviderContainer(overrides: [
      stockProvider.overrideWith((ref) => CaptureStock(ref)),
      scanProvider.overrideWith((ref) => CaptureScan(ref)),
    ]);
    providers.read(demoModeProvider.notifier).state = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(capture()));
  }

  Future<void> capture() async {
    try {
      final documents = await getApplicationDocumentsDirectory();
      final root = Directory('${documents.path}/build16-ios-ui-renders');
      await root.create(recursive: true);
      await providers.read(ledUiProvider.notifier).ensureLoaded();
      final led = providers.read(ledUiProvider.notifier);
      for (final profile in profiles) {
        final folder = Directory('${root.path}/${profile.$1}');
        await folder.create(recursive: true);
        for (var index = 0; index < names.length; index++) {
          // Fixture data only. No BLE connection, firmware or product source edits.
          led.setSegmentColor(StockSide.a, ColorZone.both,
              const HSVColor.fromAHSV(1, 314, 70 / 255, 242 / 255).toColor(),
              persist: false);
          led.setSegmentMode(StockSide.a, ColorZone.both, LedMode.rainbow,
              persist: false);
          led.setSegmentColor(
              StockSide.b, ColorZone.both, const Color(0xFF22C7F0),
              persist: false);
          led.setSegmentMode(StockSide.b, ColorZone.both, LedMode.color,
              persist: false);
          led.setBatteryVoltage(StockSide.a, 2.05, .82);
          led.setBatteryVoltage(StockSide.b, 2.01, .75);
          setState(() {
            logical = Size(profile.$2 / profile.$4, profile.$3 / profile.$4);
            screen = index;
            generation++;
          });
          await Future<void>.delayed(const Duration(milliseconds: 2200));
          await GoogleFonts.pendingFonts();
          await WidgetsBinding.instance.endOfFrame;
          final render = boundary.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
          final image = await render.toImage(pixelRatio: profile.$4);
          if (image.width != profile.$2 || image.height != profile.$3) {
            throw StateError(
                'Wrong dimensions: ${image.width}x${image.height}');
          }
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await File('${folder.path}/${names[index]}')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
          debugPrint('CAPTURED ${profile.$1}/${names[index]}');
        }
      }
      await File('${root.path}/COMPLETE.txt').writeAsString(
        '28 UI renders complete. Build 16 widgets; capture-only fixture data.\n'
        'No OS status bar. iPad/5.5-inch are viewport renders, not device screenshots.\n',
      );
      debugPrint('CAPTURE COMPLETE ${root.path}');
    } catch (error, stack) {
      debugPrint('CAPTURE FAILED $error\n$stack');
    }
  }

  @override
  Widget build(BuildContext context) {
    final productApp = const BleLedApp().build(context) as MaterialApp;
    final page = switch (screen) {
      0 => const StockSelectScreen(),
      1 => const LedSettingScreen(side: StockSide.a),
      2 => const BluetoothSettingScreen(),
      _ => SplashScreen(onFinished: () {}),
    };
    return Directionality(
      textDirection: TextDirection.ltr,
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: logical.width,
        maxWidth: logical.width,
        minHeight: logical.height,
        maxHeight: logical.height,
        child: RepaintBoundary(
          key: boundary,
          child: SizedBox(
            width: logical.width,
            height: logical.height,
            child: UncontrolledProviderScope(
              container: providers,
              child: MaterialApp(
                key: ValueKey(generation),
                debugShowCheckedModeBanner: false,
                theme: productApp.theme!.copyWith(platform: TargetPlatform.iOS),
                builder: (context, child) => MediaQuery(
                  data: MediaQueryData(size: logical, devicePixelRatio: 1),
                  child: child!,
                ),
                home: page,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
