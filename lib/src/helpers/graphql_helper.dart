import 'dart:convert';

import 'package:dio/dio.dart';

/// Holds the GraphQL query/mutation and its operation name extracted from a
/// request body.
class GraphQLRequestInfo {
  final String query;
  final String? operationName;
  final dynamic variables;

  const GraphQLRequestInfo({
    required this.query,
    this.operationName,
    this.variables,
  });
}

/// Detects and extracts GraphQL information from various request body shapes:
/// - A [FormData] holding an `operations` field (multipart GraphQL, e.g. file
///   uploads following the GraphQL multipart request spec).
/// - A [Map] body containing a `query` (and optionally `operationName`) entry.
/// - A [String] body that is either a JSON object with a `query` entry or a
///   raw GraphQL query/mutation/subscription document.
class GraphQLHelper {
  static final RegExp _operationNameRegExp =
      RegExp(r'(query|mutation|subscription)\s+([A-Za-z0-9_]+)');

  /// Returns the GraphQL info contained in [requestBody], or `null` when the
  /// body does not represent a GraphQL operation.
  static GraphQLRequestInfo? parse(dynamic requestBody) {
    if (requestBody == null) return null;

    if (requestBody is FormData) {
      return _parseFromFormData(requestBody);
    }

    if (requestBody is Map) {
      return _parseFromMap(requestBody);
    }

    if (requestBody is String) {
      return _parseFromString(requestBody);
    }

    return null;
  }

  /// Convenience accessor for the GraphQL query/mutation document.
  static String? extractQuery(dynamic requestBody) => parse(requestBody)?.query;

  /// Convenience accessor for the GraphQL operation name.
  static String? extractOperationName(dynamic requestBody) =>
      parse(requestBody)?.operationName;

  /// Convenience accessor for the GraphQL operation variables.
  static dynamic extractVariables(dynamic requestBody) =>
      parse(requestBody)?.variables;

  static GraphQLRequestInfo? _parseFromFormData(FormData formData) {
    for (final field in formData.fields) {
      if (field.key == 'operations') {
        return _parseFromJsonString(field.value);
      }
    }
    return null;
  }

  static GraphQLRequestInfo? _parseFromString(String value) {
    final trimmed = value.trimLeft();
    if (trimmed.startsWith('{') || trimmed.startsWith('[')) {
      final fromJson = _parseFromJsonString(value);
      if (fromJson != null) return fromJson;
    }

    // A query may arrive as a JSON-encoded string literal (wrapped in quotes
    // with escaped newlines), e.g. `"query CurrentSession {\n ... }"`.
    final unquoted = _decodeIfJsonString(value);
    if (_looksLikeGraphQLQuery(unquoted.trimLeft())) {
      return GraphQLRequestInfo(
        query: unquoted,
        operationName: _operationNameFromQuery(unquoted),
      );
    }

    return null;
  }

  static GraphQLRequestInfo? _parseFromJsonString(String jsonString) {
    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is Map) return _parseFromMap(decoded);
    } catch (_) {}
    return null;
  }

  static GraphQLRequestInfo? _parseFromMap(Map map) {
    final rawQuery = map['query'];
    if (rawQuery is! String || rawQuery.isEmpty) return null;

    // Guard against a query that was double-encoded as a JSON string literal
    // (carrying surrounding quotes and escaped newlines).
    final query = _decodeIfJsonString(rawQuery);
    if (query.isEmpty) return null;

    final operationName = map['operationName'];
    return GraphQLRequestInfo(
      query: query,
      operationName: operationName is String && operationName.isNotEmpty
          ? operationName
          : _operationNameFromQuery(query),
      variables: map['variables'],
    );
  }

  /// Decodes [value] when it is a JSON-encoded string literal (i.e. wrapped in
  /// double quotes), returning the unescaped string. Otherwise returns the
  /// original [value] unchanged.
  static String _decodeIfJsonString(String value) {
    final trimmed = value.trim();
    if (trimmed.length >= 2 &&
        trimmed.startsWith('"') &&
        trimmed.endsWith('"')) {
      try {
        final decoded = jsonDecode(trimmed);
        if (decoded is String) return decoded;
      } catch (_) {}
    }
    return value;
  }

  static bool _looksLikeGraphQLQuery(String value) =>
      value.startsWith('query') ||
      value.startsWith('mutation') ||
      value.startsWith('subscription') ||
      value.startsWith('fragment');

  static String? _operationNameFromQuery(String query) =>
      _operationNameRegExp.firstMatch(query)?.group(2);
}
