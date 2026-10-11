import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/order_repository.dart';
import 'server_order_notifier.dart';
import 'server_order_state.dart';

export 'server_order_state.dart';

/// Provider exposing the OrderRepository instance.
final orderRepositoryProvider = Provider<OrderRepository>((ref) {
  return OrderRepository();
});

/// Central Riverpod NotifierProvider managing the Server ordering interface state.
final serverOrderProvider =
    NotifierProvider<ServerOrderNotifier, ServerOrderState>(() {
  return ServerOrderNotifier();
});
