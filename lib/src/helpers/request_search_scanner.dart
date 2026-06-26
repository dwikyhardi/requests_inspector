import '../graphql_tree_view_widget.dart';
import '../json_pretty_converter.dart';
import '../json_tree_view_widget.dart';
import '../request_details.dart';
import 'graphql_helper.dart';
import 'inspector_helper.dart';
import 'search_helper.dart';

/// Computes, in one place, the search-match counts and match-index offsets for
/// every section that [RequestDetailsPage] renders for a [RequestDetails].
///
/// The details page highlights matches section by section and navigates them
/// by a single global "current match index". For navigation and the
/// `current / total` counter to stay correct, three things must agree exactly:
///
///  * the total number of matches (held by `InspectorController`),
///  * the per-section offsets the page assigns to its highlighted widgets, and
///  * the matches a section actually renders.
///
/// Previously these were computed independently (and over pretty-printed JSON),
/// which desynced them in two ways: sections that are not rendered were still
/// counted (most notably the raw request body when a GraphQL query is shown
/// instead), and JSON counted over pretty text diverged from what the tree view
/// highlights. This scanner is the single source of truth that both the
/// controller and the page consume so those three views can never drift apart.
class RequestSearchScanner {
  RequestSearchScanner({
    required this.request,
    required this.query,
    required this.isTreeView,
  }) {
    _compute();
  }

  final RequestDetails request;
  final String query;
  final bool isTreeView;

  int timeAndUrlOffset = 0;
  int timeAndUrlCount = 0;

  int headersOffset = 0;
  int headersCount = 0;

  int queryParamsOffset = 0;
  int queryParamsCount = 0;

  int graphqlQueryOffset = 0;
  int graphqlQueryCount = 0;

  int requestBodyOffset = 0;
  int requestBodyCount = 0;

  int graphqlVarsOffset = 0;
  int graphqlVarsCount = 0;

  int responseBodyOffset = 0;
  int responseBodyCount = 0;

  int total = 0;

  /// Whether a GraphQL query/mutation is rendered (instead of the raw body).
  bool get hasGraphqlQuery => GraphQLHelper.parse(request.requestBody) != null;

  /// The GraphQL query/mutation document, or an empty string when absent.
  String get graphqlQuery =>
      GraphQLHelper.parse(request.requestBody)?.query ?? '';

  void _compute() {
    var offset = 0;

    timeAndUrlOffset = offset;
    timeAndUrlCount = SearchHelper.findMatches(
      text: buildTimeAndUrlText(
        sentTime: request.sentTime,
        receivedTime: request.receivedTime,
        url: request.url,
      ),
      query: query,
    ).length;
    offset += timeAndUrlCount;

    headersOffset = offset;
    headersCount = _hasData(request.headers) ? _jsonCount(request.headers) : 0;
    offset += headersCount;

    queryParamsOffset = offset;
    queryParamsCount = _hasData(request.queryParameters)
        ? _jsonCount(request.queryParameters)
        : 0;
    offset += queryParamsCount;

    graphqlQueryOffset = offset;
    if (hasGraphqlQuery) {
      final searchText =
          isTreeView ? GraphqlTreeView.flatten(graphqlQuery) : graphqlQuery;
      graphqlQueryCount =
          SearchHelper.findMatches(text: searchText, query: query).length;
    } else {
      graphqlQueryCount = 0;
    }
    offset += graphqlQueryCount;

    requestBodyOffset = offset;
    requestBodyCount = (!hasGraphqlQuery && _hasData(request.requestBody))
        ? _jsonCount(request.requestBody)
        : 0;
    offset += requestBodyCount;

    graphqlVarsOffset = offset;
    graphqlVarsCount = _hasData(request.graphqlRequestVars)
        ? _jsonCount(request.graphqlRequestVars)
        : 0;
    offset += graphqlVarsCount;

    responseBodyOffset = offset;
    responseBodyCount =
        _hasData(request.responseBody) ? _jsonCount(request.responseBody) : 0;
    offset += responseBodyCount;

    total = offset;
  }

  /// Counts matches for a JSON-like section exactly the way it is rendered:
  /// via the tree's own linearization in tree view, or over pretty-printed
  /// JSON (line by line, which equals the whole-text count) in text view.
  int _jsonCount(dynamic data) => isTreeView
      ? JsonTreeView.countMatches(data, query)
      : SearchHelper.findMatches(
          text: JsonPrettyConverter().convert(data),
          query: query,
        ).length;

  /// Builds the combined "Sent at / Received at / Duration / URL" text. Shared
  /// with the page so the counted text and the rendered text are identical.
  static String buildTimeAndUrlText({
    required DateTime sentTime,
    required DateTime? receivedTime,
    required String url,
  }) {
    final sentTimeText = InspectorHelper.extractTimeText(sentTime);
    var text = 'Sent at: $sentTimeText';

    if (receivedTime != null) {
      final receivedTimeText = InspectorHelper.extractTimeText(receivedTime);
      final durationText =
          InspectorHelper.calculateDuration(sentTime, receivedTime);
      text += '\nReceived at: $receivedTimeText\nDuration: $durationText';
    }

    text += '\n\nURL: $url';
    return text;
  }

  static bool _hasData(dynamic data) {
    if (data == null) return false;
    if (data is Map) return data.isNotEmpty;
    if (data is List) return data.isNotEmpty;
    if (data is String) return data.trim().isNotEmpty;
    return true;
  }
}
