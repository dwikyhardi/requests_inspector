import 'package:flutter_test/flutter_test.dart';
import 'package:requests_inspector_plus/requests_inspector_plus.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InspectorController', () {
    late InspectorController inspectorController;

    setUp(() {
      inspectorController = InspectorController(
        enabled: true,
        showInspectorOn: ShowInspectorOn.Both,
      );
      inspectorController.clearAllRequests();
    });

    test('Initial values should be as expected', () {
      expect(inspectorController.isDarkMode, true);
      expect(inspectorController.isTreeView, true);
      expect(inspectorController.requestsList, isEmpty);
    });

    test('Should add new request', () {
      var request = RequestDetails(
        url: 'http://example.com',
        requestMethod: RequestMethod.GET,
      );
      inspectorController.addNewRequest(request);
      expect(inspectorController.requestsList.length, 1);
      expect(inspectorController.requestsList.first.url, 'http://example.com');
    });

    test('Should clear all requests', () {
      var request = RequestDetails(
        url: 'http://example.com',
        requestMethod: RequestMethod.GET,
      );
      inspectorController.addNewRequest(request);
      inspectorController.clearAllRequests();
      expect(inspectorController.requestsList, isEmpty);
      expect(inspectorController.selectedRequest, isNull);
    });

    test('Toggle dark mode should change state', () {
      inspectorController.toggleInspectorTheme();
      expect(inspectorController.isDarkMode, false);
      inspectorController.toggleInspectorTheme();
      expect(inspectorController.isDarkMode, true);
    });

    test('Search functionality works correctly', () {
      var request1 = RequestDetails(
        url: 'http://test1.com',
        requestMethod: RequestMethod.GET,
      );
      var request2 = RequestDetails(
        url: 'http://test2.com',
        requestMethod: RequestMethod.GET,
      );
      inspectorController.addNewRequest(request1);
      inspectorController.addNewRequest(request2);
      inspectorController.searchForRequests('test1');

      expect(inspectorController.filteredRequestsList.length, 1);
      expect(inspectorController.filteredRequestsList.first.url,
          'http://test1.com');
    });

    test('Search matches GraphQL query/mutation, not just the URL', () {
      // Both requests hit the same GraphQL endpoint, so the URL alone cannot
      // distinguish them; the operation name / query document must be searched.
      var sessionRequest = RequestDetails(
        url: 'https://example.com/graphql',
        requestMethod: RequestMethod.POST,
        requestBody: {
          'query': 'query CurrentSession { currentSession { id } }',
        },
      );
      var ordersRequest = RequestDetails(
        url: 'https://example.com/graphql',
        requestMethod: RequestMethod.POST,
        requestBody: {
          'query': 'mutation CreateOrder { createOrder { id } }',
        },
      );
      inspectorController.addNewRequest(sessionRequest);
      inspectorController.addNewRequest(ordersRequest);

      // Matching by operation name (case-insensitive).
      inspectorController.searchForRequests('currentsession');
      expect(inspectorController.filteredRequestsList.length, 1);
      expect(inspectorController.filteredRequestsList.first.requestName,
          'CurrentSession');

      // Matching by text inside the query document.
      inspectorController.searchForRequests('createOrder');
      expect(inspectorController.filteredRequestsList.length, 1);
      expect(inspectorController.filteredRequestsList.first.requestName,
          'CreateOrder');
    });

    test(
        'In-details total match count excludes the raw request body when a '
        'GraphQL query is rendered in its place', () {
      // The details page renders the extracted "GraphQL Query" section instead
      // of the raw request body for GraphQL requests. The raw body must
      // therefore NOT be counted, otherwise the counter and next/previous
      // navigation cycle through matches that are never highlighted.
      final request = RequestDetails(
        url: 'https://example.com/graphql',
        requestMethod: RequestMethod.POST,
        requestBody: {
          'query': 'query GetUser { user { name } }',
        },
      );
      inspectorController.selectedRequest = request;
      inspectorController.updateSearchQuery('user');

      // 'user' is highlighted exactly twice in the rendered GraphQL Query tree
      // ('GetUser' and 'user'); the (hidden) raw body would otherwise add two
      // phantom matches.
      expect(inspectorController.totalMatches, 2);
      expect(inspectorController.currentMatchIndex, 0);
    });
  });
}
