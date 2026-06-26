import 'dart:convert';

/// Signature for a custom masking callback.
///
/// Receives the matched [key] and its original [value] and returns the value
/// that should be logged in its place. Useful when a fixed placeholder is not
/// enough (e.g. keeping the last 4 digits of a card number).
typedef MaskValueBuilder = dynamic Function(String key, dynamic value);

/// Recursively masks sensitive values inside the data structures recorded by
/// the inspector (headers, query parameters, request body and response body).
///
/// Matching is done by **key name**, case-insensitively. Whenever a map entry
/// whose key is contained in [maskedKeys] is encountered, its value is replaced
/// by [placeholder] (or by the result of [maskValueBuilder] when provided).
///
/// The masker never mutates the original data: every map/list it touches is
/// rebuilt, so masking the logged copy can't corrupt the real outgoing request
/// or the live response.
///
/// [String] values are inspected too: when a string holds a JSON object/array
/// (e.g. a stringified request body, or a stringified `metadata` blob), it is
/// decoded, masked recursively and re-encoded so nested secrets are covered.
///
/// `FormData` and other unknown types are left untouched.
class SensitiveDataMasker {
  SensitiveDataMasker({
    Set<String>? maskedKeys,
    this.placeholder = '***',
    MaskValueBuilder? maskValueBuilder,
  })  : maskedKeys =
            (maskedKeys ?? defaultMaskedKeys).map((e) => e.toLowerCase()).toSet(),
        _maskValueBuilder = maskValueBuilder;

  /// A reasonable default set of sensitive key names to mask out of the box.
  static const Set<String> defaultMaskedKeys = {
    'authorization',
    'auth',
    'token',
    'access_token',
    'accesstoken',
    'refresh_token',
    'refreshtoken',
    'id_token',
    'static_token',
    'statictoken',
    'password',
    'pass',
    'pin',
    'secret',
    'client_secret',
    'clientsecret',
    'cookie',
    'set-cookie',
    'session',
    'api_key',
    'apikey',
    'x-api-key',
    'private_key',
    'privatekey',
  };

  /// The (lower-cased) set of key names whose values are masked.
  final Set<String> maskedKeys;

  /// The value substituted for a masked entry when no [maskValueBuilder] is set.
  final String placeholder;

  final MaskValueBuilder? _maskValueBuilder;

  /// Whether this masker would actually change anything.
  bool get isEnabled => maskedKeys.isNotEmpty;

  /// Returns a masked copy of [data], leaving the original untouched.
  dynamic mask(dynamic data) {
    if (!isEnabled) return data;
    return _maskValue(null, data);
  }

  dynamic _maskValue(String? key, dynamic value) {
    if (key != null && maskedKeys.contains(key.toLowerCase())) {
      return _maskValueBuilder?.call(key, value) ?? placeholder;
    }

    if (value is Map) {
      return value.map(
        (k, v) => MapEntry(k, _maskValue(k?.toString(), v)),
      );
    }

    if (value is List) {
      // List items are not addressed by the parent key, so mask each element
      // on its own merits (a matched parent key would already have replaced the
      // whole list above).
      return value.map((e) => _maskValue(null, e)).toList();
    }

    if (value is String) {
      final decoded = _tryDecodeJson(value);
      if (decoded is Map || decoded is List) {
        return jsonEncode(_maskValue(null, decoded));
      }
    }

    return value;
  }

  static dynamic _tryDecodeJson(String value) {
    final trimmed = value.trimLeft();
    if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) return null;
    try {
      return jsonDecode(value);
    } catch (_) {
      return null;
    }
  }
}
