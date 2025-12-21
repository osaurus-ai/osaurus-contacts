import Foundation

struct GetAllNumbersTool {
  let name = "get_all_numbers"
  let description = "Get all contacts and their phone numbers"
  let parameters =
    "{\"type\":\"object\",\"properties\":{\"limit\":{\"type\":\"integer\",\"description\":\"Max number of contacts to return (default 1000)\"}},\"required\":[]}"

  let manager: ContactsManager

  func run(args: String) -> String {
    struct Args: Decodable {
      let limit: Int?
    }

    let limit =
      (try? JSONDecoder().decode(Args.self, from: args.data(using: .utf8) ?? Data()))?.limit ?? 1000

    do {
      let contacts = try manager.getAllNumbers(limit: limit)
      let data = try JSONEncoder().encode(contacts)
      return String(data: data, encoding: .utf8) ?? "{}"
    } catch {
      return "{\"error\": \"\(error.localizedDescription)\"}"
    }
  }
}

struct FindNumberTool {
  let name = "find_number"
  let description = "Find phone numbers for a contact by name"
  let parameters =
    "{\"type\":\"object\",\"properties\":{\"name\":{\"type\":\"string\",\"description\":\"Name to search for\"}},\"required\":[\"name\"]}"

  let manager: ContactsManager

  func run(args: String) -> String {
    struct Args: Decodable {
      let name: String
    }

    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return "{\"error\": \"Invalid arguments\"}"
    }

    do {
      let numbers = try manager.findNumber(name: input.name)
      let data = try JSONEncoder().encode(numbers)
      return String(data: data, encoding: .utf8) ?? "[]"
    } catch {
      return "{\"error\": \"\(error.localizedDescription)\"}"
    }
  }
}

struct FindContactByPhoneTool {
  let name = "find_contact_by_phone"
  let description = "Find a contact name by their phone number"
  let parameters =
    "{\"type\":\"object\",\"properties\":{\"phoneNumber\":{\"type\":\"string\",\"description\":\"Phone number to search for\"}},\"required\":[\"phoneNumber\"]}"

  let manager: ContactsManager

  func run(args: String) -> String {
    struct Args: Decodable {
      let phoneNumber: String
    }

    guard let data = args.data(using: .utf8),
      let input = try? JSONDecoder().decode(Args.self, from: data)
    else {
      return "{\"error\": \"Invalid arguments\"}"
    }

    do {
      let name = try manager.findContactByPhone(phone: input.phoneNumber)
      if let name = name {
        let result = ["name": name]
        let data = try JSONEncoder().encode(result)
        return String(data: data, encoding: .utf8) ?? "{}"
      } else {
        return "null"
      }
    } catch {
      return "{\"error\": \"\(error.localizedDescription)\"}"
    }
  }
}
