# Migrating to Contacts 2.0

Contacts 2.0 replaces the 1.x tool surface and result shapes.

## Tool replacements

- `get_all_numbers` → `list_contacts`
- `find_number` → `find_contacts` with `match_by: "name"`
- `find_contact_by_name` → `find_contacts` with `match_by: "name"`
- `find_contact_by_phone` → `find_contacts` with `match_by: "phone"`

`limit` is required and must be an integer from 1 through 1000. Pass `next_cursor` back as
`cursor` to request another page. Cursors are opaque and scoped to the same tool and query.

## Result changes

Every success now uses the canonical envelope:

```json
{
  "ok": true,
  "tool": "find_contacts",
  "result": {
    "contacts": [
      {
        "identifier": "CNContact identifier",
        "name": "Alex Smith",
        "phone_numbers": [{"label": "mobile", "value": "+1 555 0100"}],
        "emails": [{"label": "work", "value": "alex@example.com"}]
      }
    ],
    "returned": 1,
    "total": 1,
    "truncated": false
  }
}
```

The 1.x name-keyed phone dictionary and synthetic duplicate suffixes are removed. Contacts
with the same display name remain separate records identified by `identifier`. No matches
return a successful empty page instead of `not_found`.

Failures use the SDK's canonical `ok: false` envelope and host failure kinds such as
`invalid_args`, `user_denied`, `timeout`, `execution_error`, and `tool_not_found`. Argument
objects reject undeclared properties.
