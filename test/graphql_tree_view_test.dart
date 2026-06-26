import 'package:flutter_test/flutter_test.dart';
import 'package:requests_inspector/src/graphql_tree_view_widget.dart';

void main() {
  group('GraphqlTreeView.flatten', () {
    test('keeps the operation header and nested field blocks', () {
      const query = '''
query CurrentSession {
  currentSession {
    pk
    id
    device {
      id
      deviceName
    }
    user {
      ...UserField
    }
  }
}''';

      final lines = GraphqlTreeView.flatten(query).split('\n');

      expect(lines, contains('query CurrentSession {'));
      expect(lines, contains('currentSession {'));
      expect(lines, contains('device {'));
      expect(lines, contains('user {'));
      // Scalar fields stay as standalone leaves.
      expect(lines, contains('pk'));
      expect(lines, contains('id'));
      expect(lines, contains('deviceName'));
      // Fragment spreads are leaves, not blocks.
      expect(lines, contains('...UserField'));
      // Every opened block is closed.
      final opens = lines.where((l) => l.endsWith('{')).length;
      final closes = lines.where((l) => l == '}').length;
      expect(opens, closes);
    });

    test('keeps a top-level fragment definition header', () {
      const query = '''
fragment UserField on UserType {
  id
  organization {
    id
    pk
  }
}''';

      final lines = GraphqlTreeView.flatten(query).split('\n');

      expect(lines, contains('fragment UserField on UserType {'));
      expect(lines, contains('organization {'));
      expect(lines, contains('id'));
    });

    test('keeps a field arguments list on the block header', () {
      const query = '''
mutation UploadTransactionAttachment(\$file: Upload!, \$transactionId: UUID!) {
  uploadTransactionAttachment(file: \$file, transactionId: \$transactionId) {
    status
  }
}''';

      final lines = GraphqlTreeView.flatten(query).split('\n');

      expect(
        lines,
        contains(
          'mutation UploadTransactionAttachment(\$file: Upload!, \$transactionId: UUID!) {',
        ),
      );
      expect(
        lines,
        contains(
          'uploadTransactionAttachment(file: \$file, transactionId: \$transactionId) {',
        ),
      );
      expect(lines, contains('status'));
    });

    test('handles an inline fragment (... on Type) as a block header', () {
      const query = '''
query Node {
  node {
    ... on User {
      id
    }
  }
}''';

      final lines = GraphqlTreeView.flatten(query).split('\n');

      expect(lines, contains('... on User {'));
      expect(lines, contains('id'));
    });

    test('returns empty string for an empty document', () {
      expect(GraphqlTreeView.flatten(''), '');
    });
  });
}
