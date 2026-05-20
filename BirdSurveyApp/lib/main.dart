import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/survey_provider.dart';
import 'screens/home_screen.dart';
import 'screens/history_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/setup_screen.dart';
import 'screens/survey_points_screen.dart';
import 'screens/survey_projects_screen.dart';
import 'screens/survey_screen.dart';
import 'screens/survey_start_screen.dart';
import 'services/species_meta_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SpeciesMetaService.init();
  runApp(
    ChangeNotifierProvider(
      create: (_) => SurveyProvider()..init(),
      child: const BirdSurveyApp(),
    ),
  );
}

class BirdSurveyApp extends StatelessWidget {
  const BirdSurveyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '中国鸟类调查',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E7D32),
          primary: const Color(0xFF2E7D32),
        ),
        useMaterial3: true,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF2E7D32),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: const _StartGate(),
      routes: {
        '/': (_) => const HomeScreen(),
        '/history': (_) => const HistoryScreen(),
        '/settings': (_) => const SettingsScreen(),
        '/survey': (_) => const SurveyScreen(),
        '/survey_start': (_) => const SurveyStartScreen(),
        '/survey_points': (_) => const SurveyPointsScreen(),
        '/survey_projects': (_) => const SurveyProjectsScreen(),
        '/setup': (_) => const SetupScreen(),
      },
    );
  }
}

// Routes to SetupScreen on first launch (no Tianditu key), else HomeScreen
class _StartGate extends StatelessWidget {
  const _StartGate();

  @override
  Widget build(BuildContext context) {
    final prov = context.watch<SurveyProvider>();
    if (prov.allSpecies.isEmpty) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!prov.setupDone) {
      return const SetupScreen();
    }
    return const HomeScreen();
  }
}
