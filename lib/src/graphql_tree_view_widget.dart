import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'helpers/search_helper.dart';
import 'inspector_controller.dart';
import 'shared_widgets/highlighted_text.dart';

/// Renders a GraphQL query/mutation document as a collapsible tree, mirroring
/// the look and feel of [JsonTreeView].
///
/// A GraphQL document is not JSON, so it cannot be handled by [JsonTreeView].
/// This widget parses the document's `{ ... }` selection sets into a tree where
/// every block (operation, field with a selection set, fragment, inline
/// fragment) becomes an expandable/collapsible node and every scalar field
/// becomes a leaf.
class GraphqlTreeView extends StatelessWidget {
  final String data;
  final bool _isDarkMode;
  final String searchQuery;
  final int matchIndexOffset;
  final bool _expandChildren;

  const GraphqlTreeView(
    this.data, {
    super.key,
    required bool isDarkMode,
    this.searchQuery = '',
    this.matchIndexOffset = 0,
    bool expandChildren = true,
  })  : _isDarkMode = isDarkMode,
        _expandChildren = expandChildren;

  /// Produces the linearized text used to count search matches for this widget.
  ///
  /// It must stay in sync with how the tree assigns match offsets so that the
  /// total match count reserved by the parent equals the sum consumed by the
  /// rendered nodes.
  static String flatten(String query) {
    final nodes = _parse(query);
    final lines = <String>[];

    void walk(_GqlNode node) {
      if (!node.isBlock) {
        lines.add(node.header);
        return;
      }
      lines.add(node.openLineText);
      for (final child in node.children!) {
        walk(child);
      }
      lines.add('}');
    }

    for (final node in nodes) {
      walk(node);
    }
    return lines.join('\n');
  }

