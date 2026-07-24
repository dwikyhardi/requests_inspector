import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:requests_inspector_plus/requests_inspector_plus.dart';
import 'package:requests_inspector_plus/src/helpers/graphql_helper.dart';

void main() {
  group('GraphQLHelper', () {
    test('extracts query and operation name from multipart FormData', () {
      final formData = FormData.fromMap({
        'operations':
            '{"operationName":"UploadTransactionAttachment","variables":{"file":null,"transactionId":"10de1519"},"query":"mutation UploadTransactionAttachment(\$file: Upload!, \$transactionId: UUID!) {\\n  uploadTransactionAttachment(file: \$file, transactionId: \$transactionId) {\\n    status\\n  }\\n}"}',
        'map': '{"0":["variables.file"]}',
      });

      final info = GraphQLHelper.parse(formData);

      expect(info, isNotNull);
      expect(info!.operationName, 'UploadTransactionAttachment');
      expect(info.query, contains('mutation UploadTransactionAttachment'));
      // Newlines should be decoded from the JSON escape sequences.
      expect(info.query, contains('\n'));
    });

    test('extracts from a JSON map body', () {
      final info = GraphQLHelper.parse({
        'operationName': 'GetUser',
        'query': 'query GetUser { user { id } }',
        'variables': {},
      });

      expect(info, isNotNull);
      expect(info!.operationName, 'GetUser');
      expect(info.query, 'query GetUser { user { id } }');
    });

    test('extracts operation name from raw query string', () {
      final info = GraphQLHelper.parse('mutation DoThing { doThing { ok } }');

      expect(info, isNotNull);
      expect(info!.operationName, 'DoThing');
    });

    test('decodes a JSON-encoded (quoted) query inside a map body', () {
      final info = GraphQLHelper.parse({
        'operationName': 'CurrentSession',
        // The query arrives double-encoded as a JSON string literal, carrying
        // surrounding quotes and escaped newlines.
        'query':
            '"query CurrentSession {\\n  currentSession {\\n    id\\n  }\\n}"',
      });

      expect(info, isNotNull);
      expect(info!.query, startsWith('query CurrentSession'));
      // No leading/trailing quotes should remain.
      expect(info.query.startsWith('"'), isFalse);
      expect(info.query.endsWith('"'), isFalse);
      // Escaped newlines should be decoded into real line breaks.
      expect(info.query, contains('\n'));
    });

    test('decodes a JSON-encoded (quoted) raw query string body', () {
      final info = GraphQLHelper.parse(
        '"query CurrentSession {\\n  currentSession {\\n    id\\n  }\\n}"',
      );

      expect(info, isNotNull);
      expect(info!.query, startsWith('query CurrentSession'));
      expect(info.query.startsWith('"'), isFalse);
      expect(info.operationName, 'CurrentSession');
    });

    test('returns null for non-GraphQL bodies', () {
      expect(GraphQLHelper.parse(null), isNull);
      expect(GraphQLHelper.parse({'name': 'john'}), isNull);
      expect(GraphQLHelper.parse('just a plain string'), isNull);
    });

    test('RequestDetails uses GraphQL operation name as fallback', () {
      final formData = FormData.fromMap({
        'operations':
            '{"operationName":"UploadTransactionAttachment","variables":{},"query":"mutation UploadTransactionAttachment { ok }"}',
      });

      final request = RequestDetails(
        requestMethod: RequestMethod.POST,
        url: 'https://api.example.com/graphql',
        requestBody: formData,
      );

      expect(request.requestName, 'UploadTransactionAttachment');
    });
  });
}
