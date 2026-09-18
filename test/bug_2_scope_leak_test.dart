import 'package:test/test.dart';
import 'package:flutter_zenith/src/scope/zenith_scope_manager.dart';

void main() {
  test('getOrCreateUserScope leaks memory by not disposing existing ZenithTenantScope', () {
    final manager = ZenithScopeManager();
    final tenantScope = manager.getOrCreateScope('user_1');
    
    bool tenantDisposed = false;
    tenantScope.onDispose(() {
      tenantDisposed = true;
    });

    // Create a node inside the old scope
    tenantScope.container.getOrCreateNode('my_node', (ref) {
      return 'data';
    });

    // Now call getOrCreateUserScope. Since it's a ZenithTenantScope, it gets replaced.
    final userScope = manager.getOrCreateUserScope('user_1');
    
    // The new scope is a ZenithUserScope
    expect(userScope.id, 'user_1');
    
    // The old scope should have been disposed to prevent memory leaks!
    expect(tenantScope.isDisposed, isTrue, reason: 'Bug fixed: scope IS disposed.');
    expect(tenantDisposed, isTrue, reason: 'Bug fixed: onDispose IS called.');
    
    // If we call endScope now, it will only end the NEW userScope
    manager.endScope('user_1');
    
    expect(userScope.isDisposed, isTrue);
  });
}
