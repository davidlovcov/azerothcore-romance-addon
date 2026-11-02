# Changelog

## Unreleased (2.0.0)

### Renamed: AzerothRomance is now True Companion
- Addon folder `TrueCompanion`, `/tc` or `/companion`, new logo (window and minimap button) and colours. Romantic relationships stay a per-companion option ("Romantic relationship possible"). Needs mod-true-companion 2.0 (the module was renamed too).
- Your settings come along if you rename the saved variables file (README, "Upgrading from AzerothRomance"); memory exports made before the rename can still be imported.

### Added
- Commands tab: "Learn spells" (under More commands): she goes to her class trainer. The Character tab hint says so too.
- A companion with her AI conversation off is shown as "AI off - commands only": she still carries out commands (needs mod-true-companion 97ea6f8).
- The window header shows who leads and where to ("Rindronor leads to "Solanian's Belongings" (260 yd south)", "You lead"), and which companion is off on an errand.
- Character tab: spells she can learn now (with the cost at her class trainer) and soon, above the known ones; the hint says how to learn them ("!trainer learn" with the trainer targeted).
- Simpler by default; the extras are one click away and the addon remembers what you opened:
  - Quests tab: Lead / Share / Take only; "Edit list" shows the order (Up / Down, Apply, Reset), Ignore and Abandon.
  - Settings tab: the basics (AI, party chat, wait for loot, speaking up); "Show advanced settings" for spoken commands, listening in party, model, creativity and reply length.
  - Personality tab: presets, identity and "romantic relationship possible" first; "Customize story, traits & style" for the rest (a preset fills it all in).
  - Commands tab: the 8 everyday commands; "More commands" for the rest.
  - Companion tab: three "Getting started" steps until you call your first companion.
- Companion tab: without Ollama (off on the server or unreachable) it says "commands work, no conversation"; the module answers commands in plain words then.
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
- Chat tab: a message the AI can't answer (Ollama off, or her AI conversation off) left the "thinking" dots running forever; they stop now and the reason is printed.
- The leader line stopped updating for the whole session after one "too many requests"; only a server that doesn't know the request stops it now.
- Character tab: says when she can't afford the spells she could learn ("she has only ...").
- With Ollama switched off on the server, the header said "Checking Ollama..." forever; it says "AI off (commands only)" now (also on the Settings tab).
- The logo sits centred in its circle (the figures were a little low).
- Quests tab with a server module older than the addon: "server too old for Take" instead of "nobody can take it".
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
