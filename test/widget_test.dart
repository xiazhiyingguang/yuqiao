import 'package:flutter_test/flutter_test.dart';
import 'package:yuqiao_app/main.dart';

void main() {
  testWidgets('shows Yuqiao home actions', (WidgetTester tester) async {
    await tester.pumpWidget(const YuqiaoApp());

    expect(find.text('补词'), findsOneWidget);
    expect(find.text('对话'), findsOneWidget);
    expect(find.text('拍照'), findsOneWidget);
    expect(find.text('词库'), findsOneWidget);
  });
}
