/// Pure logic helpers for user related operations.
/// Stateless but consolidation of decision logic so they can be reused from
/// anywhere.

String getUserId(String name, String? email, String? org) {
  return '${name.trim().toLowerCase().replaceAll(' ', '_')}';
}
