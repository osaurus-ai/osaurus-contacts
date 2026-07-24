import Contacts
import Foundation

enum ContactsError: Error {
  case permissionDenied(String)
  case permissionTimeout(String)
  case searchFailed(String)
}

struct LabeledValue: Codable {
  let label: String
  let value: String
}

struct ContactInfo: Codable {
  let name: String
  let phoneNumbers: [LabeledValue]
  let emails: [LabeledValue]
}

class ContactsManager {
  private let store = CNContactStore()

  // Helper to normalize labels (e.g., "_$!<Home>!$_" -> "home")
  private func normalizeLabel(_ label: String?) -> String {
    guard let label = label else { return "other" }
    return CNLabeledValue<NSString>.localizedString(forLabel: label).lowercased()
  }

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

      if semaphore.wait(timeout: .now() + 30) == .timedOut {
        throw ContactsError.permissionTimeout("Timed out waiting for Contacts permission")
      }

      if let error = error {
        throw error
      }
      if !granted {
        throw ContactsError.permissionDenied("Contacts access denied")
      }
    case .denied, .restricted:
      throw ContactsError.permissionDenied("Contacts access denied or restricted")
    @unknown default:
      throw ContactsError.permissionDenied("Unknown Contacts authorization status")
    }
  }

  func getAllNumbers(limit: Int = 1000) throws -> [String: [String]] {
    try ensureAccess()

    var entries: [(name: String, phones: [String])] = []

    let keys =
      [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor]
    let request = CNContactFetchRequest(keysToFetch: keys)

    try store.enumerateContacts(with: request) { contact, stop in
      if entries.count >= limit {
        stop.pointee = true
        return
      }

      let name = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(
        separator: " ")
      let phones = contact.phoneNumbers.map { $0.value.stringValue }

      if !name.isEmpty && !phones.isEmpty {
        entries.append((name: name, phones: phones))
      }
    }

    return Matching.nameKeyedResults(entries)
  }

  func findNumber(name: String) throws -> [String] {
    let contacts = try findContactByName(name: name)
    return contacts.flatMap { $0.phoneNumbers.map { $0.value } }
  }

  func findContactByName(name: String) throws -> [ContactInfo] {
    try ensureAccess()

    let keys = [
      CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey,
      CNContactEmailAddressesKey,
    ] as [CNKeyDescriptor]

    // exact match using predicate
    let predicate = CNContact.predicateForContacts(matchingName: name)
    var results: [ContactInfo] = []
    var exactSearchError: Error? = nil

    do {
      let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: keys)
      for contact in contacts {
        let fullName = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(
          separator: " ")
        results.append(
          ContactInfo(
            name: fullName,
            phoneNumbers: contact.phoneNumbers.map {
              LabeledValue(label: self.normalizeLabel($0.label), value: $0.value.stringValue)
            },
            emails: contact.emailAddresses.map {
              LabeledValue(label: self.normalizeLabel($0.label), value: $0.value as String)
            }
          ))
      }
    } catch {
      // Remember the error; if the fallback below also fails, both are reported.
      exactSearchError = error
    }

    if !results.isEmpty {
      return results
    }

    // fuzzy search (iterate all)
    let searchName = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    let request = CNContactFetchRequest(keysToFetch: keys)

    do {
      try store.enumerateContacts(with: request) { contact, _ in
        let fullName = [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(
          separator: " ")
        let lowerFullName = fullName.lowercased()

        if lowerFullName.contains(searchName) || searchName.contains(lowerFullName) {
          results.append(
            ContactInfo(
              name: fullName,
              phoneNumbers: contact.phoneNumbers.map {
                LabeledValue(label: self.normalizeLabel($0.label), value: $0.value.stringValue)
              },
              emails: contact.emailAddresses.map {
                LabeledValue(label: self.normalizeLabel($0.label), value: $0.value as String)
              }
            ))
        }
      }
    } catch {
      if let exactSearchError {
        throw ContactsError.searchFailed(
          "Exact search failed: \(exactSearchError.localizedDescription); fallback search failed: \(error.localizedDescription)"
        )
      }
      throw error
    }

    return results
  }

  func findContactByPhone(phone: String) throws -> String? {
    try ensureAccess()

    if Matching.normalizeDigits(phone).isEmpty { return nil }

    let keys =
      [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor]
    let request = CNContactFetchRequest(keysToFetch: keys)

    var foundName: String?

    try store.enumerateContacts(with: request) { contact, stop in
      for phoneNumber in contact.phoneNumbers {
        // Digits-only comparison requiring full equality or a >=7 digit suffix
        // match, so short numbers cannot match by raw substring containment.
        if Matching.phoneMatches(query: phone, candidate: phoneNumber.value.stringValue) {
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
