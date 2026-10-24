import 'package:flutter_test/flutter_test.dart';
import 'package:smartnps360/src/permissions/permission_status_api_contract.dart';

void main() {
  group('PermissionStatusApiContract.isAcceptedResponse', () {
    test('accepts 2xx with empty or null body', () {
      expect(
        PermissionStatusApiContract.isAcceptedResponse(
          statusCode: 202,
          body: null,
        ),
        isTrue,
      );
      expect(
        PermissionStatusApiContract.isAcceptedResponse(
          statusCode: 204,
          body: '',
        ),
        isTrue,
      );
      expect(
        PermissionStatusApiContract.isAcceptedResponse(
          statusCode: 200,
          body: '   ',
        ),
        isTrue,
      );
    });

    test('accepts 2xx JSON without failure flags', () {
      expect(
        PermissionStatusApiContract.isAcceptedResponse(
          statusCode: 200,
          body: {'message': 'saved'},
        ),
        isTrue,
      );
      expect(
        PermissionStatusApiContract.isAcceptedResponse(
          statusCode: 200,
          body: {'success': true},
        ),
        isTrue,
      );
    });

    test('rejects non-2xx even with success body', () {
      expect(
        PermissionStatusApiContract.isAcceptedResponse(
          statusCode: 500,
          body: {'success': true},
        ),
        isFalse,
      );
      expect(
        PermissionStatusApiContract.isAcceptedResponse(
          statusCode: 0,
          body: null,
        ),
        isFalse,
      );
    });

    test('rejects 2xx with explicit failure body', () {
      expect(
        PermissionStatusApiContract.isAcceptedResponse(
          statusCode: 200,
          body: {'success': false},
        ),
        isFalse,
      );
      expect(
        PermissionStatusApiContract.isAcceptedResponse(
          statusCode: 202,
          body: {'ok': false, 'message': 'nope'},
        ),
        isFalse,
      );
      expect(
        PermissionStatusApiContract.isAcceptedResponse(
          statusCode: 200,
          body: {'status': 'error'},
        ),
        isFalse,
      );
      expect(
        PermissionStatusApiContract.isAcceptedResponse(
          statusCode: 200,
          body: {'errors': {'permissions': 'invalid'}},
        ),
        isFalse,
      );
      expect(
        PermissionStatusApiContract.isAcceptedResponse(
          statusCode: 200,
          body: '<html><body>login</body></html>',
        ),
        isFalse,
      );
    });
  });
}
