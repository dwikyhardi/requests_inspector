import 'package:example/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('Posts render and refresh using modern Material callbacks', (
    tester,
  ) async {
    var refreshes = 0;
    Future<void> onRefresh() async {
      refreshes++;
    }

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PostsListWidget(
            postsList: [Post(id: 1, title: 'A post', body: 'Post body')],
            onRefresh: onRefresh,
          ),
        ),
      ),
    );

    expect(find.text('1'), findsOneWidget);
    expect(find.text('A post'), findsOneWidget);
    expect(find.text('Post body'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, 300));
    await tester.pumpAndSettle();
    expect(refreshes, 1);
    expect(tester.takeException(), isNull);
  });
}
