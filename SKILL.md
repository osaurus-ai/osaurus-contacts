---
name: osaurus-contacts
description: Use when the user asks to look up or browse entries in macOS Contacts.
---

# Contacts

Use this plugin when a user explicitly asks to look up or list entries in their macOS Contacts.

## Tools

- Use `find_contacts` for a known name or phone number.
- Use `list_contacts` only when browsing the address book is necessary.
- Start with a small `limit`; follow `next_cursor` only when more results are needed.
- Treat an empty `contacts` array as a successful search with no matches.
- Use `identifier`, not `name`, to distinguish contacts. Duplicate names are valid.

Contact data is sensitive. Confirm the request scope, avoid exposing unrelated entries, and
expect the host to ask for permission on every tool call.
