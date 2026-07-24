import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'shared_widgets/highlighted_text.dart';
import 'helpers/search_helper.dart';
import 'inspector_controller.dart';
import 'package:provider/provider.dart';

class JsonTreeView extends StatelessWidget {
  final dynamic data;
  final bool _isDarkMode;
  final String searchQuery;
  final int matchIndexOffset;
  final bool _expandChildren;

  const JsonTreeView(
    this.data, {
    super.key,
    required bool isDarkMode,
    this.searchQuery = '',
    this.matchIndexOffset = 0,
    bool expandChildren = true,
  })  : _isDarkMode = isDarkMode,
        _expandChildren = expandChildren;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: _buildNode(
          context,
          data,
          currentOffset: matchIndexOffset,
          isRoot: true,
        ),
      ),
    );
  }

  Widget _buildNode(
    BuildContext context,
    dynamic node, {
    String? keyName,
    required int currentOffset,
    bool isRoot = false,
  }) {
    if (node is Map<String, dynamic>) {
      return _buildMapNode(
        context,
        node,
        keyName,
        currentOffset,
        isRoot: isRoot,
      );
    } else if (node is List) {
      return _buildListNode(
        context,
        node,
        keyName,
        currentOffset,
        isRoot: isRoot,
      );
    } else if (node is FormData) {
      return _buildFormDataNode(
        context,
        node,
        keyName,
        currentOffset,
        isRoot: isRoot,
      );
    } else {
      return _buildLeafNode(context, keyName, node, currentOffset);
    }
  }

  Widget _buildMapNode(
    BuildContext context,
    Map<String, dynamic> map,
    String? keyName,
    int currentOffset, {
    bool isRoot = false,
  }) {
    if (map.isEmpty) {
      return _buildLeafNode(context, keyName, '{}', currentOffset);
    }

    final children = <Widget>[];
    // The node's own key (rendered in the title) takes the first match indices,
    // so children start after the title's matches.
    final titleCount = titleMatchCount(keyName, searchQuery);
    var offset = currentOffset + titleCount;

    for (final entry in map.entries) {
      children.add(_buildNode(context, entry.value,
          keyName: entry.key, currentOffset: offset));
      offset += _countMatchesInNode(entry.value, entry.key);
    }

    children.add(_buildClosingBracket(context, '} ,'));

    final totalMatches = _countMatchesInNode(map, keyName);

    return _CustomExpansionTile(
      titleString: _buildTitleString(keyName),
      children: children,
      collapsedCount: map.length,
      isObject: true,
      initiallyExpanded: isRoot || _expandChildren,
      isDarkMode: _isDarkMode,
      matchIndexOffset: currentOffset,
      totalMatches: totalMatches,
      searchQuery: searchQuery,
    );
  }

  Widget _buildListNode(
    BuildContext context,
    List list,
    String? keyName,
    int currentOffset, {
    bool isRoot = false,
  }) {
    if (list.isEmpty) {
      return _buildLeafNode(context, keyName, '[]', currentOffset);
    }

    final children = <Widget>[];
    final titleCount = titleMatchCount(keyName, searchQuery);
    var offset = currentOffset + titleCount;

    for (final item in list) {
      children.add(_buildNode(context, item, currentOffset: offset));
      offset += _countMatchesInNode(item, null);
    }

    children.add(_buildClosingBracket(context, '] ,'));

    final totalMatches = _countMatchesInNode(list, keyName);

    return _CustomExpansionTile(
      titleString: _buildTitleString(keyName),
      children: children,
      collapsedCount: list.length,
      isObject: false,
      initiallyExpanded: isRoot || _expandChildren,
      isDarkMode: _isDarkMode,
      matchIndexOffset: currentOffset,
      totalMatches: totalMatches,
      searchQuery: searchQuery,
    );
  }

  Widget _buildFormDataNode(
    BuildContext context,
    FormData formData,
    String? keyName,
    int currentOffset, {
    bool isRoot = false,
  }) {
    final length = formData.fields.length + formData.files.length;
    if (length == 0) {
      return _buildLeafNode(context, keyName, '{}', currentOffset);
    }

    final children = <Widget>[];
    final titleCount = titleMatchCount(keyName, searchQuery);
    var offset = currentOffset + titleCount;

    for (final field in formData.fields) {
      children.add(_buildNode(context, field.value,
          keyName: field.key, currentOffset: offset));
      offset += _countMatchesInNode(field.value, field.key);
    }

    for (final file in formData.files) {
      final sizeInMb = file.value.length ~/ 1024;
      final fileSizeString = '${sizeInMb.toStringAsFixed(1)} kb';
      final nodeValue = "($fileSizeString) - ${file.value.filename}";
      children.add(_buildNode(context, nodeValue,
          keyName: file.key, currentOffset: offset));
      offset += _countMatchesInNode(nodeValue, file.key);
    }

    children.add(_buildClosingBracket(context, '} ,'));

    final totalMatches = _countMatchesInNode(formData, keyName);

    return _CustomExpansionTile(
      titleString: _buildTitleString(keyName),
      children: children,
      collapsedCount: length,
      isObject: true,
      initiallyExpanded: isRoot || _expandChildren,
      isDarkMode: _isDarkMode,
      matchIndexOffset: currentOffset,
      totalMatches: totalMatches,
      searchQuery: searchQuery,
    );
  }

  int _countMatchesInNode(dynamic node, String? key) =>
      countMatches(node, searchQuery, key: key);

  /// Counts the search matches that this widget will actually render and
  /// highlight for [data] with the given [query].
  ///
  /// This must be used (instead of counting matches in pretty-printed JSON) by
  /// any code that reserves match-index offsets for a section rendered by
  /// [JsonTreeView]. The tree linearizes data into `"key" : value,` rows and
  /// renders non-`Map<String, dynamic>` values as a single leaf, so counting
  /// over pretty JSON would diverge from what is highlighted and desync the
  /// active-match navigation.
  static int countMatches(dynamic node, String query, {String? key}) {
    if (query.isEmpty) return 0;

    final isEmptyCollection = (node is Map<String, dynamic> && node.isEmpty) ||
        (node is List && node.isEmpty) ||
        (node is FormData && node.fields.isEmpty && node.files.isEmpty);

    if (node is Map<String, dynamic> && !isEmptyCollection) {
      // The node's own key is rendered (and highlighted) in the expansion-tile
      // title, so it must be counted here too, before its children.
      var count = titleMatchCount(key, query);
      for (final entry in node.entries) {
        count += countMatches(entry.value, query, key: entry.key);
      }
      return count;
    } else if (node is List && !isEmptyCollection) {
      var count = titleMatchCount(key, query);
      for (final item in node) {
        count += countMatches(item, query);
      }
      return count;
    } else if (node is FormData && !isEmptyCollection) {
      var count = titleMatchCount(key, query);
      for (final field in node.fields) {
        count += countMatches(field.value, query, key: field.key);
      }
      for (final file in node.files) {
        final sizeInMb = file.value.length ~/ 1024;
        final fileSizeString = '${sizeInMb.toStringAsFixed(1)} kb';
        final nodeValue = "($fileSizeString) - ${file.value.filename}";
        count += countMatches(nodeValue, query, key: file.key);
      }
      return count;
    } else {
      // Leaf, including empty collections which are rendered as '{}' / '[]'.
      final leafValue = isEmptyCollection ? (node is List ? '[]' : '{}') : node;
      final formattedValue =
          (leafValue is String && leafValue != '{}' && leafValue != '[]')
              ? '"$leafValue"'
              : '$leafValue';
      final fullText =
          '${key != null ? '"$key" : ' : ''}$formattedValue${key != null ? ',' : ''}';
      return SearchHelper.findMatches(text: fullText, query: query).length;
    }
  }

  /// The number of matches in an object/array node's rendered title prefix
  /// (`"key" : `). Kept identical to the title text built by
  /// [_buildTitleString] so the reserved offsets line up with the highlights.
  static int titleMatchCount(String? key, String query) => key == null
      ? 0
      : SearchHelper.findMatches(text: _buildTitleString(key), query: query)
          .length;

  static String _buildTitleString(String? key) =>
      key != null ? '"$key" : ' : '';

  Widget _buildLeafNode(
      BuildContext context, String? key, dynamic value, int currentOffset) {
    String formattedValue;
    Color valueColor;

    if (value is String && (value == '{}' || value == '[]')) {
      formattedValue = value;
      valueColor = _isDarkMode ? Colors.white : Colors.black87;
    } else if (value is String) {
      formattedValue = '"$value"';
      valueColor = _isDarkMode ? Colors.green.shade300 : Colors.green.shade700;
    } else if (value is num) {
      formattedValue = value.toString();
      valueColor = _isDarkMode ? Colors.blue.shade300 : Colors.blue.shade700;
    } else if (value is bool) {
      formattedValue = value.toString();
      valueColor =
          _isDarkMode ? Colors.orange.shade300 : Colors.orange.shade700;
    } else if (value == null) {
      formattedValue = 'null';
      valueColor = _isDarkMode ? Colors.grey.shade400 : Colors.grey.shade600;
    } else {
      formattedValue = value.toString();
      valueColor = _isDarkMode ? Colors.white : Colors.black87;
    }

    final spans = <TextSpan>[];
    if (key != null) {
      spans.add(TextSpan(
        text: '"$key" : ',
        style: TextStyle(
          fontSize: 14,
          color: _isDarkMode ? Colors.white : Colors.black87,
          fontWeight: FontWeight.w500,
        ),
      ));
    }

    spans.add(TextSpan(
      text: formattedValue,
      style: TextStyle(
        fontSize: 14,
        color: valueColor,
        fontWeight: FontWeight.w500,
      ),
    ));

    if (key != null) {
      spans.add(TextSpan(
        text: ',',
        style: TextStyle(
          fontSize: 14,
          color: _isDarkMode ? Colors.white : Colors.black87,
        ),
      ));
    }

    return Padding(
      padding: const EdgeInsets.only(left: 12.0),
      child: HighlightedText(
        spans: spans,
        searchQuery: searchQuery,
        isDarkMode: _isDarkMode,
        matchIndexOffset: currentOffset,
      ),
    );
  }

  Widget _buildClosingBracket(BuildContext context, String bracket) {
    return Padding(
      padding: const EdgeInsets.only(left: 8.0),
      // Consistent with general indentation
      child: Text(
        bracket,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: _isDarkMode ? Colors.white : Colors.black87,
        ),
      ),
    );
  }
}

