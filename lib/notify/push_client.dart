// Escolhe a implementação certa: no navegador usa push_web.dart (JavaScript);
// nas demais plataformas, push_stub.dart (não faz nada).
export 'push_types.dart';
export 'push_stub.dart' if (dart.library.js_interop) 'push_web.dart';
