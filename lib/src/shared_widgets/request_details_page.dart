import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:requests_inspector/requests_inspector.dart';
import 'package:requests_inspector/src/json_pretty_converter.dart';

import '../graphql_tree_view_widget.dart';
import '../helpers/graphql_helper.dart';
import '../helpers/inspector_helper.dart';
import '../helpers/request_search_scanner.dart';
import '../helpers/search_helper.dart';
import '../json_tree_view_widget.dart';
import 'highlighted_text.dart';
import 'search_widget.dart';

class _SearchState {
  final bool isTreeView;
  final bool isDarkMode;
  final String searchQuery;
  final bool expandChildren;

  _SearchState({
    required this.isTreeView,
    required this.isDarkMode,
    required this.searchQuery,
    required this.expandChildren,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _SearchState &&
          runtimeType == other.runtimeType &&
          isTreeView == other.isTreeView &&
          isDarkMode == other.isDarkMode &&
          searchQuery == other.searchQuery &&
          expandChildren == other.expandChildren;

  @override
  int get hashCode =>
      isTreeView.hashCode ^
      isDarkMode.hashCode ^
      searchQuery.hashCode ^
      expandChildren.hashCode;
}

class RequestDetailsPage extends StatelessWidget {
  const RequestDetailsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Selector<InspectorController, RequestDetails?>(
        selector: (_, inspectorController) =>
            inspectorController.selectedRequest,
        shouldRebuild: (previous, next) => true,
        builder: (context, selectedRequest, _) => selectedRequest == null
            ? const Center(
                child: Text('Please select a request first to view details'),
              )
            : Column(
                children: [
                  const SizedBox(height: 8),
                  Selector<InspectorController, bool>(
                    selector: (_, controller) => controller.isDarkMode,
                    builder: (context, isDarkMode, _) => SearchWidget(
                      isDarkMode: isDarkMode,
                    ),
                  ),
                  Expanded(
                    child: _buildRequestDetails(context, selectedRequest),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildRequestDetails(BuildContext context, RequestDetails request) {
    return Selector<InspectorController, _SearchState>(
      selector: (_, controller) => _SearchState(
        isTreeView: controller.isTreeView,
        isDarkMode: controller.isDarkMode,
        searchQuery: controller.searchQuery,
        expandChildren: controller.expandChildren,
      ),
      builder: (context, state, _) {
        final query = state.searchQuery;

        // Single source of truth for per-section match counts and offsets,
        // shared with [InspectorController] so the highlighted matches, the
        // reserved offsets and the total count can never drift apart. Only the
        // sections actually rendered below are counted (e.g. the raw request
        // body is not counted when a GraphQL query is shown in its place).
        final scanner = RequestSearchScanner(
          request: request,
          query: query,
          isTreeView: state.isTreeView,
        );

        final timeAndUrlOffset = scanner.timeAndUrlOffset;
        final headersOffset = scanner.headersOffset;
        final queryParamsOffset = scanner.queryParamsOffset;
        final graphqlQueryOffset = scanner.graphqlQueryOffset;
        final requestBodyOffset = scanner.requestBodyOffset;
        final graphqlVarsOffset = scanner.graphqlVarsOffset;
        final responseBodyOffset = scanner.responseBodyOffset;

        final graphqlInfo = GraphQLHelper.parse(request.requestBody);
        final graphqlQuery = graphqlInfo?.query ?? '';

        return Selector<InspectorController, int>(
          selector: (_, controller) => controller.currentMatchIndex,
          // [currentMatchIndex] is still observed so the list rebuilds while
          // navigating; the active match's scroll/orange highlight is handled
          // by the inner widgets themselves.
          builder: (context, currentMatchIndex, _) {
            // A section is expanded whenever it contains any match for the
            // current query, so the highlighted text inside it (including the
            // Response Body) is actually rendered. A collapsed [ExpansionTile]
            // builds none of its children, so before this nothing inside a
            // collapsed section could ever be highlighted.
            final timeAndUrlHasMatches = scanner.timeAndUrlCount > 0;
            final headersHasMatches = scanner.headersCount > 0;
            final queryParamsHasMatches = scanner.queryParamsCount > 0;
            final graphqlQueryHasMatches = scanner.graphqlQueryCount > 0;
            final requestBodyHasMatches = scanner.requestBodyCount > 0;
            final graphqlVarsHasMatches = scanner.graphqlVarsCount > 0;
            final responseBodyHasMatches = scanner.responseBodyCount > 0;

            return ListView(
              padding:
                  const EdgeInsets.only(left: 12.0, right: 12.0, bottom: 96.0),
              children: [
                _buildExpandableSection(
                  context: context,
                  txtCopy: JsonPrettyConverter().convert(graphqlInfo == null
                      ? request.url
                      : graphqlInfo.operationName),
                  titleWidget: _buildRequestNameAndStatus(
                    method: request.requestMethod,
                    requestName: request.requestName,
                    statusCode: request.statusCode,
                  ),
                  forceExpanded: timeAndUrlHasMatches,
                  children: [
                    _buildRequestSentTimeAndDuration(
                      request.sentTime,
                      request.receivedTime,
                      request.url,
                      searchQuery: query,
                      isDarkMode: state.isDarkMode,
                      matchIndexOffset: timeAndUrlOffset,
                    ),
                  ],
                ),
                if (_hasData(request.headers))
                  _buildExpandableSection(
                    context: context,
                    txtCopy: JsonPrettyConverter().convert(request.headers),
                    title: 'Headers',
                    forceExpanded: headersHasMatches,
                    children: _buildDataBlock(
                      request.headers,
                      isTreeView: state.isTreeView,
                      isDarkMode: state.isDarkMode,
                      searchQuery: query,
                      matchIndexOffset: headersOffset,
                      expandChildren: state.expandChildren || headersHasMatches,
                    ),
                  ),
                if (_hasData(request.queryParameters))
                  _buildExpandableSection(
                    context: context,
                    txtCopy:
                        JsonPrettyConverter().convert(request.queryParameters),
                    title: 'Query Parameters',
                    forceExpanded: queryParamsHasMatches,
                    children: _buildDataBlock(
                      request.queryParameters,
                      isTreeView: state.isTreeView,
                      isDarkMode: state.isDarkMode,
                      searchQuery: query,
                      matchIndexOffset: queryParamsOffset,
                      expandChildren:
                          state.expandChildren || queryParamsHasMatches,
                    ),
                  ),
                if (graphqlInfo != null)
                  _buildExpandableSection(
                    context: context,
                    txtCopy: graphqlQuery,
                    title: 'GraphQL Query',
                    forceExpanded: graphqlQueryHasMatches,
                    children: _buildGraphqlQueryBlock(
                      graphqlQuery,
                      isTreeView: state.isTreeView,
                      isDarkMode: state.isDarkMode,
                      searchQuery: query,
                      matchIndexOffset: graphqlQueryOffset,
                      expandChildren:
                          state.expandChildren || graphqlQueryHasMatches,
                    ),
                  ),
                if (graphqlInfo == null && _hasData(request.requestBody))
                  _buildExpandableSection(
                    context: context,
                    txtCopy: JsonPrettyConverter().convert(request.requestBody),
                    title:
                        'Request Body${request.requestBody is FormData ? " (Form Data)" : ""}',
                    forceExpanded: requestBodyHasMatches,
                    children: _buildDataBlock(
                      request.requestBody,
                      isTreeView: state.isTreeView,
                      isDarkMode: state.isDarkMode,
                      searchQuery: query,
                      matchIndexOffset: requestBodyOffset,
                      expandChildren:
                          state.expandChildren || requestBodyHasMatches,
                    ),
                  ),
                if (_hasData(request.graphqlRequestVars))
                  _buildExpandableSection(
                    context: context,
                    txtCopy: JsonPrettyConverter()
                        .convert(request.graphqlRequestVars),
                    title: 'GraphQL Request Vars',
                    forceExpanded: graphqlVarsHasMatches,
                    children: _buildDataBlock(
                      request.graphqlRequestVars,
                      isTreeView: state.isTreeView,
                      isDarkMode: state.isDarkMode,
                      searchQuery: query,
                      matchIndexOffset: graphqlVarsOffset,
                      expandChildren:
                          state.expandChildren || graphqlVarsHasMatches,
                    ),
                  ),
                if (_hasData(request.responseBody))
                  _buildExpandableSection(
                    context: context,
                    txtCopy:
                        JsonPrettyConverter().convert(request.responseBody),
                    title: 'Response Body',
                    forceExpanded: responseBodyHasMatches,
                    children: _buildDataBlock(
                      request.responseBody,
                      isTreeView: state.isTreeView,
                      isDarkMode: state.isDarkMode,
                      searchQuery: query,
                      matchIndexOffset: responseBodyOffset,
                      expandChildren:
                          state.expandChildren || responseBodyHasMatches,
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }

  // ... (keeping other methods, updating _buildDataBlock below)

  Widget _buildExpandableSection({
    required BuildContext context,
    String? title,
    required String txtCopy,
    Widget? titleWidget,
    bool forceExpanded = false,
    required List<Widget> children,
  }) {
    final theme = Theme.of(context);
    final cardColor = theme.cardColor;
    final borderColor = theme.dividerColor;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: theme.shadowColor.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          type: MaterialType.transparency,
          child: Theme(
            data: theme.copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              key: ValueKey(
                  '${title}_${forceExpanded ? 'expanded' : 'collapsed'}'),
              initiallyExpanded: forceExpanded,
              tilePadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 10,
              ),
              childrenPadding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 8,
              ),
              expandedAlignment: Alignment.topLeft,
              title: Row(
                children: [
                  Expanded(
                    child: titleWidget ??
                        Text(
                          title ?? '',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                  ),
                  InkWell(
                    child: const Icon(Icons.copy, color: Colors.grey, size: 20),
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: txtCopy));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Copied to clipboard')),
                      );
                    },
                  ),
                ],
              ),
              children: [
                Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: children,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRequestSentTimeAndDuration(
    DateTime sentTime,
    DateTime? receivedTime,
    String url, {
    required String searchQuery,
    required bool isDarkMode,
    required int matchIndexOffset,
  }) {
    // Reuse the scanner's builder so the rendered text is identical to the text
    // its match count was computed from (keeping the offsets aligned).
    final text = RequestSearchScanner.buildTimeAndUrlText(
      sentTime: sentTime,
      receivedTime: receivedTime,
      url: url,
    );

    return Padding(
      padding: const EdgeInsets.all(6.0),
      child: HighlightedText(
        text: text,
        searchQuery: searchQuery,
        isDarkMode: isDarkMode,
        matchIndexOffset: matchIndexOffset,
        style: const TextStyle(fontSize: 16.0),
      ),
    );
  }

  bool _hasData(dynamic data) {
    if (data == null) return false;
    if (data is Map) return data.isNotEmpty;
    if (data is List) return data.isNotEmpty;
    if (data is String) return data.trim().isNotEmpty;
    return true;
  }

  List<Widget> _buildGraphqlQueryBlock(
    String query, {
    required bool isTreeView,
    required bool isDarkMode,
    required String searchQuery,
    required int matchIndexOffset,
    required bool expandChildren,
  }) {
    if (query.trim().isEmpty) return [];

    // In tree mode, render the GraphQL document as a collapsible tree (like
    // [JsonTreeView]) so its selection sets can be expanded/collapsed. A GraphQL
    // document is not JSON, so it has its own dedicated tree widget.
    if (isTreeView) {
      return [
        GraphqlTreeView(
          query,
          isDarkMode: isDarkMode,
          searchQuery: searchQuery,
          matchIndexOffset: matchIndexOffset,
          expandChildren: expandChildren,
        ),
      ];
    }

    // Otherwise it is rendered as plain (line-by-line) highlighted text.
    final lines = query.split('\n');
    final children = <Widget>[];
    var currentOffset = matchIndexOffset;

    for (final line in lines) {
      final matchesCount =
          SearchHelper.findMatches(text: line, query: searchQuery).length;

      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 1.0),
          child: HighlightedText(
            text: line,
            searchQuery: searchQuery,
            isDarkMode: isDarkMode,
            matchIndexOffset: currentOffset,
          ),
        ),
      );

      currentOffset += matchesCount;
    }

    return [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    ];
  }

  List<Widget> _buildDataBlock(
    dynamic data, {
    required bool isTreeView,
    required bool isDarkMode,
    required String searchQuery,
    required int matchIndexOffset,
    required bool expandChildren,
  }) {
    if (data == null) return [];

    if ((data is Map || data is String || data is List) && data.isEmpty) {
      return [];
    }

    return [
      isTreeView
          ? JsonTreeView(
              data,
              isDarkMode: isDarkMode,
              searchQuery: searchQuery,
              matchIndexOffset: matchIndexOffset,
              expandChildren: expandChildren,
            )
          : _buildSelectableText(
              data,
              searchQuery: searchQuery,
              isDarkMode: isDarkMode,
              matchIndexOffset: matchIndexOffset,
            ),
    ];
  }

  Widget _buildSelectableText(
    dynamic text, {
    required String searchQuery,
    required bool isDarkMode,
    required int matchIndexOffset,
  }) {
    final prettyprint = JsonPrettyConverter().convert(text);
    final lines = prettyprint.split('\n');

    if (lines.isEmpty) return const SizedBox();

    // If only one line, return as before (optimization)
    if (lines.length == 1) {
      return Padding(
        padding: const EdgeInsets.all(6.0),
        child: HighlightedText(
          text: prettyprint,
          searchQuery: searchQuery,
          isDarkMode: isDarkMode,
          matchIndexOffset: matchIndexOffset,
        ),
      );
    }

    // If multiple lines, build a specific widget for each line so we can scroll to them
    final children = <Widget>[];
    var currentOffset = matchIndexOffset;

    for (final line in lines) {
      final matchesCount =
          SearchHelper.findMatches(text: line, query: searchQuery).length;

      children.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 1.0),
          child: HighlightedText(
            text: line,
            searchQuery: searchQuery,
            isDarkMode: isDarkMode,
            matchIndexOffset: currentOffset,
          ),
        ),
      );

      currentOffset += matchesCount;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _buildRequestNameAndStatus({
    required RequestMethod method,
    required String requestName,
    required int? statusCode,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${method.name} - $requestName',
          style: const TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4.0),
        Text(
          'Status: ${statusCode ?? 'N/A'}',
          style: TextStyle(
            fontSize: 14.0,
            color: InspectorHelper.specifyStatusCodeColor(statusCode),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
