/// Typed domain exceptions for Fresh Cane V1 POS architecture.
abstract class FreshCaneException implements Exception {
  final String message;
  const FreshCaneException(this.message);

  @override
  String toString() => message;
}

/// Thrown when caller lacks necessary permissions or authentication.
class UnauthorizedException extends FreshCaneException {
  const UnauthorizedException([super.message = 'Unauthorized operation']);
}

/// Thrown when an action attempts to re-finish an already finished customer.
class CustomerAlreadyFinishedException extends FreshCaneException {
  const CustomerAlreadyFinishedException([super.message = 'Customer has already finished ordering']);
}

/// Thrown when a customer is already in a terminal state (billed or closed).
class CustomerNoLongerActiveException extends FreshCaneException {
  const CustomerNoLongerActiveException([super.message = 'Customer is already billed or closed and cannot be modified']);
}

/// Thrown when a requested customer or session cannot be found.
class CustomerNotFoundException extends FreshCaneException {
  const CustomerNotFoundException([super.message = 'Customer was not found in the table session']);
}

/// Thrown when an order is attempted for a customer who has completed ordering.
class CustomerCannotOrderException extends FreshCaneException {
  const CustomerCannotOrderException([super.message = 'Customer has completed ordering and cannot place new orders']);
}

/// Thrown for general repository, database, or network communication failures.
class RepositoryFailureException extends FreshCaneException {
  final dynamic originalError;
  const RepositoryFailureException(super.message, [this.originalError]);
}
