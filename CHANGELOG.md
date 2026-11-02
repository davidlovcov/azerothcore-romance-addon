# Changelog

## Unreleased

### Fixed
- Export / import of many memories: transfers now run in pages with progress, a timeout and a clear error; an import changes nothing unless every part arrived. Exports too large for the text box are saved in the addon's saved variables, and "Import" with an empty box imports the last saved export.

### Changed
- Neutral wording in the Settings and Character tabs and the README, since companions can be male or female.

### Added
- Character tab: "Available nearby" lists quests the companion could pick up around you (giver, distance, direction, class quests marked).

## 1.1.0 — 2026-11-01

For mod-romance 1.1.0 (protocol version 1, new ops are additive).

### Added
- Character tab: level, XP, gold, bags, gear, quests and spells of the selected companion.
- Presets: gender-filtered list ("All genders" shows every preset), save / overwrite / delete your own presets, "Reset to preset", "Undo changes".
- Randomize buttons for story & taste (Personality tab) and for your own story (Player Profile tab).
- Estrangement shown in the companion list ("Left you (back in ~Nh)") and on the Relationship tab.

### Fixed
- The header switched to the selected character even when calling it failed (e.g. companion limit reached); it now names the companions that are really active.
- Error codes such as `limit_reached` are shown as readable messages.
- Significant moments refresh right after memories change.

## 1.0.0 — 2026-11-01

First release, for mod-romance 1.0.0 (protocol version 1).

- Tabs: Companion, Chat, Personality, Player Profile, Relationship, Settings, and a small Debug tab.
- Memory viewer: filter, search, edit, pin, delete, add, clear, full reset, export and import.
- Companion state shown accurately ("active", "not active yet"), with an "Activate AI" button.
- Custom dark input fields with a gold border (the stock 3.3.5 input template was nearly invisible on dark panels).
- Minimap button, `/romance` and `/ar`, remembered window position, per-character local chat log.
- Paced protocol sender that stays below AzerothCore's addon flood protection.
- Headless tests under a strict 3.3.5a API stub, plus wire-format interop with the server.
