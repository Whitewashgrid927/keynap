# KeyNap

A small, local macOS keyboard-cleaning utility. Swift, SwiftUI, AppKit and public
Quartz Event Services; macOS 26 or newer, Apple silicon.

## Use

Open /Applications/KeyNap.app. Select all keys, a group, a side, individual keys,
or drag an area. A drag replaces the selection; Shift-drag adds an area. Click
Lock to start cleaning. Violet means selected; amber means the lock is active.

The mouse and trackpad remain usable. Wake keyboard, the moon in the menu bar,
closing the window, or quitting releases the lock. Closing the last window quits
the process. Minimizing retains the lock and the menu-bar wake button. Hiding
the app, screen sleep, system sleep or leaving the login session releases it.
KeyNap always launches unlocked and never starts at login.

macOS may require a one-time grant in System Settings > Privacy & Security >
Accessibility. The Enable KeyNap button opens that panel. The app refreshes the
permission when you return. It never claims to be locked if creating the event
filter fails.

## Coverage and limits

The pictured keyboard uses MacBook US ANSI physical positions, including Fn and
inverted-T arrows. The selection applies to those key codes across connected
keyboards, rather than identifying a particular device. All keys also covers
ordinary extra keys on an external keyboard.

This filters input delivered to apps. It is not a hardware power switch. Touch ID
and power remain available. OS-reserved shortcuts and system-level actions can
run outside this event stream, so they cannot all be guaranteed blocked. Public
NX media events for brightness, volume and playback are filtered when their
corresponding keys are selected; exact physical Fn-row behavior depends on the
keyboard and macOS configuration. Secure Keyboard Entry prevents starting a
lock; if it begins during cleaning, the lock ends on the next health check.

Selected modifiers are removed from forwarded key and mouse events. Unselected
left/right counterparts are preserved. For Caps Lock, forwarded events retain
the state present when locking began, but the hardware LED/latch can change.
Check Caps Lock after cleaning. Locking starts only when ordinary keys and
momentary modifiers are released.

## Resource and privacy behavior

No network access, telemetry, key text logging, screen capture, login item,
helper process, root daemon, web runtime, machine-learning model, animation loop
or display link. The event tap and a one-second health timer exist only while
locked. Idle UI updates only on user interaction or lifecycle notifications.
The event callback reads key identifiers and modifier flags, never characters,
and does not publish each keypress into SwiftUI.

Liquid Glass uses Apple's glassEffect inside one GlassEffectContainer. Default
production code never substitutes a simulated material. Reduce Transparency and
Reduce Motion are respected. The keys expose individual VoiceOver actions.

## Build and verify

Requires Xcode Command Line Tools with a macOS 26 or newer SDK on an Apple-silicon Mac.

Run the offline tests without a signing certificate:

```sh
./test.sh
```

To build the application, select an Apple signing certificate already available
in your local keychain. Supply its name or SHA-1 as an environment variable:

```sh
export KEYNAP_SIGNING_IDENTITY='your local Apple signing identity'
./build.sh
```

There is no personal signing identity in the source. The build uses hardened
runtime and verifies an Apple-anchored signature for `org.keynap.app`. Missing
signing configuration or ad-hoc application signing fails the build. Offline
tests do not need a developer identity or Accessibility approval.

The default output is `.build.noindex/output.noindex/KeyNap.app`. Set
`KEYNAP_BUILD_DIR` to use another build directory. Copy a successful build into
Applications before normal use. This script creates a local signed build;
public binary distribution requires a separate release/notarization process.
Signing certificates identify their owner in built apps even when the source
contains no personal attribution.

The app executable supports:

- --self-test: offline layout, selection and input-filter tests; no desktop
  events are posted.
- --system-test: requires Accessibility. Creates/removes a harmless global tap
  20 times, then verifies suppression/forwarding with events addressed only to
  the test process. It never locks the user's physical keys.
- --permission-status: reports Accessibility status for the current launch
  context. Terminal/Codex authorization can differ from a Finder launch.
- --close-test: opens an invisible test window, installs a harmless tap when
  authorized, closes the window and verifies that the app terminates.
- --preview PATH [--dark] [--locked] [--compact] [--denied]: renders a layout
  proof using the production geometry and text with flat material substitutes.
  These images do not prove native compositor optics.
- --profile-idle SECONDS: creates a window offscreen and measures its idle
  process. This excludes the cost of a visible desktop backdrop.

The live filter uses the same KeyboardFilter policy as the tests. macOS disabling
the tap causes an unlock rather than silently restarting interception. No lock
state is persisted.

## Color update: 1.0.1

The selection, Lock button, group controls and drag outline now use muted violet.
Selection text adapts for light and dark mode. Active cleaning remains amber.

## Publication

Build products, local environment files and signing exports are excluded by
`.gitignore`. Keep them out of commits and source archives. The source contains
no signing certificate, private key or developer account identifier.

When moving from a differently identified build, quit the old app and approve
the new app in Accessibility. Existing grants belong to their signed identity.

## License

MIT; see [LICENSE](LICENSE).

## Apple references

- [Liquid Glass custom views](https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views)
- [Quartz Event Services](https://developer.apple.com/documentation/coregraphics/quartz-event-services)
- [CGEvent tap creation](https://developer.apple.com/documentation/coregraphics/cgevent/tapcreate(tap:place:options:eventsofinterest:callback:userinfo:))
- Public SDK headers CGEvent.h, HIToolbox/Events.h and IOKit/hidsystem/IOLLEvent.h
  specify the event contract, physical key codes and side-specific modifier bits.
