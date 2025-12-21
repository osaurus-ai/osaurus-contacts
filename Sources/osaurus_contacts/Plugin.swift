import Foundation

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

// MARK: - C ABI surface

// Opaque context
private typealias osr_plugin_ctx_t = UnsafeMutableRawPointer

// Function pointers
private typealias osr_free_string_t = @convention(c) (UnsafePointer<CChar>?) -> Void
private typealias osr_init_t = @convention(c) () -> osr_plugin_ctx_t?
private typealias osr_destroy_t = @convention(c) (osr_plugin_ctx_t?) -> Void
private typealias osr_get_manifest_t = @convention(c) (osr_plugin_ctx_t?) -> UnsafePointer<CChar>?
private typealias osr_invoke_t =
  @convention(c) (
    osr_plugin_ctx_t?,
    UnsafePointer<CChar>?,  // type
    UnsafePointer<CChar>?,  // id
    UnsafePointer<CChar>?  // payload
  ) -> UnsafePointer<CChar>?

private struct osr_plugin_api {
  var free_string: osr_free_string_t?
  var `init`: osr_init_t?
  var destroy: osr_destroy_t?
  var get_manifest: osr_get_manifest_t?
  var invoke: osr_invoke_t?
}

// Context state
private class PluginContext {
  let manager = ContactsManager()
  lazy var tools: [String: any Tool] = {
    let list: [any Tool] = [
      GetAllNumbersTool(manager: manager),
      FindNumberTool(manager: manager),
      FindContactByPhoneTool(manager: manager),
    ]
    return Dictionary(uniqueKeysWithValues: list.map { ($0.name, $0) })
  }()
}

// Helper to return C strings
private func makeCString(_ s: String) -> UnsafePointer<CChar>? {
  guard let ptr = strdup(s) else { return nil }
  return UnsafePointer(ptr)
}

// API Implementation
private var api: osr_plugin_api = {
  var api = osr_plugin_api()

  api.free_string = { ptr in
    if let p = ptr { free(UnsafeMutableRawPointer(mutating: p)) }
  }

  api.`init` = {
    let ctx = PluginContext()
    return Unmanaged.passRetained(ctx).toOpaque()
  }

  api.destroy = { ctxPtr in
    guard let ctxPtr = ctxPtr else { return }
    Unmanaged<PluginContext>.fromOpaque(ctxPtr).release()
  }

  api.get_manifest = { ctxPtr in
    guard let ctxPtr = ctxPtr else { return nil }
    let ctx = Unmanaged<PluginContext>.fromOpaque(ctxPtr).takeUnretainedValue()

    let toolsList = ctx.tools.values.sorted(by: { $0.name < $1.name }).map { tool in
      """
      {
        "id": "\(tool.name)",
        "description": "\(tool.description)",
        "parameters": \(tool.parameters),
        "requirements": [],
        "permission_policy": "ask"
      }
      """
    }.joined(separator: ",")

    let manifest = """
      {
        "plugin_id": "osaurus.contacts",
        "version": "0.1.0",
        "description": "Access and manage contacts on macOS",
        "capabilities": {
          "tools": [
            \(toolsList)
          ]
        }
      }
      """
    return makeCString(manifest)
  }

  api.invoke = { ctxPtr, typePtr, idPtr, payloadPtr in
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
        return makeCString(result)
      }
    }

    return makeCString("{\"error\": \"Unknown capability or tool\"}")
  }

  return api
}()

@_cdecl("osaurus_plugin_entry")
public func osaurus_plugin_entry() -> UnsafeRawPointer? {
  return UnsafeRawPointer(&api)
}
