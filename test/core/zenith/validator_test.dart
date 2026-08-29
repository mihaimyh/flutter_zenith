import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_zenith/flutter_zenith.dart';

class SignupForm {
  final String email;
  final String password;
  final int age;

  const SignupForm({
    required this.email,
    required this.password,
    required this.age,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SignupForm &&
          other.email == email &&
          other.password == password &&
          other.age == age);

  @override
  int get hashCode => Object.hash(email, password, age);
}

class SignupFormValidator extends ZenithValidator<SignupForm> {
  SignupFormValidator() {
    ruleFor((f) => f.email, 'email').notEmpty().email();
    ruleFor((f) => f.password, 'password').notEmpty().minLength(8);
    ruleFor((f) => f.age, 'age').greaterThan(18);
  }
}

void main() {
  group('ZenithValidator & ZenithValidatedNode', () {
    final validator = SignupFormValidator();

    test('validate returns errors for invalid fields', () {
      const invalidForm = SignupForm(
        email: 'invalid_email',
        password: 'short',
        age: 15,
      );

      final result = validator.validate(invalidForm);

      expect(result.isValid, isFalse);
      expect(result.errorsFor('email'), contains('Invalid email address.'));
      expect(
        result.errorsFor('password'),
        contains('Minimum length is 8 characters.'),
      );
      expect(result.errorsFor('age'), contains('Must be greater than 18.'));
    });

    test('validate returns valid result when all rules pass', () {
      const validForm = SignupForm(
        email: 'alice@example.com',
        password: 'securepassword123',
        age: 25,
      );

      final result = validator.validate(validForm);
      expect(result.isValid, isTrue);
      expect(result.errors, isEmpty);
    });

    test('ZenithValidatedNode automatically updates validation state on set()', () {
      final validatedNode = ZenithValidatedNode<SignupForm>(
        const SignupForm(email: '', password: '', age: 0),
        validator: validator,
      );

      expect(validatedNode.isValid, isFalse);
      expect(validatedNode.errorsFor('email'), isNotEmpty);

      // Update to valid model
      validatedNode.set(
        const SignupForm(
          email: 'bob@example.com',
          password: 'password123',
          age: 30,
        ),
      );

      expect(validatedNode.isValid, isTrue);
      expect(validatedNode.errorsFor('email'), isEmpty);
    });
  });
}
