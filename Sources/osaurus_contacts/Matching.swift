import Foundation

/// Pure matching and result-shaping helpers, kept framework-free so they can
/// be unit tested without Contacts framework/TCC access.
enum Matching {
  /// Minimum number of digits required for a suffix match between two phone
  /// numbers. Seven digits is a full local number; anything shorter (e.g.
  /// "911", "0", short codes) must match exactly.
  static let minSuffixMatchDigits = 7

  /// Strips everything except decimal digits.
  static func normalizeDigits(_ s: String) -> String {
    return s.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
  }

  /// Whether a searched phone number matches a stored one. Both are compared
  /// on digits only. A match requires full equality, or one number being a
  /// suffix of the other where the shorter side has at least
  /// `minSuffixMatchDigits` digits (handles missing/present country codes
  /// without letting short numbers match by raw substring containment).
  static func phoneMatches(query: String, candidate: String) -> Bool {
    let q = normalizeDigits(query)
    let c = normalizeDigits(candidate)
    guard !q.isEmpty && !c.isEmpty else { return false }
    if q == c { return true }
    let shorterCount = min(q.count, c.count)
    guard shorterCount >= minSuffixMatchDigits else { return false }
    return q.hasSuffix(c) || c.hasSuffix(q)
  }

  /// Builds the name-keyed phone map returned by get_all_numbers while
  /// preserving contacts whose display names collide: subsequent duplicates
  /// get a " (2)", " (3)", ... suffix instead of overwriting earlier entries.
  static func nameKeyedResults(_ entries: [(name: String, phones: [String])]) -> [String: [String]]
  {
    var results: [String: [String]] = [:]
    for entry in entries {
      var key = entry.name
      var suffix = 2
      while results[key] != nil {
        key = "\(entry.name) (\(suffix))"
        suffix += 1
      }
      results[key] = entry.phones
    }
    return results
  }
}
