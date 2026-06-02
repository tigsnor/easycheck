import 'package:flutter/material.dart';

import '../features/plates/presentation/plate_editor_screen.dart';
import 'theme.dart';

class EasyCheckApp extends StatelessWidget {
  const EasyCheckApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'EasyCheck',
      debugShowCheckedModeBanner: false,
      theme: buildEasyCheckTheme(),
      home: const PlateEditorScreen(),
    );
  }
}
