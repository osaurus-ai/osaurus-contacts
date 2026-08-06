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

struct ContactRecord: Codable, Equatable {
  let identifier: String
  let name: String
  let phoneNumbers: [LabeledValue]
  let emails: [LabeledValue]

  enum CodingKeys: String, CodingKey {
    case identifier
    case name
    case phoneNumbers = "phone_numbers"
    case emails
  }
}

extension LabeledValue: Equatable {}

enum ContactMatchField: String {
  case name
  case phone
}

protocol ContactsManaging {
  func listContacts() throws -> [ContactRecord]
  func findContacts(query: String, matchBy: ContactMatchField) throws -> [ContactRecord]
}

final class ContactsManager: ContactsManaging {
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

  func listContacts() throws -> [ContactRecord] {
    try ensureAccess()

    let keys: [CNKeyDescriptor] = [
      CNContactIdentifierKey as CNKeyDescriptor,
      CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
      CNContactOrganizationNameKey as CNKeyDescriptor,
      CNContactPhoneNumbersKey as CNKeyDescriptor,
      CNContactEmailAddressesKey as CNKeyDescriptor,
    ]
    let request = CNContactFetchRequest(keysToFetch: keys)
    var contacts: [ContactRecord] = []

    try store.enumerateContacts(with: request) { contact, _ in
      contacts.append(self.record(from: contact))
    }

    return contacts.sorted { $0.identifier < $1.identifier }
  }

  func findContacts(query: String, matchBy: ContactMatchField) throws -> [ContactRecord] {
    let contacts = try listContacts()
    switch matchBy {
    case .name:
      return contacts.filter { Matching.nameMatches(query: query, candidate: $0.name) }
    case .phone:
      return contacts.filter {
        $0.phoneNumbers.contains {
          Matching.phoneMatches(query: query, candidate: $0.value)
        }
      }
    }
  }

  private func record(from contact: CNContact) -> ContactRecord {
    let formattedName =
      CNContactFormatter.string(from: contact, style: .fullName)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let name = formattedName.isEmpty ? contact.organizationName : formattedName

    return ContactRecord(
      identifier: contact.identifier,
      name: name,
      phoneNumbers: contact.phoneNumbers.map {
        LabeledValue(label: normalizeLabel($0.label), value: $0.value.stringValue)
      },
      emails: contact.emailAddresses.map {
        LabeledValue(label: normalizeLabel($0.label), value: $0.value as String)
      }
    )
  }
}
