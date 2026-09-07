import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Set the secure flag before the first frame rather than after the vault
  // opens. The gap would be small, but it is exactly the window in which the
  // OS takes its app-switcher snapshot on a cold start.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarDividerColor: Colors.transparent,
  ));

  // Anything that reaches the top uncaught would otherwise print through the
  // default handler, which on release builds can include argument values. In a
  // password manager an argument is quite often a password.
  FlutterError.onError = (details) {
    FlutterError.presentError(
      FlutterErrorDetails(
        exception: details.exception,
        stack: details.stack,
        library: details.library,
        context: details.context,
        silent: details.silent,
      ),
    );
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    debugPrint('sablekey: uncaught error: ${error.runtimeType}');
    return true;
  };

  runApp(const ProviderScope(child: SablekeyApp()));
}
