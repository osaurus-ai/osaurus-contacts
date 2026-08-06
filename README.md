# osaurus-contacts 2.0

An Osaurus plugin for reading macOS Contacts through a small, privacy-sensitive tool surface.

## Tools

- `list_contacts(limit, cursor?)`: List contacts with stable identifiers and labeled phone/email values.
- `find_contacts(query, match_by, limit, cursor?)`: Find contacts by `name` or `phone`.

Both tools return a canonical success envelope containing `contacts`, `returned`, `total`,
`truncated`, and (when another page exists) `next_cursor`. An empty match is a successful
result with an empty `contacts` array.

## Development

1. Build:
   ```bash
   swift build -c release
   ```
2. Package (for distribution):
   ```bash
   osaurus tools package osaurus.contacts 2.0.0
   ```
   This creates `osaurus.contacts-2.0.0.zip`.
3. Install locally:
   ```bash
   osaurus tools install ./osaurus.contacts-2.0.0.zip
   ```

## Permissions

Every tool keeps `permission_policy: ask` because contact details are sensitive. macOS will
also prompt the host application for Contacts access on first use.

See [MIGRATION-2.0.md](MIGRATION-2.0.md) for breaking changes from 1.x.

## Credits

- Based on logic from [apple-mcp](https://github.com/supermemoryai/apple-mcp)
