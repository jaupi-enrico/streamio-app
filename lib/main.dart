import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'core/app_version.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();
  // Awaited before the first widget builds: ApiClient stamps
  // X-Client-Version from a synchronous constructor, so the version has to be
  // known before anything can create one.
  await AppVersion.load();
  runApp(const ProviderScope(child: StreamioApp()));
}
