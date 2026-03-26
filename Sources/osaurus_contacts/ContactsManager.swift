import Contacts
import Foundation

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
      // ignore error and fall back
    }

    if !results.isEmpty {
      return results
    }

    // fuzzy search (iterate all)
    let searchName = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    let request = CNContactFetchRequest(keysToFetch: keys)

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

    return results
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
