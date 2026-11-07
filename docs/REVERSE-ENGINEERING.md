# Reverse-engineering notes

Razer doesn't publish the Naga V3 Pro's protocol. Everything here was worked out on macOS with
`tools/razerprobe.swift`. The detailed findings (command bytes, button IDs, what's still unknown)
are kept in [`CLAUDE.md`](../CLAUDE.md) at the repository root.

## razerprobe
A command-line tool for exploring the mouse. Most commands only read; anything that writes needs `--yes`
and saves the previous value first.

```bash
swiftc -O tools/razerprobe.swift -o razerprobe -framework IOKit
./razerprobe list                 # Razer HID interfaces
./razerprobe info                 # firmware, DPI, battery…
./razerprobe buttons              # decoded button mappings
./razerprobe backup my.json       # save all mappings (read-only)
./razerprobe restore my.json      # show differences; add --yes to write them
./razerprobe help                 # everything else
```

## Capturing what Synapse sends (for features not decoded yet)
1. On a Windows PC, install Razer Synapse, Wireshark, and USBPcap (offered by the Wireshark installer).
2. Start a capture on the mouse's USB root hub, make ONE change in Synapse, and stop the capture.
   Repeat for each item on the checklist in `CLAUDE.md`.
3. Filter for `usb.setup.bRequest == 9 && usb.setup.wLength == 90` and export the packets.
   Diffing them against the known 90-byte format shows the new command and its arguments.
