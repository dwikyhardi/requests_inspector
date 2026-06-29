import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../requests_inspector_plus.dart';
import 'helpers/graphql_helper.dart';

/// Dio interceptor that feeds every request/response into the
/// [InspectorController] backing the inspector UI.
///
/// On top of the basic capture it offers two opt-in capabilities (both default
/// to the previous behaviour when their parameters are omitted):
///
/// * **Runtime gating** — pass an [isEnabled] [ValueListenable] to toggle
///   capture on/off at runtime (e.g. a developer-options switch). While it is
///   `false` nothing is recorded and the request/response stoppers are skipped,
///   so the interceptor adds no overhead until it is turned on. When omitted,
///   capture is always on (legacy behaviour).
/// * **Sensitive-data masking** — pass a [SensitiveDataMasker] to redact secret
///   values (tokens, passwords, cookies, ...) from the headers, query
///   parameters, request body, GraphQL variables and response body **before**
///   they are stored for display. Masking is applied only to the logged copy;
///   the real outgoing request and the live response are never altered.
///
/// GraphQL POSTs are additionally labelled by their `operationName`, with the
/// variables surfaced in their own section (parity with the GraphQL link).
class RequestsInspectorInterceptor extends Interceptor {
  RequestsInspectorInterceptor({
    ValueListenable<bool>? isEnabled,
    SensitiveDataMasker? masker,
  })
      : _isEnabled = isEnabled,
        _masker = masker;

  static const String _startTimeKey = 'startTime';

  /// Optional runtime toggle. When `null`, capture is always enabled.
  final ValueListenable<bool>? _isEnabled;

  /// Optional masker applied to the recorded (logged) data only.
  final SensitiveDataMasker? _masker;

  bool get _isCapturingEnabled => _isEnabled?.value ?? true;

  @override
  Future<void> onRequest(RequestOptions options,
      RequestInterceptorHandler handler,) async {
    options.extra[_startTimeKey] = DateTime.now();

    if (!_isCapturingEnabled || !InspectorController().requestStopperEnabled)
      return super.onRequest(options, handler);

    final requestDetails = _convertToRequestDetails(options);
    final newRequestDetails = await InspectorController().editRequest(
      requestDetails,
    );

    if (newRequestDetails == null) return super.onRequest(options, handler);

    final newOptions = _copyRequestToNewOptions(options, newRequestDetails);
    return super.onRequest(newOptions, handler);
  }

  @override
  Future<void> onResponse(Response response,
      ResponseInterceptorHandler handler,) async {
    final dateTime = DateTime.now();

    if (_isCapturingEnabled && InspectorController().responseStopperEnabled) {
      final url = _extractUrl(response.requestOptions).key;
      final oldResponseData = ResponseDetails(
        url: url,
        statusCode: response.statusCode ?? 0,
        headers: response.headers.map,
        responseBody: response.data,
      );

      final newResponseData = await InspectorController().editResponse(
        oldResponseData,
      );

      if (newResponseData != null) {
        response.data = newResponseData.responseBody;
        response.statusCode = newResponseData.statusCode;
        // Update headers if they were modified
        if (newResponseData.headers != null) {
          response.headers.clear();
          if (newResponseData.headers is Map) {
            (newResponseData.headers as Map).forEach((key, value) {
              response.headers.add(key.toString(), value.toString());
            });
          }
        }
      }
    }

    _record(
      options: response.requestOptions,
      statusCode: response.statusCode ?? 0,
      responseBody: response.data,
      receivedTime: dateTime,
    );
    super.onResponse(response, handler);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    _record(
      options: err.requestOptions,
      statusCode: err.response?.statusCode ?? 0,
      responseBody: err.response?.data ?? err.message,
      receivedTime: DateTime.now(),
    );
    super.onError(err, handler);
  }

  /// Builds and records a [RequestDetails] for a finished exchange, applying
  /// the optional masker to every logged field. Skipped entirely while capture
  /// is gated off.
  void _record({
    required RequestOptions options,
    required int statusCode,
    required dynamic responseBody,
    required DateTime receivedTime,
  }) {
    if (!_isCapturingEnabled) return;

    final graphql = GraphQLHelper.parse(options.data);
    final urlAndQueryParMapEntry = _extractUrl(options);
    InspectorController().addNewRequest(
      RequestDetails(
        requestName: graphql?.operationName,
        requestMethod: _resolveMethod(options.method),
        url: urlAndQueryParMapEntry.key,
        statusCode: statusCode,
        headers: _mask(options.headers),
        queryParameters: _mask(urlAndQueryParMapEntry.value),
        requestBody: _mask(options.data),
        graphqlRequestVars: _mask(graphql?.variables),
        responseBody: _mask(responseBody),
        sentTime: options.extra[_startTimeKey] as DateTime? ?? DateTime.now(),
        receivedTime: receivedTime,
      ),
    );
  }

  /// Returns a masked copy of [data] when a masker is configured, otherwise the
  /// value unchanged. Masking never mutates the original structure.
  dynamic _mask(dynamic data) => _masker?.mask(data) ?? data;

  RequestMethod _resolveMethod(String method) =>
      RequestMethod.values.firstWhere(
            (e) => e.name == method.toUpperCase(),
        orElse: () => RequestMethod.GET,
      );

  MapEntry<String, Map<String, dynamic>> _extractUrl(
      RequestOptions requestOptions,) {
    final splitUri = requestOptions.uri.toString().split('?');
    final baseUrl = splitUri.first;
    final builtInQuery = splitUri.length > 1 ? splitUri.last : null;
    final buildInQueryParamsList = builtInQuery?.split('&').map((e) {
      final split = e.split('=');
      return MapEntry(split.first, split.length > 1 ? split.last : '');
    }).toList();
    final builtInQueryParams = buildInQueryParamsList == null
        ? null
        : Map.fromEntries(buildInQueryParamsList);
    final queryParameters = {
      ...?builtInQueryParams,
      ...requestOptions.queryParameters,
    };

    return MapEntry(baseUrl, queryParameters);
  }

  RequestDetails _convertToRequestDetails(RequestOptions options) =>
      RequestDetails(
        requestMethod: _resolveMethod(options.method),
        url: options.uri.toString(),
        headers: options.headers,
        queryParameters: options.queryParameters,
        requestBody: options.data,
        graphqlRequestVars: GraphQLHelper.extractVariables(options.data),
        sentTime: DateTime.now(),
      );

  RequestOptions _copyRequestToNewOptions(RequestOptions options,
      RequestDetails requestDetails,) =>
      options.copyWith(
        method: requestDetails.requestMethod.name,
        headers: requestDetails.headers,
        queryParameters: requestDetails.queryParameters,
        data: requestDetails.requestBody,
        path: requestDetails.url,
        extra: {...options.extra, _startTimeKey: DateTime.now()},
      );
}
