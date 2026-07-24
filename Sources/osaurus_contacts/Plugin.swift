import Foundation
import OsaurusPluginABI
import OsaurusPluginKit

// MARK: - Manifest

// File-scope manifest literal. Tool entries use `"id"` (the host-required key)
// and must stay in sync with the tools registered in `PluginContext`.
let contactsManifestJSON = """
  {
    "plugin_id": "osaurus.contacts",
    "name": "Contacts",
    "version": "1.1.0",
    "description": "Access and manage contacts on macOS",
    "license": "MIT",
    "authors": ["Dinoki Labs"],
    "min_macos": "13.0",
    "min_osaurus": "0.5.0",
    "capabilities": {
      "tools": [
        {
          "id": "find_contact_by_name",
          "description": "Find full contact details (phone, email) for a contact by name",
          "parameters": {"type":"object","properties":{"name":{"type":"string","description":"Name to search for"}},"required":["name"]},
          "requirements": ["contacts"],
          "permission_policy": "ask"
        },
        {
          "id": "find_contact_by_phone",
          "description": "Find a contact name by their phone number",
          "parameters": {"type":"object","properties":{"phoneNumber":{"type":"string","description":"Phone number to search for"}},"required":["phoneNumber"]},
          "requirements": ["contacts"],
          "permission_policy": "ask"
        },
        {
          "id": "find_number",
          "description": "Find phone numbers for a contact by name",
          "parameters": {"type":"object","properties":{"name":{"type":"string","description":"Name to search for"}},"required":["name"]},
          "requirements": ["contacts"],
          "permission_policy": "ask"
        },
        {
          "id": "get_all_numbers",
          "description": "Get all contacts and their phone numbers",
          "parameters": {"type":"object","properties":{"limit":{"type":"integer","description":"Max number of contacts to return (default 1000)"}},"required":[]},
          "requirements": ["contacts"],
          "permission_policy": "ask"
        }
      ]
    }
  }
  """

// MARK: - Protocol
protocol Tool {
  var name: String { get }
  var description: String { get }
  var parameters: String { get }
  func run(args: String) -> String
}

extension GetAllNumbersTool: Tool {}
extension FindNumberTool: Tool {}
extension FindContactByPhoneTool: Tool {}
extension FindContactByNameTool: Tool {}

// MARK: - C ABI surface

// Context state
private class PluginContext {
  let manager = ContactsManager()
  lazy var tools: [String: any Tool] = {
    let list: [any Tool] = [
      GetAllNumbersTool(manager: manager),
      FindNumberTool(manager: manager),
      FindContactByPhoneTool(manager: manager),
      FindContactByNameTool(manager: manager),
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
      Envelope.failure(.notFound, "Unknown capability or tool: \(type)/\(id)"))
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
