import 'dart:convert';

import 'package:requests_inspector/src/enums/requests_methods.dart';
import 'package:requests_inspector/src/helpers/graphql_helper.dart';
import 'package:requests_inspector/src/request_details.dart';

abstract class RequestFilter {
  bool Function(RequestDetails requestDetails) get requestFilter;
}

class RequestMethodFilter implements RequestFilter {
  const RequestMethodFilter(this.requestMethod);

  final RequestMethod requestMethod;

  @override
  bool Function(RequestDetails requestDetails) get requestFilter =>
      (requestDetails) => requestDetails.requestMethod == requestMethod;
}

class RequestUrlFilter implements RequestFilter {
  const RequestUrlFilter(this.url);

  final String url;

  @override
  bool Function(RequestDetails requestDetails) get requestFilter =>
      (requestDetails) => requestDetails.url
          .trim()
          .toLowerCase()
          .contains(url.trim().toLowerCase());
}

/// Matches a request against a free-text [query] across the fields a user can
/// reasonably search for in the requests list.
///
/// Searching only the URL is misleading for GraphQL APIs, where every
/// operation is usually sent to the same endpoint (e.g. `/graphql`). This
/// filter therefore also matches the request name (the GraphQL operation name
/// when available) and the GraphQL query/mutation document itself, so typing a
/// query or mutation name finds the matching request.
class RequestSearchFilter implements RequestFilter {
  const RequestSearchFilter(this.query);

  final String query;

  @override
  bool Function(RequestDetails requestDetails) get requestFilter =>
      (requestDetails) {
        final normalizedQuery = query.trim().toLowerCase();
        if (normalizedQuery.isEmpty) return true;

        final haystacks = <String?>[
          requestDetails.url,
          requestDetails.requestName,
          GraphQLHelper.extractQuery(requestDetails.requestBody),
          jsonEncode(requestDetails.responseBody),
        ];

        return haystacks.any((value) =>
            value != null && value.toLowerCase().contains(normalizedQuery));
      };
}

class RequestStatusCodeFilter implements RequestFilter {
  const RequestStatusCodeFilter(this.statusCode);

  final int statusCode;

  @override
  bool Function(RequestDetails requestDetails) get requestFilter =>
      (requestDetails) => requestDetails.statusCode == statusCode;
}
