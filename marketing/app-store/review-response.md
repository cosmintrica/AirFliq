# Resubmission checklist — September 9 rejection

The rejected version was 1.0.0 (9). Use a build number higher than **every**
previously uploaded build, including Xcode Cloud uploads.

1. Build a signed App Store archive/package from this source and run
   `scripts/verify-app-store-build.sh` against the resulting app/package.
2. Test on a clean macOS user account: complete setup without granting Automation;
   invoke the shortcut and menu action; cancel the picker; select multiple files
   and a folder; drop onto the menu icon/drag target; enable Finder Sync and send
   from right-click. Verify the native AirDrop panel and complete a real transfer.
   Test the trial/purchase/restore flow with StoreKit sandbox credentials.
3. Replace **all** screenshots in **every** App Store locale with the four PNGs
   in `marketing/app-store/final/`. Remove the old fifth trial screenshot and
   any duplicated screenshots in other screenshot sets. No screenshot should
   show a price, a free offer or a paywall.
4. Remove the old optional App Preview from App Store Connect for this submission.
   `ComposeAppPreviewFilm.swift` and the Shipaton recordings are historical
   material: they include the old onboarding/menu/paywall. Do not upload them.
   Re-record any future preview from the corrected build and inspect every frame.
5. Update the description and reviewer notes using `metadata-en-US.md`, select
   the newly processed build, then send the response below and resubmit.

## Suggested response (send after uploading the corrected build and metadata)

Hello App Review,

Thank you for the feedback. We have addressed both issues:

- Guideline 2.4.5(i): The new Mac App Store build removes the Finder Apple Events
  temporary exception and the Automation entitlement. It does not request
  Automation permission or use AppleScript to read Finder selection. The global
  shortcut and menu action now open the standard macOS file picker. The Finder
  context-menu action uses our bundled Finder Sync extension. Drag-and-drop
  remains available. All routes open the native macOS AirDrop sharing service.
- Guideline 2.3.7: We have replaced the screenshots with feature-focused images
  without pricing or free-offer references and removed the previous trial/paywall
  screenshot and App Preview. Pricing information remains in the app description
  and the in-app purchase interface.

To test, open AirFliq from the menu bar and choose “Choose files to send…”, or
press the configured global shortcut, select files, and confirm the picker. To
use right-click, enable AirFliq's Finder extension through Setup → Enable Finder
Menu, then right-click a file in Finder and choose “Send with AirFliq”. The file
picker and drag workflows do not use Finder Automation.

The app requires no account. Please see the updated App Review notes for the
explicit 7-day Trial IAP and purchase restoration steps.
