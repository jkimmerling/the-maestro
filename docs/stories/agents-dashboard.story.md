# Story: Agents on Dashboard (CRUD, Auth linkage, Prompts/Personas)

## Status
Planned – ready to scaffold with Phoenix generators

## Summary
Add an “Agents” section to the Dashboard with full CRUD and creation via modal. Each Agent:
- References a Saved Auth (FK to `saved_authentications`).
- References a Base System Prompt (FK to `base_system_prompts`).
- References a Persona (FK to `personas`).
- Stores `tools`, `mcps`, `memory` as JSONB for flexible, evolving configuration.

Policies confirmed by PM/owner:
- Auth deletion policy: Restrict deletion when Agents exist. UI must block deletion with a helpful message. Auths are deleted only from the Auths section/menu (not via Agent screens).
- Prompt/Persona storage: model as tables with UUID ids; Agent references them via FKs.
- Memory shape: store as JSONB; enforce structure in changesets (convert to typed structs for validation), but persist the JSON as-is.

## Data Model

Tables & keys (PostgreSQL):

- `agents` (UUID primary key)
  - `id` UUID, PK
  - `name` string, unique, NOT NULL
  - `auth_id` integer, NOT NULL, FK → `saved_authentications(id)`, on_delete: :restrict
  - `base_system_prompt_id` UUID, FK → `base_system_prompts(id)`, on_delete: :nilify_all
  - `persona_id` UUID, FK → `personas(id)`, on_delete: :nilify_all
  - `tools` JSONB NOT NULL DEFAULT '{}'
  - `mcps` JSONB NOT NULL DEFAULT '{}'
  - `memory` JSONB NOT NULL DEFAULT '{}'
  - `inserted_at`, `updated_at`

- `base_system_prompts` (UUID primary key)
  - `id` UUID, PK
  - `name` string, unique, NOT NULL
  - `prompt_text` text, NOT NULL
  - `inserted_at`, `updated_at`

- `personas` (UUID primary key)
  - `id` UUID, PK
  - `name` string, unique, NOT NULL
  - `prompt_text` text, NOT NULL
  - `inserted_at`, `updated_at`

Indexes & constraints:
- `unique_index(:agents, [:name])`
- `index(:agents, [:auth_id])` (filter lists by auth)
- `unique_index(:base_system_prompts, [:name])`
- `unique_index(:personas, [:name])`

Ecto schema notes:
- Agents: `@primary_key {:id, :binary_id, autogenerate: true}`; `@foreign_key_type :binary_id` for FK UUIDs; `belongs_to :saved_authentication, TheMaestro.SavedAuthentication, foreign_key: :auth_id, type: :integer`.
- JSONB fields typed as `:map` with changeset validation enforcing expected shapes.

## Generators

Run generators, then tweak migrations for UUID primary keys & defaults:

```
# Agents live CRUD (with JSONB fields and FKs)
mix phx.gen.live Agents Agent agents \
  name:string \
  auth_id:references:saved_authentications \
  base_system_prompt_id:references:base_system_prompts \
  persona_id:references:personas \
  tools:map mcps:map memory:map \
  base_system_prompt:text base_persona:text

# Base System Prompts CRUD
mix phx.gen.live Prompts BaseSystemPrompt base_system_prompts name:string:unique prompt_text:text

# Personas CRUD
mix phx.gen.live Personas Persona personas name:string:unique prompt_text:text
```

Migration adjustments (hand-edit):
- Use `create table(:agents, primary_key: false)` + `add :id, :binary_id, primary_key: true`.
- For `base_system_prompts` and `personas`: same UUID PK pattern.
- Set JSONB defaults for `tools`, `mcps`, `memory` to `%{}`.
- Add unique indexes on names.

## Context APIs

- Agents context
  - `list_agents/0`, `list_agents_with_auth/0` (preload `saved_authentication`, `base_system_prompt`, `persona`)
  - `get_agent!/1` (preload)
  - `create_agent/1`, `update_agent/2`, `delete_agent/1`, `change_agent/2`
  - Changeset:
    - required: `[:name, :auth_id]`
    - length & format on name: 3–50 chars, `^[a-zA-Z0-9_-]+$`
    - `tools`, `mcps`, `memory` default `%{}` and validate map
    - optional FKs for prompt/persona; use `foreign_key_constraint/2`

- Prompts context: full CRUD for `BaseSystemPrompt` (name + prompt_text)
- Personas context: full CRUD for `Persona` (name + prompt_text)

## LiveView UX

- Dashboard
  - Add an “Agents” section under Auths
  - “Create Agent” button → opens modal (LiveComponent) reusing the generator’s `FormComponent`
  - Fields in modal:
    - Name (text)
    - Saved Auth (select from DB; label: "<auth.name> — <provider>/<auth_type>")
    - Base System Prompt (select; fetched from `base_system_prompts`)
    - Persona (select; fetched from `personas`)
    - Tools (placeholder – JSON saved as `{}`)
    - MCPs (placeholder – JSON saved as `{}`)
    - Memory (placeholder – JSON saved as `{}`)
  - After create/update/delete, stream card list to stay snappy

- Agent Cards
  - Show: name, auth summary, prompt/persona names, counts for tools/mcps, preview of prompts
  - Actions: View, Edit, Delete (use generated routes for deep links)

- Auth deletion UX
  - Disable/block delete when `agents` exist for `auth_id` (FK is `:restrict` anyway)
  - Surface a friendly message: “Cannot delete: X agents reference this auth”
  - Auth deletion is exposed only in the Auths section/menu (not via Agent screens)

## Validation & JSONB structure

- Store `memory` as JSONB. Enforce structure with a typed struct and `validate_change`:
  - Example element: `%{type: :file | :url, value: binary, meta: map}`
  - Changeset can normalize list → map or pass-through; persisted as JSON while validating shape.

## Testing

- Changeset unit tests: name validations, FK constraints, JSON map validation
- LiveView tests: create via modal; edit; delete; error rendering; streaming updates
- Restriction tests: attempt to delete an auth with dependent agents → changeset/DB error + handled UI message

## Implementation Steps

1. Run generators for Agents, BaseSystemPrompts, Personas
2. Edit migrations for UUID PKs, defaults, indexes; migrate
3. Wire contexts: preload helpers, validations for JSON maps
4. Integrate modal on Dashboard reusing generated FormComponent; supply select options from contexts
5. Render Agents cards grid on Dashboard with stream updates
6. Update Auth deletion handler to check dependencies and flash friendly message
7. Add tests (changesets & LiveView)

## Best Practices Applied
- DRY: reuse generator’s FormComponent across routes and dashboard modal
- Separation of concerns: contexts own business logic; LiveViews render/state only
- Data integrity: FK + `:restrict` for auth deletion; unique indexes
- JSONB with progressive typing: validate shapes in changeset, keep storage flexible
- Preloading to avoid N+1 in UI
- Clean HEEx (no heavy logic), concise assigns, minimal antipatterns

