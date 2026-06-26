import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:requests_inspector/requests_inspector.dart';
import 'package:requests_inspector/src/shared_widgets/request_details_page.dart';

/// A realistic, deeply nested GraphQL response body (mirrors the structure of
/// a real API response: nested objects, a list of objects and a string field).
Map<String, dynamic> _buildRealResponseBody() => {
      'data': {
        'currentSession': {
          'pk': '00000000-0000-0000-0000-000000000001',
          'device': {
            'deviceName': 'iPhone Mock Model (iPhoneMock,1)',
            'isActive': true,
            'deviceVersion': 'iOS 0.0',
            'staticToken': 'mock-static-token',
          },
          'user': {
            'username': 'user@example.com',
            'fullName': 'Mock User Account',
            'metadata':
                '{"rt": "000", "rw": "000", "new_mobile": "+10000000000"}',
            'grantedPerms': [
              {'codename': 'core.cardstatement.can_view', 'name': 'CARDSTATEMENT_VIEW'},
              {'codename': 'monit_card.bill.can_create', 'name': 'BILL_CREATE'},
              {'codename': 'cashback.cashback.can_view', 'name': 'CASHBACK_VIEW'},
              {'codename': 'core.card.can_pay', 'name': 'CARD_PAY'},
              {'codename': 'core.card.can_view', 'name': 'CARD_VIEW'},
            ],
            'permGroup': {
              'pk': '00000000-0000-0000-0000-000000000002',
              'name': 'FINANCE_MEMBER',
              'description': 'Manage and approve financial requests.',
            },
          },
        },
      },
    };

Map<String, dynamic> _buildTallResponseBody() => {
      'data': {
        'items': [
          for (var i = 0; i < 60; i++) {'index': i, 'label': 'row_$i'},
          {'index': 999, 'label': 'NEEDLE_marker_value'},
          for (var i = 0; i < 60; i++) {'index': 1000 + i, 'label': 'tail_$i'},
        ],
      },
    };

int _countHighlightedInSpan(InlineSpan? span) {
  if (span == null) return 0;
  var count = 0;
  span.visitChildren((inline) {
    if (inline is TextSpan) {
      final bg = inline.style?.backgroundColor;
      if (bg == Colors.yellow || bg == Colors.orange) count++;
    }
    return true;
  });
  return count;
}

/// Counts every highlighted (yellow/orange) span actually rendered on screen.
int _countHighlightedSpans() {
  var count = 0;
  for (final element in find.byType(RichText).evaluate()) {
    count += _countHighlightedInSpan((element.widget as RichText).text);
  }
  for (final element in find.byType(SelectableText).evaluate()) {
    count += _countHighlightedInSpan((element.widget as SelectableText).textSpan);
  }
  return count;
}

bool _hasColoredSpan(InlineSpan? span, Color color) {
  if (span == null) return false;
  var found = false;
  span.visitChildren((inline) {
    if (inline is TextSpan && inline.style?.backgroundColor == color) {
      found = true;
    }
    return true;
  });
  return found;
}

int _activeSpanCount() {
  var active = 0;
  for (final element in find.byType(SelectableText).evaluate()) {
    if (_hasColoredSpan((element.widget as SelectableText).textSpan,
        Colors.orange)) {
      active++;
    }
  }
  return active;
}

Rect? _activeMatchRect(WidgetTester tester) {
  for (final element in find.byType(SelectableText).evaluate()) {
    final selectable = element.widget as SelectableText;
    if (_hasColoredSpan(selectable.textSpan, Colors.orange)) {
      return tester.getRect(find.byWidget(selectable));
    }
  }
  return null;
}

Widget _wrap(InspectorController controller) {
  return MaterialApp(
    home: Scaffold(
      body: ChangeNotifierProvider<InspectorController>.value(
        value: controller,
        child: const Column(children: [RequestDetailsPage()]),
      ),
    ),
  );
}

