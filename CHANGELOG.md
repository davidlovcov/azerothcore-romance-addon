# Changelog

## Unreleased

### Added
- Quests tab: the quests of the whole group (who has which, who is done) and the quests available around. Change the order with Up / Down and "Apply order" (the leading companion switches right away), "Lead" sends the selected companion there, "Ignore" keeps a quest from ever being picked up or done, "Abandon" (click twice) drops it for every companion. Replaces the Character tab's quest order window. Needs mod-romance 1.1.1.
- Quests tab: "Share" per group quest (enabled when the quest can be shared and someone lacks it; the tooltip names who) and "Take" per quest around, which shows who can take it (companions, and "you"). Taking an ignored quest unignores it.
- Commands tab: "Send to" lists every companion who is with you (and party chat), so commands and macros no longer depend on the companion selected on the Companion tab.
- Two tab rows: general tabs on top, the tabs about the selected companion (Chat, Character, Personality, Relationship, Settings) below, labelled with her name. The window is 22 pixels taller.
- Settings tab: "Wait for me to loot" (off by default) - after a fight she also waits for your loot.
- Commands tab: buttons for the common companion commands and your own ones, sent to the selected companion or to all of them in party chat. Macro mode makes a WoW macro from a button (it lands on your cursor for the action bar); "Make macros for all" creates them all.
- Character tab: "walking behind <name>" when another companion leads.
- Character tab: "Share quests" button (same as saying "share your quests").
- Settings tab shows the addon and the server module version, and warns when they differ.

### Fixed
- Quests tab: the last "Available around here" row overlapped the paging and the Refresh button; long rows are cut instead of wrapping into the next one.
- The tab row shrinks evenly when the tabs would not fit next to the Debug tab.
- The export window: the explanation no longer runs out of the window, and an export that is too large to show has no (useless) text box.
- Import / export no longer show "Too many requests": a step that hits the server's limit is sent again after a moment by itself. The memory list reloads at most every 2 seconds and not during a transfer.
- Minimap button: the icon is centered in its ring.
- After an import, the Memories and Relationship tabs sent a burst of requests ("get_memories: Too many requests"): memory changes are now collected and each tab reloads at most once per second.
- Imports of many memories stopped with "Too many requests, slow down" (and repeated the message): the addon now sends at a steady pace below the server's limit, and shows that message at most every 10 seconds.
- Export / import of many memories: transfers now run in pages with progress, a timeout and a clear error; an import changes nothing unless every part arrived. Exports too large for the text box are saved in the addon's saved variables, and "Import" with an empty box imports the last saved export.

### Changed
- Export / import has its own window: "Export" saves the memories in the addon and shows the text to copy; "Import..." lets you pick a saved export (the last one is preselected) or paste one. No more tiny text box.
- Playerbots' command feedback ("Following", "attack rti target: useless", quest notices) from your AI companions is hidden in the chat window and kept as gray `[Playerbots]` lines in the Chat tab. Answers to plain Playerbots commands still show. Settings tab: "Hide Playerbots feedback". Needs mod-romance 1.1.1.
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
