import 'zenith_node.dart';

/// Single field validation error description.
class ValidationError {
  /// Property name that failed validation.
  final String propertyName;

  /// Error message explaining why validation failed.
  final String message;

  /// Creates a [ValidationError].
  const ValidationError({required this.propertyName, required this.message});

  @override
  String toString() => '$propertyName: $message';
}

/// The result of evaluating a [ZenithValidator] against a model.
class ValidationResult {
  /// List of validation errors encountered.
  final List<ValidationError> errors;

  /// Creates a [ValidationResult].
  const ValidationResult(this.errors);

  /// Whether all validation rules passed (no errors).
  bool get isValid => errors.isEmpty;

  /// Returns error messages for a specific [propertyName].
  List<String> errorsFor(String propertyName) {
    return errors
        .where((e) => e.propertyName == propertyName)
        .map((e) => e.message)
        .toList();
  }
}

/// Rule builder for fluent property validation.
class PropertyRuleBuilder<T, V> {
  final V Function(T model) selector;
  final String propertyName;
  final List<String? Function(V value)> _validators = [];

  /// Creates a [PropertyRuleBuilder].
  PropertyRuleBuilder(this.selector, this.propertyName);

  /// Asserts that the field is not null or empty.
  PropertyRuleBuilder<T, V> notEmpty([String? customMessage]) {
    _validators.add((val) {
      if (val == null) return customMessage ?? 'Cannot be empty.';
      if (val is String && val.trim().isEmpty) {
        return customMessage ?? 'Cannot be empty.';
      }
      if (val is Iterable && val.isEmpty) {
        return customMessage ?? 'Cannot be empty.';
      }
      return null;
    });
    return this;
  }

  /// Asserts that a string property is a valid email format.
  PropertyRuleBuilder<T, V> email([String? customMessage]) {
    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    _validators.add((val) {
      if (val is String && val.isNotEmpty && !emailRegex.hasMatch(val)) {
        return customMessage ?? 'Invalid email address.';
      }
      return null;
    });
    return this;
  }

  /// Asserts that a string property has at least [min] characters.
  PropertyRuleBuilder<T, V> minLength(int min, [String? customMessage]) {
    _validators.add((val) {
      if (val is String && val.length < min) {
        return customMessage ?? 'Minimum length is $min characters.';
      }
      return null;
    });
    return this;
  }

  /// Asserts that a number is greater than [target].
  PropertyRuleBuilder<T, V> greaterThan(num target, [String? customMessage]) {
    _validators.add((val) {
      if (val is num && val <= target) {
        return customMessage ?? 'Must be greater than $target.';
      }
      return null;
    });
    return this;
  }

  /// Custom predicate validator.
  PropertyRuleBuilder<T, V> must(
    bool Function(V value) predicate,
    String errorMessage,
  ) {
    _validators.add((val) {
      if (!predicate(val)) {
        return errorMessage;
      }
      return null;
    });
    return this;
  }

  List<ValidationError> _evaluate(T model) {
    final value = selector(model);
    final errors = <ValidationError>[];
    for (final v in _validators) {
      final msg = v(value);
      if (msg != null) {
        errors.add(ValidationError(propertyName: propertyName, message: msg));
      }
    }
    return errors;
  }
}

/// Abstract base validator class for fluent model validation.
///
/// Equivalent to FluentValidation in .NET.
///
/// ```dart
/// class SignupValidator extends ZenithValidator<SignupForm> {
///   SignupValidator() {
///     ruleFor((f) => f.email, 'email').notEmpty().email();
///   }
/// }
/// ```
abstract class ZenithValidator<T> {
  final List<PropertyRuleBuilder<T, dynamic>> _rules = [];

  /// Registers a property rule selector and name.
  PropertyRuleBuilder<T, V> ruleFor<V>(
    V Function(T model) selector,
    String propertyName,
  ) {
    final builder = PropertyRuleBuilder<T, V>(selector, propertyName);
    _rules.add(builder);
    return builder;
  }

  /// Validates [model] against all registered rules.
  ValidationResult validate(T model) {
    final allErrors = <ValidationError>[];
    for (final rule in _rules) {
      allErrors.addAll(rule._evaluate(model));
    }
    return ValidationResult(allErrors);
  }
}

/// A specialized [ZenithNode] that automatically validates [T] on creation and mutation.
class ZenithValidatedNode<T> extends ZenithNode<T> {
  /// The validator powering this node.
  final ZenithValidator<T> validator;

  late ValidationResult _validationResult;

  /// Creates a [ZenithValidatedNode].
  ZenithValidatedNode(T model, {required this.validator}) : super(model) {
    _validationResult = validator.validate(model);
  }

  /// Whether the current node model is valid.
  bool get isValid => _validationResult.isValid;

  /// The current validation result containing errors.
  ValidationResult get validationResult => _validationResult;

  /// Gets error messages for a specific [propertyName].
  List<String> errorsFor(String propertyName) {
    return _validationResult.errorsFor(propertyName);
  }

  @override
  void set(T newValue) {
    _validationResult = validator.validate(newValue);
    super.set(newValue);
  }
}
