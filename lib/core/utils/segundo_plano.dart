import 'dart:async';

import 'package:flutter/foundation.dart';

Future<T> enSegundoPlano<T>(FutureOr<T> Function() tarea) async {
  try {
    return await compute<void, T>((_) => tarea(), null);
  } catch (_) {
    return await tarea();
  }
}
