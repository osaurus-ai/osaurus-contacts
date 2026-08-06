import Foundation
import OsaurusPluginABI
import OsaurusPluginKit

// MARK: - Manifest

private func makeContactsManifestJSON() -> String {
  let tools: [[String: Any]] = ToolContracts.all.map { definition in
    let parameters = try! JSONSerialization.jsonObject(with: Data(definition.parameters.utf8))
    return [
      "id": definition.id,
      "description": definition.description,
      "parameters": parameters,
      "requirements": ["contacts"],
      "permission_policy": "ask",
    ]
  }
  let manifest: [String: Any] = [
    "plugin_id": "osaurus.contacts",
    "name": "Contacts",
    "version": "2.0.0",
    "description": "Read contacts on macOS",
    "license": "MIT",
    "authors": ["Dinoki Labs"],
    "min_macos": "13.0",
    "min_osaurus": "0.5.0",
    "capabilities": ["tools": tools],
  ]
  let data = try! JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
  return String(data: data, encoding: .utf8)!
}

let contactsManifestJSON = makeContactsManifestJSON()

// MARK: - Protocol
protocol Tool {
  var name: String { get }
  var description: String { get }
  var parameters: String { get }
  func run(args: String) -> String
}

extension ListContactsTool: Tool {}
extension FindContactsTool: Tool {}

// MARK: - C ABI surface

// Context state
private class PluginContext {
  let manager = ContactsManager()
  lazy var tools: [String: any Tool] = {
    let list: [any Tool] = [
      ListContactsTool(manager: manager),
      FindContactsTool(manager: manager),
    ]
    return Dictionary(uniqueKeysWithValues: list.map { ($0.name, $0) })
  }()
}

// API Implementation
private var pluginAPI = PluginEntry.makeAPI(
  version: OsrABIVersion.v2,
  init: {
    Unmanaged.passRetained(PluginContext()).toOpaque()
  },
  destroy: { ctxPtr in
    guard let ctxPtr = ctxPtr else { return }
    Unmanaged<PluginContext>.fromOpaque(ctxPtr).release()
  },
  getManifest: { ctxPtr in
    guard ctxPtr != nil else { return nil }
    return osrMakeCString(contactsManifestJSON)
  },
  invoke: { ctxPtr, typePtr, idPtr, payloadPtr in
    guard let ctxPtr = ctxPtr,
      let typePtr = typePtr,
      let idPtr = idPtr,
      let payloadPtr = payloadPtr
    else { return nil }

    let ctx = Unmanaged<PluginContext>.fromOpaque(ctxPtr).takeUnretainedValue()
    let type = String(cString: typePtr)
    let id = String(cString: idPtr)
    let payload = String(cString: payloadPtr)

    if type == "tool" {
      if let tool = ctx.tools[id] {
        let result = tool.run(args: payload)
        return osrMakeCString(result)
      }
    }

    return osrMakeCString(
      Envelope.failure(
        .toolNotFound,
        "Unknown capability or tool: \(type)/\(id)",
        tool: id
      ))
  }
)

@_cdecl("osaurus_plugin_entry_v2")
public func osaurus_plugin_entry_v2(_ host: UnsafeRawPointer?) -> UnsafeRawPointer? {
  PluginEntry.enterV2(host, api: &pluginAPI)
}

@_cdecl("osaurus_plugin_entry")
public func osaurus_plugin_entry() -> UnsafeRawPointer? {
  PluginEntry.enterV1(api: &pluginAPI)
}
