// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_idp_ui/main.dart';

void main() {
  testWidgets('login screen renders before dashboard',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const ProviderScope(
        child: PatientMonitoringApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Patient'), findsOneWidget);
    expect(find.text('Create'), findsOneWidget);
    expect(find.text('Family'), findsOneWidget);
  });
}
