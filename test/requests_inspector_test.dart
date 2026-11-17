import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:requests_inspector_plus/requests_inspector_plus.dart';

void main() {
  for (final locale in [const Locale('en'), const Locale('ar')]) {
    for (final darkMode in [false, true]) {
      testWidgets(
        'Host stopper routes and inspector theme: ${locale.languageCode}, '
        'dark=$darkMode, without compatibility bridge',
        (tester) async {
          final navigatorKey = GlobalKey<NavigatorState>();
          final hostTheme = ThemeData(
            brightness: darkMode ? Brightness.light : Brightness.dark,
            colorSchemeSeed: Colors.purple,
          );
          await tester.pumpWidget(
            RequestsInspector(
              navigatorKey: navigatorKey,
              showInspectorOn: ShowInspectorOn.None,
              defaultIsDarkMode: darkMode,
              child: MaterialApp(
                navigatorKey: navigatorKey,
                theme: hostTheme,
                locale: locale,
                supportedLocales: const [Locale('en'), Locale('ar')],
                localizationsDelegates: locale.languageCode == 'en'
                    ? null
                    : GlobalMaterialLocalizations.delegates,
                home: const Scaffold(body: Text('Host app')),
              ),
            ),
          );
          await tester.pumpAndSettle();
          expect(navigatorKey.currentState!.canPop(), isFalse);

          final controller = InspectorController();
          final request = RequestDetails(
            url: 'https://example.com/original',
            requestMethod: RequestMethod.GET,
          );
          final StoppingRequestCallback editRequest = controller.editRequest;
          final requestResult = editRequest(request);
          await tester.pumpAndSettle();
          expect(find.byType(RequestStopperEditorDialog), findsOneWidget);
          _expectHostDialog(tester, navigatorKey, locale, darkMode);

          await tester.tap(find.byType(DropdownButton<RequestMethod>));
          await tester.pumpAndSettle();
          await tester.tap(find.text('POST').last);
          await tester.pumpAndSettle();
          await tester.enterText(
            find.byType(TextField).first,
            'https://example.com/edited',
          );
          await tester.tap(find.text('Send'));
          await tester.pumpAndSettle();
          final editedRequest = await requestResult;
          expect(editedRequest?.url, 'https://example.com/edited');
          expect(editedRequest?.requestMethod, RequestMethod.POST);
          expect(request.url, 'https://example.com/original');
          expect(request.requestMethod, RequestMethod.GET);
          expect(navigatorKey.currentState!.canPop(), isFalse);

          final response = ResponseDetails(
            url: 'https://example.com/original',
            statusCode: 200,
            responseBody: {'message': 'original'},
          );
          final StoppingResponseCallback editResponse = controller.editResponse;
          final responseResult = editResponse(response);
          await tester.pumpAndSettle();
          expect(find.byType(ResponseStopperEditorDialog), findsOneWidget);
          _expectHostDialog(tester, navigatorKey, locale, darkMode);

          await tester.enterText(find.byType(TextFormField), '201');
          await tester.enterText(
            find.byWidgetPredicate(
              (widget) =>
                  widget is TextField &&
                  (widget.controller?.text.contains('original') ?? false),
            ),
            '{"message":"edited"}',
          );
          await tester.tap(find.text('Receive'));
          await tester.pumpAndSettle();
          final editedResponse = await responseResult;
          expect(editedResponse?.statusCode, 201);
          expect(editedResponse?.responseBody, {'message': 'edited'});
          expect(response.statusCode, 200);
          expect(response.responseBody, {'message': 'original'});
          expect(navigatorKey.currentState!.canPop(), isFalse);

          final cancelledRequest = editRequest(request);
          await tester.pumpAndSettle();
          navigatorKey.currentState!.pop();
          await tester.pumpAndSettle();
          expect(await cancelledRequest, isNull);
          final cancelledResponse = editResponse(response);
          await tester.pumpAndSettle();
          navigatorKey.currentState!.pop();
          await tester.pumpAndSettle();
          expect(await cancelledResponse, isNull);

          controller.showInspector();
          await tester.pumpAndSettle();
          final inspectorContext = tester.element(find.byType(Scaffold));
          expect(
            Theme.of(inspectorContext).brightness,
            darkMode ? Brightness.dark : Brightness.light,
          );
          expect(
            MaterialLocalizations.of(inspectorContext),
            isA<DefaultMaterialLocalizations>(),
          );
          controller.toggleInspectorTheme();
          await tester.pumpAndSettle();
          expect(
            Theme.of(inspectorContext).brightness,
            darkMode ? Brightness.light : Brightness.dark,
          );
          controller.hideInspector();
          await tester.pumpAndSettle();
          expect(find.text('Host app'), findsOneWidget);
          expect(
            Theme.of(navigatorKey.currentContext!).colorScheme,
            hostTheme.colorScheme,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }
}

void _expectHostDialog(
  WidgetTester tester,
  GlobalKey<NavigatorState> navigatorKey,
  Locale locale,
  bool darkMode,
) {
  final dialogContext = tester.element(find.byType(AlertDialog));
  expect(navigatorKey.currentState!.canPop(), isTrue);
  expect(
    Theme.of(dialogContext).brightness,
    darkMode ? Brightness.dark : Brightness.light,
  );
  expect(Localizations.localeOf(dialogContext), locale);
  expect(Directionality.of(dialogContext), TextDirection.ltr);
  final route = ModalRoute.of(dialogContext)! as DialogRoute;
  expect(route.navigator, navigatorKey.currentState);
  expect(
    route.barrierLabel,
    MaterialLocalizations.of(navigatorKey.currentContext!)
        .modalBarrierDismissLabel,
  );
}
