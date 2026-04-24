import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'screens/home_screen.dart';
import 'services/pack_manager.dart';
import 'services/storage.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化服务
  final prefs = await SharedPreferences.getInstance();
  final packManager = PackManager();
  final storage = StorageService(prefs);

  runApp(BirdFlashcardApp(
    packManager: packManager,
    storage: storage,
  ));
}

class BirdFlashcardApp extends StatelessWidget {
  final PackManager packManager;
  final StorageService storage;

  const BirdFlashcardApp({
    super.key,
    required this.packManager,
    required this.storage,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Birdaholic',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2d5016),
        useMaterial3: true,
      ),
      home: HomeScreen(
        packManager: packManager,
        storage: storage,
      ),
    );
  }
}
