import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:requests_inspector_plus/src/shared_widgets/inspector.dart';
import '../requests_inspector_plus.dart';

///You can show the Inspector by **Shaking** your phone.
class RequestsInspector extends StatelessWidget {
  /// Pass your `navigatorKey` of your MaterialApp to enable Request & Response `Stopper` Dialogs.
  /// And if you don't want to use it, you can pass it as `null`.
  const RequestsInspector({
    super.key,
    bool enabled = true,
    bool hideInspectorBanner = false,
    ShowInspectorOn showInspectorOn = ShowInspectorOn.Both,
    required Widget child,
    bool defaultTreeViewEnabled = true,
    GlobalKey<NavigatorState>? navigatorKey,
    bool defaultExpandChildren = true,
    bool defaultIsDarkMode = true,
  })  : _enabled = enabled,
        _hideInspectorBanner = hideInspectorBanner,
        _showInspectorOn = showInspectorOn,
        _child = child,
        _navigatorKey = navigatorKey,
        _defaultTreeViewEnabled = defaultTreeViewEnabled,
        _defaultExpandChildren = defaultExpandChildren,
        _defaultIsDarkMode = defaultIsDarkMode;

  final bool _enabled;
  final bool _hideInspectorBanner;
  final ShowInspectorOn _showInspectorOn;
  final Widget _child;
  final bool _defaultTreeViewEnabled;
  final bool _defaultExpandChildren;
  final bool _defaultIsDarkMode;
  final GlobalKey<NavigatorState>? _navigatorKey;

  @override
  Widget build(BuildContext context) {
    var widget = _enabled
        ? ChangeNotifierProvider(
            create: (context) => InspectorController(
              enabled: _enabled,
              showInspectorOn: _effectiveShowInspectorOn,
              defaultTreeViewEnabled: _defaultTreeViewEnabled,
              defaultExpandChildren: _defaultExpandChildren,
              defaultIsDarkMode: _defaultIsDarkMode,
              onStoppingRequest: (requestDetails) => _showRequestEditorDialog(
                context,
                requestDetails: requestDetails,
              ),
              onStoppingResponse: (responseDetails) =>
                  _showResponseEditorDialog(
                context,
                responseDetails: responseDetails,
              ),
            ),
            lazy: false,
            builder: (context, _) {
              return ValueListenableBuilder<int>(
                valueListenable: InspectorController().currentPage,
                builder: (context, currentPage, child) {
                  return PopScope(
                    canPop: currentPage == 0,
                    child: GestureDetector(
                      onLongPress: _allowLongPress
                          ? InspectorController().showInspector
                          : null,
                      child: IndexedStack(
                        index: currentPage,
                        children: [
                          _child,
                          Inspector(navigatorKey: _navigatorKey),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          )
        : _child;

    if (!_hideInspectorBanner && _enabled) {
      widget = Banner(
        message: 'INSPECTOR',
        textDirection: TextDirection.ltr,
        location: BannerLocation.topEnd,
        child: widget,
      );
    }

    return Directionality(textDirection: TextDirection.ltr, child: widget);
  }

  bool _isSupportShaking() =>
      kIsWeb ? false : Platform.isAndroid || Platform.isIOS;

  /// Resolves the effective trigger, falling back to long press only when
  /// shaking is requested but not supported. `None` is always preserved so the
  /// inspector is never shown by long press or shaking.
  ShowInspectorOn get _effectiveShowInspectorOn {
    if (_showInspectorOn == ShowInspectorOn.None) return ShowInspectorOn.None;
    return _isSupportShaking() ? _showInspectorOn : ShowInspectorOn.LongPress;
  }

  bool get _allowLongPress => [
        ShowInspectorOn.LongPress,
        ShowInspectorOn.Both,
      ].contains(_effectiveShowInspectorOn);

  Future<RequestDetails?> _showRequestEditorDialog(
    BuildContext context, {
    required RequestDetails requestDetails,
  }) {
    if (_navigatorKey?.currentContext == null) return Future.value(null);
    if (!InspectorController().shouldStopRequest(requestDetails))
      return Future.value(null);

    return showDialog<RequestDetails?>(
      context: _navigatorKey!.currentContext!,
      builder: (context) =>
          RequestStopperEditorDialog(requestDetails: requestDetails),
    );
  }

  Future<ResponseDetails?> _showResponseEditorDialog(
    BuildContext context, {
    required ResponseDetails responseDetails,
  }) {
    if (_navigatorKey?.currentContext == null) return Future.value(null);
    if (!InspectorController().shouldStopResponse(responseDetails))
      return Future.value(null);

    return showDialog<ResponseDetails>(
      context: _navigatorKey!.currentContext!,
      builder: (context) =>
          ResponseStopperEditorDialog(responseDetails: responseDetails),
    );
  }
}
