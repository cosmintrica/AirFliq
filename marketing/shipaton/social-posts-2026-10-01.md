# Social posts, October 1, 2026

Posts tagged #Shipaton count for the #BuildInPublic award until September 30, 23:45 PDT (October 1, 09:45 in Romania). Add each published link to Devpost (Additional info, Build in Public links).

Published on X:
- https://x.com/cosmintrica/status/2105481756384407586 (macOS 27 AirDrop lesson, with a developer reply)

## r/macapps

Check the subreddit rules and pick the developer or self-promotion flair before posting.

**Title:** I made AirFliq: AirDrop any file on your Mac in one move (right-click, drag target, shortcut or menu bar)

**Body:**

Getting to the AirDrop panel on the Mac always took me three or four clicks, so I built AirFliq.

It opens Apple's own AirDrop panel in one move:

- Right-click any file in Finder > Send with AirFliq
- Drag a file and drop it on a small magnetic target that appears next to your cursor (the card folds into a paper plane and flies off)
- Press a global shortcut (⌃⌥A by default) and pick a file
- Or click the menu bar icon

Privacy: files only go through Apple's AirDrop. No account, no servers, and it reads only the folders you choose (no Full Disk Access).

Pricing: free with 5 sends a day (version 1.0.1, now in App Review), a 7-day unlimited trial that never charges automatically, and a one-time Lifetime Pro. No subscription.

Mac App Store: https://apps.apple.com/us/app/airfliq/id6801543708
62-second demo: https://youtu.be/d5o6kD_NpCk

It's my entry for RevenueCat's Shipaton. I'd love feedback, especially on the setup flow and what you would want next.

## r/SideProject

**Title:** I built a Mac app that turns AirDrop into one move, and found a macOS 27 quirk on the way

**Body:**

AirFliq is a small macOS menu bar app: right-click a file in Finder, drop it on a magnetic target next to your cursor, press a shortcut or click the menu bar, and Apple's AirDrop panel opens. When you drop a file on the target, the card folds into a paper plane and flies off the screen.

Two things I learned shipping it for #Shipaton:

1. Optional means skippable. My first release had a setup step for the Finder extension that people could get stuck on. Version 1.0.1 lets you skip any optional step and shows a small guide beside System Settings that notices the moment you flip the switch.
2. Don't trust "success" callbacks blindly. On macOS 27, cancelling the AirDrop panel still tells the app the files were shared, with exactly the same data as a real send. My free tier (5 sends a day) was counting sends that never happened, so 1.0.1 never charges a free send for a cancelled panel.

Free with 5 sends a day, a 7-day trial that never charges automatically, and a one-time Lifetime Pro through RevenueCat. No subscription.

Mac App Store: https://apps.apple.com/us/app/airfliq/id6801543708
Demo: https://youtu.be/d5o6kD_NpCk
Code: https://github.com/cosmintrica/AirFliq

## r/swift (or r/macosprogramming)

**Title:** PSA: on macOS 27, NSSharingService (AirDrop) reports a cancel as didShareItems

**Body:**

If you use `NSSharingService(named: .sendViaAirDrop)` and treat `sharingService(_:didShareItems:)` as success, cancels look like successful sends on macOS 27.

What I measured with a small probe app and the unified log:

- Cancel: `didShareItems` with the same items as a real send. `didFailToShareItems` is never called.
- Real send, then Done: `didShareItems` with identical items.
- No interaction: no callback at all.

I tried to tell them apart inside the process: delegate arguments, NSItemProvider loads, the ShareKit windows (classes starting with `SHK`) and ShareKit's own log sequence are identical, including "transition out with success 0" for both. Checking whether the sheet was still on screen looked promising in one probe run, but it turned out to be a race.

The only place that knows is `sharingd`: its AirDrop session metric records `transfersInitiated`, which is out of reach for a sandboxed app. So if you meter sends, don't count `didShareItems` on macOS 27.

Has anyone found a reliable public signal for "the user actually sent something"? I'd love to hear it. Found while building AirFliq for #Shipaton: https://github.com/cosmintrica/AirFliq
