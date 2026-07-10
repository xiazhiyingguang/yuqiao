import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:yuqiao_app/main.dart';

void main() {
  testWidgets('shows Yuqiao home actions', (WidgetTester tester) async {
    FlutterSecureStorage.setMockInitialValues({});
    SharedPreferences.setMockInitialValues({
      'support_profile_v1': jsonEncode({
        'completed': true,
        'difficulties': ['找词'],
        'scenes': ['家里'],
        'cuePreferences': ['图片'],
        'trainingMinutes': 3,
        'candidateCount': 2,
        'needsFamilyAssist': false,
        'rememberChoices': true,
      }),
    });
    await tester.pumpWidget(const YuqiaoApp());
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 500)),
    );
    for (var attempt = 0; attempt < 20; attempt++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('补词').evaluate().isNotEmpty) break;
    }
    expect(find.text('补词'), findsOneWidget);
    expect(find.text('对话'), findsOneWidget);
    expect(find.text('拍照'), findsOneWidget);
    expect(find.text('词库'), findsOneWidget);
  });
}
