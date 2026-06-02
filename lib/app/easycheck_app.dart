import 'package:flutter/material.dart';

import '../features/experiments/presentation/experiments_home_screen.dart';
import 'theme.dart';

class EasyCheckApp extends StatelessWidget {
  const EasyCheckApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EasyCheck',
      debugShowCheckedModeBanner: false,
      theme: buildEasyCheckTheme(),
      home: const ExperimentsHomeScreen(),
    );
  }
}