Future<InspectorController> _pumpWithSearch(
  WidgetTester tester, {
  required dynamic responseBody,
  required String query,
  bool treeView = true,
  dynamic headers,
  String url = 'http://example.com/graphql',
}) async {
  final controller = InspectorController(
    enabled: true,
    showInspectorOn: ShowInspectorOn.Both,
  );
  controller.clearAllRequests();
  if (!treeView) controller.toggleInspectorJsonView();

  controller.selectedRequest = RequestDetails(
    url: url,
    requestMethod: RequestMethod.POST,
    statusCode: 200,
    headers: headers,
    responseBody: responseBody,
  );

  await tester.pumpWidget(_wrap(controller));
  await tester.pumpAndSettle();

  controller.toggleSearchVisibility();
  controller.updateSearchQuery(query);
  await tester.pumpAndSettle();

  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Response body value matches are highlighted (tree view)',
      (tester) async {
    final controller = await _pumpWithSearch(
      tester,
      responseBody: _buildRealResponseBody(),
      query: 'iPhone',
    );
    expect(tester.takeException(), isNull);
    expect(controller.totalMatches, greaterThan(0));
    expect(_countHighlightedSpans(), greaterThan(0));
  });

  testWidgets('Response body value matches are highlighted (text view)',
      (tester) async {
    await _pumpWithSearch(
      tester,
      responseBody: _buildRealResponseBody(),
      query: 'iPhone',
      treeView: false,
    );
    expect(tester.takeException(), isNull);
    expect(_countHighlightedSpans(), greaterThan(0));
  });

  testWidgets('Response body provided as a JSON string is searchable',
      (tester) async {
    await _pumpWithSearch(
      tester,
      responseBody: '{"device":{"deviceName":"iPhone 17 Pro Max"}}',
      query: 'iPhone',
    );
    expect(tester.takeException(), isNull);
    expect(_countHighlightedSpans(), greaterThan(0));
  });

  // Regression: object/array KEY names are rendered in the tree's collapsible
  // node titles. They used to be neither counted nor highlighted, so searching
  // a parent key (very common in a GraphQL response) highlighted nothing.
  for (final query in ['currentSession', 'grantedPerms', 'device', 'permGroup']) {
    testWidgets('Object/array key "$query" is highlighted in tree view',
        (tester) async {
      final controller = await _pumpWithSearch(
        tester,
        responseBody: _buildRealResponseBody(),
        query: query,
      );
      expect(controller.totalMatches, greaterThan(0),
          reason: 'key "$query" must be counted');
      expect(_countHighlightedSpans(), greaterThan(0),
          reason: 'key "$query" must be highlighted');
    });
  }

  // Every counted match must be highlighted exactly once (no phantom matches),
  // across both render modes and several queries that hit keys and values.
  for (final treeView in [true, false]) {
    final mode = treeView ? 'tree' : 'text';
    for (final query in ['can_view', 'card', 'name', 'core', 'pk', 'user']) {
      testWidgets('[$mode] total == rendered highlights for "$query"',
          (tester) async {
        final controller = await _pumpWithSearch(
          tester,
          responseBody: _buildRealResponseBody(),
          query: query,
          treeView: treeView,
        );
        expect(_countHighlightedSpans(), controller.totalMatches,
            reason: '[$mode] "$query": every counted match must render once');
      });
    }
  }

  // Stepping through matches must always land on exactly one active highlight,
  // proving the per-section offsets stay aligned with the global index.
  for (final treeView in [true, false]) {
    final mode = treeView ? 'tree' : 'text';
    testWidgets('[$mode] each match index has exactly one active span',
        (tester) async {
      final controller = await _pumpWithSearch(
        tester,
        responseBody: _buildRealResponseBody(),
        query: 'card',
        treeView: treeView,
        headers: {'x-card-token': 'card-abc'},
        url: 'http://example.com/graphql?card=1',
      );
      final total = controller.totalMatches;
      expect(total, greaterThan(0));
      for (var i = 0; i < total; i++) {
        expect(_activeSpanCount(), 1,
            reason: '[$mode] index $i must have exactly one active span');
        controller.nextMatch();
        await tester.pumpAndSettle();
      }
    });
  }

  testWidgets('Active match deep in a tall response scrolls into view',
      (tester) async {
    final controller = await _pumpWithSearch(
      tester,
      responseBody: _buildTallResponseBody(),
      query: 'NEEDLE',
    );
    expect(tester.takeException(), isNull);
    expect(controller.totalMatches, greaterThan(0));

    final screen = tester.getSize(find.byType(MaterialApp));
    final rect = _activeMatchRect(tester);
    expect(rect, isNotNull);
    expect(rect!.bottom > 0 && rect.top < screen.height, isTrue,
        reason: 'the active response-body match must be scrolled into view');
  });
}
