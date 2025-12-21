# osaurus-contacts

An Osaurus plugin for managing Contacts on macOS.

## Tools

- `get_all_numbers`: Get all contacts and their phone numbers
- `find_number`: Find phone numbers for a contact by name
- `find_contact_by_phone`: Find a contact name by their phone number

## Development

1. Build:
   ```bash
   swift build -c release
   cp .build/release/libosaurus-contacts.dylib ./libosaurus-contacts.dylib
   ```
2. Package (for distribution):
   ```bash
   osaurus tools package osaurus.contacts 0.1.0
   ```
   This creates `osaurus.contacts-0.1.0.zip`.
3. Install locally:
   ```bash
   osaurus tools install ./osaurus.contacts-0.1.0.zip
   ```

## Permissions

This plugin requires access to your Contacts. On macOS, you will be prompted to grant access to the host application (e.g. Terminal, osaurus CLI, or the app using the plugin) upon the first request.

## Credits

- Based on logic from [apple-mcp](https://github.com/supermemoryai/apple-mcp)
