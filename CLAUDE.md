# Naga V3 Pro onboard remapper: project context

Goal: a macOS app that remaps the Razer Naga V3 Pro's buttons by writing to the mouse's onboard memory.
Razer Synapse doesn't support this mouse on macOS, and there is no public protocol documentation.

## What's confirmed (macOS, via tools/razerprobe.swift)
- Control interface: VID 0x1532, PID 0x00E7, usage page/usage 0x0001/0x0003, 90-byte feature reports, report ID 0.
- Razer 90-byte report: [0] status [1] transaction id [2-3] remaining [4] proto [5] size [6] class [7] cmd [8-87] args [88] crc = XOR of bytes 2..87.
- Transaction ID 0x1F works. Status: 01 busy, 02 ok, 03 failed, 04 timeout, 05 not supported.
- Reads work: firmware 01 01, serial OK, poll rate 1000 Hz, DPI 1600 (0x0640), battery 0xD2.
- Class 0x02 GET commands the mouse recognizes: 82 84 8C 8E 96 97 98 A2 A3 B0 B3 B4.
  With size 0x0A and no args, 8C and 8E return "failed" (they exist but need args).
  Hypothesis: 0x8C reads one button mapping with args (profile, button id, hypershift); its write counterpart is 0x0C.
- Class 0x03 has nothing (lighting on newer devices is class 0x0F).

## Button map: decoded (from mapscan)
- Read: class 0x02 cmd 0x8C, size 0x0A, args [profile, button, hypershift]. Profiles 00 and 01 answer identically.
- Reply: [profile, button, hypershift, action type, 01 (unknown, constant), params...]
  - type 01 = mouse button, params [01, n]. Buttons 01-05 = left/right/middle/back/forward; 09/0A = wheel up/down.
  - type 02 = keyboard key, params [modifier, HID usage]. Side buttons 1-12 = ids 0x40-0x4B -> keys 1..0,-,= (0x1E-0x27, 0x2D, 0x2E).
  - Not decoded yet: type 06 (ids 0B/0C), 07 (0E), 0C (39), 0E (34/35, maybe tilt), 12 (6A). Ids 0x50-0x55 also map to keys 1-6, purpose unknown.
- 0x8E answers for profile 01 only, ids 01-7F, all zeros (maybe macro slots or Hypershift; unknown).
- CONFIRMED write: class 0x02 cmd 0x0C, size 0x0A, same 10-byte layout. `setkey 01 4B 04 --yes` changed side button 12 from '=' to 'a', and the button now types 'a'.
- Still to confirm: survives unplug/power cycle; modifier byte = standard HID bitmask (01 Ctrl, 02 Shift, 04 Option, 08 Cmd); Hypershift layer (byte 2 = 01).

## Next step (superseded)
Build, then run `./razerprobe mapscan 8C` and `./razerprobe mapscan 8E`. If both get 0 hits, run `./razerprobe mapscan 8C 0A 01 swap`.
Default side buttons send keys 1-9, 0, -, =, which lets us decode the reply format.

## Safety rules
- Keep the probe read-only: only cmd >= 0x80. Do not add any write (SET) command until the button-map
  format is decoded and the user explicitly approves a single test write that reads the value back afterwards.
- Build: swiftc -O tools/razerprobe.swift -o razerprobe -framework IOKit

## Tooling now in tools/razerprobe.swift
- `backup <file.json> [profile]`: reads ids 01-7F on both layers (hypershift 0/1) via 0x8C and saves them as JSON (format naga-config/1). Read-only.
- `restore <file.json> [--profile XX] [--yes]`: diffs the file against the mouse; with --yes it writes only the differences via 0x0C and verifies each one.
- `set <profile> <button> key|mouse|dpi|raw ... [--hs] [--yes]`: writes one button, logs the old value to mapping-backup.txt, verifies, and prints an undo command. Left click (01) is never written.
- Partly decoded: type 06 = DPI (01 up?, 02 down?) on ids 0B/0C, which are the DPI buttons.

## Plan (user's goals)
1. Synapse-like assignments: keys+modifiers, mouse functions, DPI, profile switch, Hypershift, multimedia, macros, disable.
2. Rebind the DPI buttons (ids 0B/0C) and be able to restore them.
3. Back up the configuration to a file and restore it later, so the user can keep profiles for different uses.
4. Then a SwiftUI app on top of the same protocol code.

## Findings 2026-11-07 (factory.json)
- Profile 01 has 32 button ids: 01-05, 09, 0A, 0B, 0C, 0E, 34, 35, 39, 40-4B, 50-55, 6A.
- Byte 2 is NOT a Hypershift selector for reads: asking with hs=1 returns byte 2 = 00 and the normal-layer data. The Hypershift mechanism is still unknown (maybe class 02 cmds 96/97/98/A2/A3/B0/B3/B4).
- The 0B write (DPI button -> key b) verified, and restore put it back to type 06. Fixed: backup skips layer mismatches, restore skips duplicates.
- Physical button test (unknown ids temporarily set to letters):
  - 0x6A (type 12, param 01) = the scroll-mode button behind the wheel (smooth/free-spin vs. notched). It typed 'g'.
  - 0x39 (type 0C, param 39) = the third top button, to the right of right click. It typed 'f'. Its default function is not confirmed yet.
  - 0x0E (type 07, param 04) did not type 'e' on any button the user tried. Maybe the bottom profile button, or not a physical button.
  - 0x50 did not type 'h'. The side buttons kept 1..= so 0x50-0x55 aren't the physical side buttons. Purpose unknown.
