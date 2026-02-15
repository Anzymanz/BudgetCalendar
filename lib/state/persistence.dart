import 'persistence_stub.dart'
    if (dart.library.io) 'persistence_io.dart'
    if (dart.library.html) 'persistence_web.dart';

abstract class BudgetPersistence {
  Future<String?> read();
  Future<void> write(String contents);
}

BudgetPersistence createPersistence() => createPersistenceImpl();

