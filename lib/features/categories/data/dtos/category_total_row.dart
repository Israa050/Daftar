/// A joined row from the category-totals aggregate query: one spending total
/// per category. A data-layer DTO -- the repository maps it to a
/// `CategoryTotalEntity` for the domain/UI.
///
/// [categoryId] and [categoryName] are nullable because the query left-outer
/// joins categories onto transactions, so an expense with no category (or a
/// deleted one) produces null here.
class CategoryTotalRow {
  CategoryTotalRow({
    required this.categoryId,
    required this.categoryName,
    required this.colorHex,
    required this.totalMinor,
  });

  final String? categoryId;
  final String? categoryName;
  final String? colorHex;
  final int totalMinor;
}