- CONFIRMED on the physical button: with 0x0B remapped to key b, pressing the DPI-up button typed 'b'. Restore put DPI back. DPI buttons can be rebound and reverted.
- 0x39 (third top button) does nothing even at factory settings, so type 0C is probably "unassigned/default". The button is free to assign.

## Physical button map (CONFIRMED 2026-11-07)
| id | physical button | factory action |
|----|-----------------|----------------|
| 01-05 | left, right, middle (wheel click), back, forward | type 01 mouse n |
| 09/0A | wheel up/down | type 01 mouse 09/0A |
| 0B | front DPI button | type 06 param 01 = DPI up |
| 0C | rear DPI button | type 06 param 02 = DPI down |
| 0E | profile button on the bottom | type 07 param 04 = profile cycle (probably) |
| 34/35 | wheel tilt left/right | type 0E params 68/69 00 14 = repeating tilt, interval 0x14 |
| 39 | third top button (right of right click) | type 0C param 39 = unassigned (does nothing) |
| 6A | first button behind the wheel | type 12 param 01 = scroll-mode toggle |
| 40-4B | side buttons 1-12 | type 02 keys 1..0 - = |
| 50-55 | none found | type 02 keys 1-6, purpose unknown |
- The second button behind the wheel has no ID in the 0x8C map, so it can't be remapped yet. It may be handled directly by the firmware.

## Report 05 on interface 0x0001/0x0006 (2026-11-07, corrected)
- Pressing the scroll-mode button (id 6A, first button behind the wheel) sends report ID 05: `05 39 01` and then `05 39 00` on the next press.
  It alternates with each press, so it's most likely a scroll-mode STATE notification, not a press/release pair.
  (An earlier note guessed that type 0C = "host event"; that is NOT supported by this data.)
- The AI Prompt Master button (2nd button behind the wheel) sent nothing on 0x0001/0x0003 or 0x0001/0x0006.
  The pointer interface (0x0001/0x0002) hasn't been checked yet: run `listen 10 --mouse`.
- It is marketed as rebindable but isn't in the 0x8C map. It may need to be enabled by a command Synapse sends (0x8E table? other class 02 commands?).
- `listen --mouse`: the AI Prompt Master button sends NOTHING on any of the four interfaces, pointer included.
  Conclusion: it's inactive at the firmware level, probably until Synapse sends an enable or mapping command we haven't seen.
  Parked until a Windows Synapse USB capture is available (that capture should also cover macros and media keys).

## Swappable side panels (CONFIRMED 2026-11-07)
- 12-button panel = ids 40-4B. 6-button panel = ids 50-55: top row front-to-back 50, 51, 52; bottom row front-to-back 55, 54, 53 (keys 1 2 3 / 6 5 4).
  2-button panel = ids 04 (back) and 05 (forward).
- The mouse stores all three panels' mappings at the same time (all readable with the 12-button panel attached), so nothing is stored in the panels.
  The mouse presumably detects which panel is attached and uses that panel's ids.
- Possible lead: class 02 cmd 84 returned `21 01 02 0B 0C 0E 03 34 35 6A`, which looks like a list of button ids. Maybe the active button set, or related to the attached panel. Not tested.

## Onboard profiles (2026-11-07)
- 0x8C answers for profiles 02, 03, 04 and 05 too (side 1 = key 1 in each), so there are at least 5 onboard slots plus 00.
- Class 05 GETs that answer: 80 -> [01], 81 -> [05 01] (size 2), 84 -> [01], 8A -> [05]. All others fail.
  Guess: 8A = number of profiles (5); 80/84 or 81 byte 2 = active profile (01). Next: press the bottom profile button and see which values change.
- Pressing/holding the bottom profile button changed none of 05/80, 81, 84, 8A. Theory: factory has only 1 profile enabled,
  so cycling has nothing to cycle to (81 = [05 01] might mean 5 slots, 1 enabled). Testing class 05 cmd 04 [n] as "set active profile" via `setprofile`.
- class 05 cmd 04 [02] -> status FAILED; cmd 04 [01] -> status OK. So 0x04 is very likely "set active profile",
  and it refuses slot 2 because that slot isn't enabled. Mapping data CAN be written to slots 02-05 (0x0C on profile 02 verified).
  Missing piece: the command that enables or creates a profile slot. Next: read-only per-slot probes of class 05 GETs with a slot argument.
- Class 05 GETs 82 83 85 86 87 88 89 8B 8C with a slot argument (01 or 02): ALL failed. No read-only way found to see which slots are enabled.
  Enabling profile slots is parked for the Windows capture. Candidates if blind-testing later: 05/00 or 05/01 (write versions of 80 [01] and 81 [05 01]).

## Windows Synapse capture checklist
1. Rebind the AI Prompt Master button (to see how it's enabled).
2. Add a 2nd onboard profile and switch to it (how slots are enabled and switched).
3. Assign a short macro.  4. Assign a media key (volume up).  5. Set a button to Disable.  6. Assign a Hypershift action.

- CONFIRMED: modifier byte 0x08 = Command. Side button 12 set to modifier 08 + key 04 selects all, so the byte is the standard HID modifier bitmask (01 Ctrl, 02 Shift, 04 Option, 08 Cmd).