class _CustomExpansionTile extends StatefulWidget {
  final String? titleString;
  final List<Widget> children;
  final bool initiallyExpanded;
  final int? collapsedCount;
  final bool isObject;
  final bool isDarkMode;

  final int matchIndexOffset;
  final int totalMatches;
  final String searchQuery;

  const _CustomExpansionTile({
    required this.titleString,
    required this.children,
    this.initiallyExpanded = false,
    this.collapsedCount,
    this.isObject = false,
    required this.isDarkMode,
    this.matchIndexOffset = 0,
    this.totalMatches = 0,
    this.searchQuery = '',
  });

  @override
  State<_CustomExpansionTile> createState() => _CustomExpansionTileState();
}

class _CustomExpansionTileState extends State<_CustomExpansionTile>
    with SingleTickerProviderStateMixin {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
  }

  @override
  void didUpdateWidget(_CustomExpansionTile oldWidget) {
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

    return Selector<InspectorController, int>(
      selector: (_, controller) => controller.currentMatchIndex,
      builder: (context, currentMatchIndex, _) {
        final isActive = currentMatchIndex >= widget.matchIndexOffset &&
            currentMatchIndex < widget.matchIndexOffset + widget.totalMatches;

        if (isActive && !_expanded) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _expanded = true;
              });
            }
          });
        }

        return Padding(
          padding: const EdgeInsets.only(left: 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              InkWell(
                onTap: () {
                  setState(() {
                    _expanded = !_expanded;
                  });
                },
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
                        child: _buildTitle(textColor, secondaryTextColor),
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
            ],
          ),
        );
      },
    );
  }

  Widget _buildTitle(Color textColor, Color secondaryTextColor) {
    final titleStyle = TextStyle(
      fontWeight: FontWeight.w500,
      fontSize: 14,
      color: textColor,
    );
    final hasTitleString =
        widget.titleString != null && widget.titleString!.isNotEmpty;

    final bracketSpans = <InlineSpan>[
      if (_expanded)
        TextSpan(text: widget.isObject ? '{' : '[', style: titleStyle)
      else ...[
        TextSpan(text: widget.isObject ? '{' : '[', style: titleStyle),
        if (widget.collapsedCount != null)
          TextSpan(
            text: widget.collapsedCount.toString(),
            style: TextStyle(fontSize: 14, color: secondaryTextColor),
          ),
        TextSpan(text: widget.isObject ? '} ,' : '] ,', style: titleStyle),
      ],
    ];

    // While searching, highlight the object/array key. It is rendered first so
    // its match indices line up with the offsets [JsonTreeView] reserves for
    // the title; the structural brackets/count are never searched.
    if (hasTitleString && widget.searchQuery.isNotEmpty) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Flexible(
            child: HighlightedText(
              text: widget.titleString,
              searchQuery: widget.searchQuery,
              isDarkMode: widget.isDarkMode,
              matchIndexOffset: widget.matchIndexOffset,
              style: titleStyle,
            ),
          ),
          Text.rich(TextSpan(children: bracketSpans)),
        ],
      );
    }

    return Text.rich(
      TextSpan(
        children: [
          if (hasTitleString)
            TextSpan(text: widget.titleString, style: titleStyle),
          ...bracketSpans,
        ],
      ),
    );
  }
}
