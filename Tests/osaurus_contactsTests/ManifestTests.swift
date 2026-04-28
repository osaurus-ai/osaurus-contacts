import Foundation
import Testing

@testable import osaurus_contacts

@Suite("Plugin Manifest")
struct ManifestTests {

  private enum ManifestError: Error {
    case entryPointFailed
    case nilManifest
    case invalidJSON
  }

  private func loadManifest() throws -> [String: Any] {
    guard let apiPtr = osaurus_plugin_entry() else {
      throw ManifestError.entryPointFailed
    }

    let fnPtrSize = MemoryLayout<UnsafeRawPointer?>.stride
    let initPtr = apiPtr.load(
      fromByteOffset: fnPtrSize,
      as: (@convention(c) () -> UnsafeMutableRawPointer?).self)
    let ctx = initPtr()

    let getManifestPtr = apiPtr.load(
      fromByteOffset: fnPtrSize * 3,
      as: (@convention(c) (UnsafeMutableRawPointer?) -> UnsafePointer<CChar>?).self)
    guard let cStr = getManifestPtr(ctx) else {
      throw ManifestError.nilManifest
    }
    let jsonString = String(cString: cStr)

    let freeStringPtr = apiPtr.load(
      fromByteOffset: 0,
      as: (@convention(c) (UnsafePointer<CChar>?) -> Void).self)
    freeStringPtr(cStr)

    let destroyPtr = apiPtr.load(
      fromByteOffset: fnPtrSize * 2,
      as: (@convention(c) (UnsafeMutableRawPointer?) -> Void).self)
    destroyPtr(ctx)

    guard let data = jsonString.data(using: .utf8),
      let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      throw ManifestError.invalidJSON
    }
    return manifest
  }

  private func tools(from manifest: [String: Any]) -> [[String: Any]] {
    let capabilities = manifest["capabilities"] as? [String: Any]
    return capabilities?["tools"] as? [[String: Any]] ?? []
  }

  private func toolMap(from manifest: [String: Any]) -> [String: [String: Any]] {
    Dictionary(
      uniqueKeysWithValues: tools(from: manifest).compactMap { tool -> (String, [String: Any])? in
        guard let id = tool["id"] as? String else { return nil }
        return (id, tool)
      })
  }

  @Test("manifest has correct plugin identity")
  func pluginIdentity() throws {
    let manifest = try loadManifest()
    #expect(manifest["plugin_id"] as? String == "osaurus.contacts")
  }

  @Test("manifest declares expected contact tools")
  func toolIDs() throws {
    let manifest = try loadManifest()
    let ids = Set(tools(from: manifest).compactMap { $0["id"] as? String })
    #expect(
      ids == ["find_contact_by_name", "find_contact_by_phone", "find_number", "get_all_numbers"])
  }

  @Test("all contact tools declare contacts requirement and approval")
  func requirementsAndPermissions() throws {
    let manifest = try loadManifest()
    for tool in tools(from: manifest) {
      let requirements = tool["requirements"] as? [String] ?? []
      #expect(requirements == ["contacts"])
      #expect(tool["permission_policy"] as? String == "ask")
    }
  }

  @Test("lookup tools declare required search parameters")
  func requiredParameters() throws {
    let manifest = try loadManifest()
    let map = toolMap(from: manifest)

    let findNumberParams = map["find_number"]?["parameters"] as? [String: Any]
    let findNumberRequired = findNumberParams?["required"] as? [String] ?? []
    #expect(findNumberRequired.contains("name"))

    let nameParams = map["find_contact_by_name"]?["parameters"] as? [String: Any]
    let nameRequired = nameParams?["required"] as? [String] ?? []
    #expect(nameRequired.contains("name"))

    let phoneParams = map["find_contact_by_phone"]?["parameters"] as? [String: Any]
    let phoneRequired = phoneParams?["required"] as? [String] ?? []
    #expect(phoneRequired.contains("phoneNumber"))
  }
}
