import Contacts
import Foundation

class ContactsManager {
  private let store = CNContactStore()

  // Helper to ensure we have access
  private func ensureAccess() throws {
    let status = CNContactStore.authorizationStatus(for: .contacts)
    switch status {
    case .authorized:
      return
    case .notDetermined:
      let semaphore = DispatchSemaphore(value: 0)
      var granted = false
      var error: Error?

      store.requestAccess(for: .contacts) { g, e in
        granted = g
        error = e
        semaphore.signal()
      }

      semaphore.wait()

      if let error = error {
        throw error
      }
      if !granted {
        throw NSError(
          domain: "ContactsManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Access denied"]
        )
      }
    case .denied, .restricted:
      throw NSError(
        domain: "ContactsManager", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Access denied or restricted"])
    @unknown default:
      throw NSError(
        domain: "ContactsManager", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Unknown authorization status"])
    }
  }

  func getAllNumbers(limit: Int = 1000) throws -> [String: [String]] {
    try ensureAccess()

    var results: [String: [String]] = [:]
    var count = 0

    let keys =
      [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor]
    let request = CNContactFetchRequest(keysToFetch: keys)

    try store.enumerateContacts(with: request) { contact, stop in
      if count >= limit {
        stop.pointee = true
        return
      }

      let name = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(
        separator: " ")
      let phones = contact.phoneNumbers.map { $0.value.stringValue }

      if !name.isEmpty && !phones.isEmpty {
        results[name] = phones
        count += 1
      }
    }

    return results
  }

  func findNumber(name: String) throws -> [String] {
    try ensureAccess()

    // Try exact match first using predicate (fast)
    let predicate = CNContact.predicateForContacts(matchingName: name)
    let keys = [CNContactPhoneNumbersKey] as [CNKeyDescriptor]

    var allPhones: [String] = []

    do {
      let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keys)
      for contact in contacts {
        allPhones.append(contentsOf: contact.phoneNumbers.map { $0.value.stringValue })
      }
    } catch {
      // Ignore error and fall back to fuzzy search
    }

    if !allPhones.isEmpty {
      return allPhones
    }

    // Fallback: Fuzzy search (iterate all)
    let allContacts = try getAllNumbers(limit: 5000)

    let searchName = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)

    // Strategy 1: Exact match case-insensitive
    if let match = allContacts.keys.first(where: { $0.lowercased() == searchName }) {
      return allContacts[match] ?? []
    }

    // Strategy 2: Contains
    if let match = allContacts.keys.first(where: {
      $0.lowercased().contains(searchName) || searchName.contains($0.lowercased())
    }) {
      return allContacts[match] ?? []
    }

    return []
  }

  func findContactByPhone(phone: String) throws -> String? {
    try ensureAccess()

    // Normalize search phone
    let searchPhone = phone.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()
    if searchPhone.isEmpty { return nil }

    let keys =
      [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor]
    let request = CNContactFetchRequest(keysToFetch: keys)

    var foundName: String?

    try store.enumerateContacts(with: request) { contact, stop in
      for phoneNumber in contact.phoneNumbers {
        let num = phoneNumber.value.stringValue.components(
          separatedBy: CharacterSet.decimalDigits.inverted
        ).joined()
        // Check for match
        // We check if the search number is contained in the contact number or vice versa
        // to handle cases with/without country codes etc.
        if !num.isEmpty && (num.contains(searchPhone) || searchPhone.contains(num)) {
          foundName = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(
            separator: " ")
          stop.pointee = true
          return
        }
      }
    }

    return foundName
  }
}
