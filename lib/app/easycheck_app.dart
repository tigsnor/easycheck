import 'package:flutter/material.dart';

import '../features/experiments/presentation/experiments_home_screen.dart';
import '../shared/presentation/local_data_recovery_listener.dart';
import 'theme.dart';

class EasyCheckApp extends StatelessWidget {
  const EasyCheckApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PlateNote',
      debugShowCheckedModeBanner: false,
      theme: buildEasyCheckTheme(),
      builder: (context, child) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: child ?? const SizedBox.shrink(),
      ),
      home: const LocalDataRecoveryListener(child: ExperimentsHomeScreen()),
    );
  }
}
