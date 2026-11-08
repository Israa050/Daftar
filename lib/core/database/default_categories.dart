import 'package:drift/drift.dart';
import 'package:stockflow/core/database/app_database.dart';

// Fixed (not randomly generated) so they're stable and predictable across
// installs -- but real UUIDs, not human-readable strings like the old
// 'default-food', since Supabase's category_id/id columns are typed uuid
// and reject anything else.
const defaultCategoryFoodId = '11111111-1111-1111-1111-111111111111';
const defaultCategoryTransportId = '22222222-2222-2222-2222-222222222222';
const defaultCategoryShoppingId = '33333333-3333-3333-3333-333333333333';
const defaultCategoryBillsId = '44444444-4444-4444-4444-444444444444';

/// The categories seeded into a fresh database on first create.
final defaultCategories = [
  CategoriesCompanion.insert(
    id: defaultCategoryFoodId,
    name: 'Food',
    colorHex: const Value('#FF9800'),
  ),
  CategoriesCompanion.insert(
    id: defaultCategoryTransportId,
    name: 'Transport',
    colorHex: const Value('#2196F3'),
  ),
  CategoriesCompanion.insert(
    id: defaultCategoryShoppingId,
    name: 'Shopping',
    colorHex: const Value('#9C27B0'),
  ),
  CategoriesCompanion.insert(
    id: defaultCategoryBillsId,
    name: 'Bills',
    colorHex: const Value('#F44336'),
  ),
];
