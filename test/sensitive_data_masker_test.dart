import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:requests_inspector_plus/requests_inspector_plus.dart';

void main() {
  group('SensitiveDataMasker', () {
    test('masks matching top-level keys (case-insensitive)', () {
      final masker = SensitiveDataMasker(maskedKeys: {'authorization'});

      final masked = masker.mask({
        'Authorization': 'Bearer secret-token',
        'Accept': 'application/json',
      });

      expect(masked['Authorization'], '***');
      expect(masked['Accept'], 'application/json');
    });

    test('masks nested keys inside maps and lists', () {
      final masker = SensitiveDataMasker(maskedKeys: {'password', 'token'});

      final masked = masker.mask({
        'data': {
          'user': {'name': 'john', 'password': 'p4ss'},
          'sessions': [
            {'id': 1, 'token': 'aaa'},
            {'id': 2, 'token': 'bbb'},
          ],
        },
      });

      expect(masked['data']['user']['name'], 'john');
      expect(masked['data']['user']['password'], '***');
      expect(masked['data']['sessions'][0]['token'], '***');
      expect(masked['data']['sessions'][1]['token'], '***');
      expect(masked['data']['sessions'][0]['id'], 1);
    });

    test('replaces the whole value when a collection-valued key matches', () {
      final masker = SensitiveDataMasker(maskedKeys: {'secret'});

      final masked = masker.mask({
        'secret': {'a': 1, 'b': 2},
      });

      expect(masked['secret'], '***');
    });

    test('masks secrets embedded in a JSON string value', () {
      final masker = SensitiveDataMasker(maskedKeys: {'new_mobile'});

      final masked = masker.mask({
        'metadata': '{"rt":"002","new_mobile":"+62851"}',
      });

      final decoded = jsonDecode(masked['metadata']) as Map<String, dynamic>;
      expect(decoded['rt'], '002');
      expect(decoded['new_mobile'], '***');
    });

    test('does not mutate the original data', () {
      final masker = SensitiveDataMasker(maskedKeys: {'token'});
      final original = {
        'token': 'real-token',
        'nested': {'token': 'real-nested'},
      };

      masker.mask(original);

      expect(original['token'], 'real-token');
      expect((original['nested'] as Map)['token'], 'real-nested');
    });

    test('uses a custom maskValueBuilder when provided', () {
      final masker = SensitiveDataMasker(
        maskedKeys: {'token'},
        maskValueBuilder: (key, value) => '<redacted $key>',
      );

      final masked = masker.mask({'token': 'abc'});

      expect(masked['token'], '<redacted token>');
    });

    test('leaves FormData untouched', () {
      final masker = SensitiveDataMasker(maskedKeys: {'token'});
      final formData = FormData.fromMap({'token': 'abc'});

      final masked = masker.mask(formData);

      expect(identical(masked, formData), isTrue);
    });

    test('disabled masker (empty keys) returns data unchanged', () {
      final masker = SensitiveDataMasker(maskedKeys: <String>{});
      final data = {'token': 'abc'};

      final masked = masker.mask(data);

      expect(identical(masked, data), isTrue);
      expect(masker.isEnabled, isFalse);
    });
  });
}
