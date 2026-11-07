# Naga Remapper for macOS

Remap the buttons on a **Razer Naga V3 Pro** from a Mac. Razer Synapse doesn't support this mouse on macOS.
Changes are written to the mouse's own memory, so they keep working on any computer, without this app running.

> **Unofficial and use at your own risk.** This project is not affiliated with, endorsed by, or supported by Razer.
> It writes settings to your mouse's onboard memory using a protocol that was reverse-engineered, not documented,
> and it has only been tested on one Naga V3 Pro (firmware 1.01). It is provided "as is", without warranty of any kind.
> Save a backup of your mouse before changing anything (see [Disclaimer](#disclaimer)).

## What you can do
- Remap the 12-, 6- and 2-button side panels, right click, wheel click, wheel tilt, the DPI buttons,
  the scroll-mode button, top button 3 and the profile button. Left click is locked so you can't lose it.
- Assign keyboard keys (with ⌃ ⌥ ⇧ ⌘), mouse functions, DPI up/down, scroll left/right, scroll-mode toggle or profile cycle.
- Save the whole setup to a file and load it later, for example one file for games and one for work.
- Reset everything to factory defaults.

Not supported yet: macros, media keys, disabling a button, Hypershift, launching apps, the AI Prompt Master button,
and switching between the mouse's onboard profiles.

## Connect by USB to configure
The mouse must be connected **over USB** while you change settings: either the **USB cable** or the
**HyperSpeed wireless USB dongle**. **Bluetooth is not supported** for configuring the mouse.

Your button mappings are saved on the mouse itself, so once they're applied you can switch back to Bluetooth
(or use the mouse on another computer) and they keep working.

## Download (easiest)
Get the latest **NagaRemapper-….zip** from the [Releases page](https://github.com/YOUR-USERNAME/YOUR-REPO/releases),
unzip it, and move **Naga Remapper.app** to Applications. It runs on Apple silicon and Intel Macs with macOS 13 or later.
Connect the mouse by USB cable or the HyperSpeed dongle before opening it.

The app isn't notarized by Apple, so macOS blocks it the first time. Try to open it once, then go to
**System Settings › Privacy & Security** and click **Open Anyway**. Then follow steps 3 and 4 below.

## Build it yourself
### Requirements
- macOS 13 (Ventura) or later.
- **Xcode Command Line Tools.** This is the only thing to install: it includes `git`, the Swift compiler and `codesign`.
  The full Xcode app isn't needed. Install it from Terminal:
  ```bash
  xcode-select --install
  ```
  If it says the tools are already installed, you're set.
- A Razer Naga V3 Pro connected **over USB**: the USB cable or the HyperSpeed wireless USB dongle. Bluetooth won't work.

### Install
1. Download the code:
   ```bash
   git clone https://github.com/YOUR-USERNAME/YOUR-REPO.git
   cd YOUR-REPO/app
   ```
2. Build the app (takes a minute the first time):
   ```bash
   ./build-app.sh
   ```
   This creates **Naga Remapper.app** in the `app` folder. You can drag it into Applications.
3. Open it. macOS asks to allow **Input Monitoring**. Allow it in
   System Settings › Privacy & Security › Input Monitoring, then quit and reopen the app.
   If you rebuild the app later, macOS may ask again.
4. **Save a backup first:** click **Save…** before changing anything.

## Using it
- The app reads your mouse when it opens. Pick a new action for any button. Changed buttons get an orange dot.
- Click **Apply to Mouse** to write the changes. Each one is read back to confirm it took.
- **Open…** loads a saved file, **Factory Defaults** restores the original layout, and **Revert** drops unapplied changes.
  These all still need **Apply to Mouse**.

## Troubleshooting
- **"Razer Naga V3 Pro not found"**: the mouse must be connected over USB (cable or HyperSpeed dongle), not Bluetooth.
  Switch the mouse's connection mode, then click **Read from Mouse**. Close Razer Synapse if it's installed.
- **"Couldn't open the mouse"**: Input Monitoring isn't allowed yet (see step 3). Quit and reopen the app after allowing it.

## For developers
`tools/razerprobe.swift` is the command-line tool used to work out the protocol, and `CLAUDE.md` holds the findings.
See [docs/REVERSE-ENGINEERING.md](docs/REVERSE-ENGINEERING.md). Help with the unsupported features is welcome,
especially USB captures from Razer Synapse on Windows.

## Making a release (maintainers)
On GitHub, go to **Releases › Draft a new release**, create a tag such as `v0.1.0`, and click **Publish release**.
GitHub Actions then builds a universal app (about 5 minutes) and attaches the zip to that release,
along with install instructions. To test a build without releasing, use **Actions › Release › Run workflow**.

## Disclaimer
This software is provided "as is", without warranty of any kind, express or implied, including but not limited to
the warranties of merchantability, fitness for a particular purpose and noninfringement. In no event shall the
authors or copyright holders be liable for any claim, damages or other liability arising from, out of or in
connection with the software or its use. See [LICENSE](LICENSE) for the full terms.

In particular:
- Using this app may affect your mouse's configuration or behavior, and may affect your warranty or support from Razer.
  You use it entirely at your own risk.
- The protocol was worked out by experiment and may be wrong for other firmware versions or hardware revisions.
- Razer Synapse may overwrite settings made with this app, and this app may overwrite settings made with Synapse.

Razer, Naga, Synapse, HyperSpeed and HyperScroll are trademarks of Razer Inc. They are used here only to identify
the hardware this project works with. This project is independent and not affiliated with Razer Inc.

## License
[MIT](LICENSE) © 2026 Scott Harvey
