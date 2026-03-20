
import 'dart:ui_web' as ui_web;
import 'dart:js' as js;
import 'dart:js_util' as js_util;

void registerMapViewFactory(Object Function(int) factory) {
  ui_web.platformViewRegistry.registerViewFactory('gmaps-web-view', factory);
}

void invokeJsContext(String method, List<dynamic> args) {
  js.context.callMethod(method, args);
}

Future<dynamic> invokeJsPromise(String method, List<dynamic> args) async {
  try {

    final window = js.context;
    if (!js_util.hasProperty(window, method)) {
      print('JS Error: Method $method not found on window');
      return null;
    }

    final fn = js_util.getProperty(window, method);
    final promise = js_util.callMethod(fn, 'apply', [window, js_util.jsify(args)]);

    if (promise == null) return null;
    return await js_util.promiseToFuture(promise);
  } catch (e) {
    print('JS Promise Error ($method): $e');
    return null;
  }
}

dynamic createJsDiv() {
  return js.context['document'].createElement('div');
}