  @override
  Widget build(BuildContext context) {
    final nodes = _parse(data);

    var offset = matchIndexOffset;
    for (final node in nodes) {
      offset = _assignOffsets(node, offset);
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final node in nodes) _buildNode(node, isRoot: true),
        ],
      ),
    );
  }

  int _assignOffsets(_GqlNode node, int offset) {
    if (!node.isBlock) {
      node.headerOffset = offset;
      node.headerMatches =
          SearchHelper.findMatches(text: node.header, query: searchQuery)
              .length;
      node.subtreeMatches = node.headerMatches;
      return offset + node.headerMatches;
    }

    final start = offset;
    node.headerOffset = offset;
    node.headerMatches =
        SearchHelper.findMatches(text: node.openLineText, query: searchQuery)
            .length;
    offset += node.headerMatches;

    for (final child in node.children!) {
      offset = _assignOffsets(child, offset);
    }

    node.closeOffset = offset;
    node.closeMatches =
        SearchHelper.findMatches(text: '}', query: searchQuery).length;
    offset += node.closeMatches;

    node.subtreeMatches = offset - start;
    return offset;
  }

  Widget _buildNode(_GqlNode node, {bool isRoot = false}) {
    if (!node.isBlock) {
      return Padding(
        padding: const EdgeInsets.only(left: 12.0),
        child: HighlightedText(
          text: node.header,
          searchQuery: searchQuery,
          isDarkMode: _isDarkMode,
          matchIndexOffset: node.headerOffset,
        ),
      );
    }

    return _GqlExpansionTile(
      titleString: node.header,
      collapsedCount: node.children!.length,
      initiallyExpanded: isRoot || _expandChildren,
      isDarkMode: _isDarkMode,
      matchIndexOffset: node.headerOffset,
      totalMatches: node.subtreeMatches,
      closeOffset: node.closeOffset,
      searchQuery: searchQuery,
      children: [
        for (final child in node.children!) _buildNode(child),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Parsing
  // ---------------------------------------------------------------------------

  static List<_GqlNode> _parse(String source) {
    final tokens = _tokenize(source);
    final parser = _Parser(tokens);
    return parser.parseDocument();
  }

  /// Splits [source] into `{`, `}`, and "word" tokens. Parentheses/brackets are
  /// kept glued to their preceding name (so `field(a: 1, b: 2)` is one token),
  /// while top-level whitespace and commas act as separators.
  static List<String> _tokenize(String source) {
    final tokens = <String>[];
    final buffer = StringBuffer();
    var depth = 0;

    void flush() {
      final value = buffer.toString().trim();
      if (value.isNotEmpty) tokens.add(value);
      buffer.clear();
    }

    for (var i = 0; i < source.length; i++) {
      final char = source[i];
      if (depth == 0) {
        if (char == '{' || char == '}') {
          flush();
          tokens.add(char);
        } else if (char == '(' || char == '[') {
          depth++;
          buffer.write(char);
        } else if (char == ',' ||
            char == ' ' ||
            char == '\n' ||
            char == '\t' ||
            char == '\r') {
          flush();
        } else {
          buffer.write(char);
        }
      } else {
        if (char == '(' || char == '[') depth++;
        if (char == ')' || char == ']') depth--;
        buffer.write(char);
      }
    }
    flush();
    return tokens;
  }
}

class _Parser {
  _Parser(this._tokens);

  final List<String> _tokens;
  var _pos = 0;

  /// Parses the top level of a document, where definitions
  /// (`query Name { ... }`, `fragment X on Y { ... }`, shorthand `{ ... }`)
  /// carry multi-word headers.
  List<_GqlNode> parseDocument() {
    final nodes = <_GqlNode>[];
    final pendingWords = <String>[];

    while (_pos < _tokens.length) {
      final token = _tokens[_pos];
      if (token == '{') {
        _pos++;
        final children = _parseSelectionSet();
        nodes.add(_GqlNode(pendingWords.join(' '), children));
        pendingWords.clear();
      } else if (token == '}') {
        _pos++;
      } else {
        pendingWords.add(token);
        _pos++;
      }
    }

    for (final word in pendingWords) {
      nodes.add(_GqlNode(word));
    }
    return nodes;
  }

  /// Parses a selection set (the content between a matching pair of braces).
  /// Each selection is a single field; a trailing `{` turns the preceding
  /// field (or `... on Type` inline fragment) into a collapsible block.
  List<_GqlNode> _parseSelectionSet() {
    final nodes = <_GqlNode>[];

    while (_pos < _tokens.length) {
      final token = _tokens[_pos];
      if (token == '}') {
        _pos++;
        break;
      }
      if (token == '{') {
        _pos++;
        final children = _parseSelectionSet();
        final header = _takeHeaderFor(nodes);
        nodes.add(_GqlNode(header, children));
        continue;
      }
      nodes.add(_GqlNode(token));
      _pos++;
    }
    return nodes;
  }

  /// Removes and joins the trailing leaf node(s) that form the header for a
  /// block. Handles the simple `fieldName` case as well as the
  /// `... on TypeName` inline-fragment case.
  String _takeHeaderFor(List<_GqlNode> nodes) {
    if (nodes.isEmpty || nodes.last.isBlock) return '';

    var header = nodes.removeLast().header;

    if (nodes.length >= 2 &&
        !nodes[nodes.length - 1].isBlock &&
        nodes[nodes.length - 1].header == 'on' &&
        !nodes[nodes.length - 2].isBlock &&
        nodes[nodes.length - 2].header == '...') {
      final on = nodes.removeLast().header;
      final spread = nodes.removeLast().header;
      header = '$spread $on $header';
    }
    return header;
  }
}

class _GqlNode {
  _GqlNode(this.header, [this.children]);

  final String header;
  final List<_GqlNode>? children;

  int headerOffset = 0;
  int headerMatches = 0;
  int closeOffset = 0;
  int closeMatches = 0;
  int subtreeMatches = 0;

  bool get isBlock => children != null;

  String get openLineText => header.isEmpty ? '{' : '$header {';
}

class _GqlExpansionTile extends StatefulWidget {
  final String titleString;
  final List<Widget> children;
  final bool initiallyExpanded;
  final int collapsedCount;
  final bool isDarkMode;
  final String searchQuery;
  final int matchIndexOffset;
  final int totalMatches;
  final int closeOffset;

  const _GqlExpansionTile({
    required this.titleString,
    required this.children,
    required this.initiallyExpanded,
    required this.collapsedCount,
    required this.isDarkMode,
    required this.searchQuery,
    required this.matchIndexOffset,
    required this.totalMatches,
    required this.closeOffset,
  });

  @override
  State<_GqlExpansionTile> createState() => _GqlExpansionTileState();
}

class _GqlExpansionTileState extends State<_GqlExpansionTile> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  void didUpdateWidget(_GqlExpansionTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initiallyExpanded != widget.initiallyExpanded) {
      setState(() => _expanded = widget.initiallyExpanded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final textColor = widget.isDarkMode ? Colors.white : Colors.black87;
    final secondaryTextColor =
        widget.isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600;

    final hasTitle = widget.titleString.isNotEmpty;

    return Selector<InspectorController, int>(
      selector: (_, controller) => controller.currentMatchIndex,
      builder: (context, currentMatchIndex, _) {
        final isActive = currentMatchIndex >= widget.matchIndexOffset &&
            currentMatchIndex < widget.matchIndexOffset + widget.totalMatches;

        if (isActive && !_expanded) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() => _expanded = true);
            }
          });
        }

        return Padding(
          padding: const EdgeInsets.only(left: 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                borderRadius: BorderRadius.circular(4),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedRotation(
                        turns: _expanded ? 0.25 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          Icons.arrow_right,
                          size: 16,
                          color: secondaryTextColor,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        fit: FlexFit.loose,
                        child: Text.rich(
                          TextSpan(
                            children: [
                              if (hasTitle)
                                TextSpan(
                                  text: '${widget.titleString} ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
                                    color: textColor,
                                  ),
                                ),
                              if (_expanded)
                                TextSpan(
                                  text: '{',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 14,
                                    color: textColor,
                                  ),
                                )
                              else
                                TextSpan(
                                  children: [
                                    TextSpan(
                                      text: '{',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: textColor,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    TextSpan(
                                      text: widget.collapsedCount.toString(),
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: secondaryTextColor,
                                      ),
                                    ),
                                    TextSpan(
                                      text: '}',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: textColor,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_expanded)
                Padding(
                  padding: const EdgeInsets.only(left: 12.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: widget.children,
                  ),
                ),
              if (_expanded)
                Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: HighlightedText(
                    text: '}',
                    searchQuery: widget.searchQuery,
                    isDarkMode: widget.isDarkMode,
                    matchIndexOffset: widget.closeOffset,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: textColor,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
