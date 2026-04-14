# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

This is the **Производственный план** (Production Plan) module for altAwin — a window manufacturing ERP system. It consists of:

- `html/production-plan.html` — a single-file HTML view rendered inside altAwin's embedded browser
- `client-methods/*.pas` — FastScript (Object Pascal) server-side methods called via `Host.executeMethod()`
- `docs/sql/production-plan-schema.sql` — Firebird DDL to create DB objects (run once)
- `ALTAWIN_API.md` — reference for altAwin FastScript API (QueryRecordList, MakeDictionary, JSON functions, etc.)
- `docs/setup-instructions.md` — step-by-step deployment instructions

## Architecture

The HTML page communicates with the altAwin backend exclusively through `Host.executeMethod('methodName', params)`. Each `.pas` file in `client-methods/` is a script registered in altAwin's `SCRIPTMETHODS` table with parameters in `SCRIPTMETHODSPARAMS`.

Two operating modes (switchable in UI):
- **batchType = 1** — Столярка (carpentry)
- **batchType = 2** — Малярка (painting)

Each mode has its own partition of `VK_PROD_BATCHES` (keyed by `BATCHTYPE`). Orders are assigned to batches by writing to a UserField on `IdocOrder` — the UF IDs are stored centrally in `VK_PROD_SETTINGS` (`CARP_UF_ID`, `PAINT_UF_ID`).

## DB access

Always use the **MCP tool** (`mcp__mcp-firebird-vk__*`) to query or inspect the Firebird database. Never use Bash/node.js scripts for DB operations.

Key tables:
- `VK_PROD_BATCHES` — batches (`ID`, `BATCHNUMBER`, `BATCHTYPE`, `SORTORDER`, `DATE_START`, `DATE_END`)
- `VK_PROD_SETTINGS` — single-row config (`CARP_UF_ID`, `PAINT_UF_ID`)
- `SCRIPTMETHODS` / `SCRIPTMETHODSPARAMS` — registered client methods
- `HTML_VIEWS` — HTML source storage (BLOB field `SOURCEHTML`)

## FastScript rules (ALTAWIN_API.md)

- Parameters are accessed **directly by name** (not via Args)
- `QueryRecordList` requires a non-nil Params dict — use `MakeDictionary([])` when no params
- DATE fields: embed as string literals in SQL (`'2025-01-01'`), not as bind params (FastScript can't coerce OleStr to Date)
- Use `ReplaceStr` instead of `StringReplace` (FastScript's StringReplace takes only 3 args, no flags)
- To open a document: `Order := OpenDocument(IdocOrder, id); Order.ShowModal;`

## Deployment

There are no build commands. Deployment is manual:
1. Run `docs/sql/production-plan-schema.sql` in the target Firebird DB once
2. Update `VK_PROD_SETTINGS` with the correct UserField IDs
3. Register each `.pas` file as a client method in altAwin (see `docs/setup-instructions.md` §3)
4. **The user uploads** `html/production-plan.html` manually into `HTML_VIEWS` — do **not** attempt to upload it via MCP or scripts
