# Changelog

## 1.0.0 — 2026-11-01

First release, for mod-romance 1.0.0 (protocol version 1).

- Tabs: Companion, Chat, Personality, Player Profile, Relationship, Settings, and a small Debug tab.
- Memory viewer: filter, search, edit, pin, delete, add, clear, full reset, export and import.
- Companion state shown accurately ("active", "not active yet"), with an "Activate AI" button.
- Custom dark input fields with a gold border (the stock 3.3.5 input template was nearly invisible on dark panels).
- Minimap button, `/romance` and `/ar`, remembered window position, per-character local chat log.
- Paced protocol sender that stays below AzerothCore's addon flood protection.
- Headless tests under a strict 3.3.5a API stub, plus wire-format interop with the server.
