# Original SmartTubeIOS Customizations

Migration specification for reimplementing the original local product behavior on a fresh checkout of upstream [SmartTubeIOS](https://github.com/milika/SmartTubeIOS).

This document describes **what the app should do**. It is not a patch, and it is not a request to copy the old player files onto current upstream.

## 1. Purpose and Migration Strategy

### Purpose

Start from a clean checkout of the latest upstream `master`. Reimplement the behaviors in [Original Customizations — Confirmed](#2-original-customizations--confirmed). Leave upstream architecture, playback lifecycle, and iOS player behavior in place except where a confirmed requirement changes the user-visible result.

### What counts as original

The original customizations are the uncommitted local work that existed on upstream commit `64562f5` (15 August 2026, “Merge pull request #131”, tvOS playback-control clipping) and was saved on 20 October 2026 as commit `0d82234` (“Save custom SmartTube modifications”).

That commit is the tip of `my-customizations`, `master`, `backup-before-upstream`, and `backup-integrate-attempt`. The same tracked diff is in `~/Desktop/smarttube-changes.patch` (20 October 2026). `~/Desktop/smarttube-staged-changes.patch` is empty. `~/Desktop/SmartTubeIOS-backup` is that same tree, still dirty on `64562f5`, plus a few untracked files that were not part of the saved commit.

Intent is written down in `docs/keyhou-tvos-player-work.md` on commit `0d82234` only. That note is dated 2 September 2026 and says the work was uncommitted on local `master` at `64562f5`. Its eleven sections match the code in `0d82234`. Where the note and the diff disagree, this document says so in [Partially Recovered or Uncertain](#3-original-customizations--partially-recovered-or-uncertain).

### What this document does not preserve

- The later port onto upstream `e659ce9` (`integrate-upstream`, October 20–22 2026). That working tree reimplements the same goals on a newer player. It is not a second product. See [Later Work](#9-later-work--not-confirmed-as-original).
- Git history, file layout, or line-level edits from `0d82234`.
- Personal signing, bundle identifiers, App Groups, entitlements, or the large `Localizable.xcstrings` reorder.

### How to reimplement

1. Check out the latest upstream. Do not merge `my-customizations`.
2. Implement the confirmed behaviors against the current types and files. Names in “Implementation clues” are locators from the August 2026 tree. Current upstream may have split or renamed them.
3. Keep upstream’s stream-selection pipeline. Add 4K selection at the quality-picker and quality-switch seam. Do not paste the old `PlaybackViewModel+Fallback.swift` over the current file.
4. Add the unit tests named below. Update tvOS UI tests only where navigation or HUD identifiers changed.
5. Verify the tvOS remote behaviors on an Apple TV with a Siri Remote 2 clickpad. The Simulator does not decode VP9/AV1 and does not reproduce clickpad press-down.

## 2. Original Customizations — Confirmed

Confidence values:

- **Confirmed** — living notes and the `0d82234` diff agree.
- **Strongly supported** — present in the diff, consistent with the notes, with a small inference called out in the item.

### 2.1 Hardware Play/Pause toggles once

| | |
|---|---|
| Feature | One physical Play/Pause press toggles playback exactly once. |
| User-facing behavior | Pressing Play/Pause on the Siri Remote pauses or resumes. A second automatic delivery of the same press does not immediately undo it. |
| Platform | Shared playback view model. The double delivery is a tvOS remote problem. The guard is harmless on iOS and macOS. |
| Expected behavior | `togglePlayPause()` ignores a second call within **120 ms**. Hardware Play/Pause still reaches that method from the player, the HUD, the more menu, pickers, and the SponsorBlock skip toast. |
| Edge cases | A real second press inside 120 ms is also ignored. Both SwiftUI `.onPlayPauseCommand` and `MPRemoteCommandCenter.togglePlayPauseCommand` call the same method; the debounce is what makes the pair safe. UI tests that pass `--uitesting-show-controls` already suppress auto-hide; do not let the debounce break those tests. |
| Implementation clues | `lastTogglePlayPauseTime` on `PlaybackViewModel`. Guard in `togglePlayPause()` (`PlaybackViewModel+Controls.swift`). Helper `onPlayerPlayPause`. `TogglePlayPauseDebounceTests`. |
| Confidence | Confirmed |
| Dependencies | Must keep working while a HUD dropdown or the more menu is open (2.2, 2.4). |

### 2.2 tvOS player HUD: Like, Dislike, Speed, Captions, Quality

| | |
|---|---|
| Feature | Dedicated top-right player buttons, in addition to the existing more menu. |
| User-facing behavior | The top row of the tvOS transport is Back, Channel, Like, Dislike, Speed, Captions, Quality, More. Speed shows the current rate (`1×` at normal, otherwise a general format such as `1.6×`). Captions show Off or the language. Quality shows the current label or Auto. Select on Speed, Captions, or Quality opens a dropdown under that button. Select on Like or Dislike uses the existing like/dislike actions. Select on More still opens the more menu, which keeps the same actions. |
| Platform | tvOS. iOS and macOS keep their existing sheets and menus. |
| Expected behavior | Dropdown rows are native buttons. The current value takes default focus. Menu closes the dropdown. Play/Pause still toggles inside it. Opening a picker or the more menu keeps the chrome up and cancels auto-hide. Closing it leaves the top-right button that opened it highlighted, and auto-hide starts again (2.10). A Select that the second-generation remote can emit after a row confirms is swallowed for about **350 ms** so focus does not jump to Play/Pause. |
| Edge cases | Like and Dislike run only when the user is signed in (`vm.like()` / `vm.dislike()`). They do not add a new rating API. The more button uses a circle stroke plus the light-blue highlight when focused (2.3). Center Rewind, Play/Pause, and Forward must not overlap when the focused one scales up. |
| Implementation clues | `TVPlayerControl` cases `.like`, `.dislike`, `.speed`, `.captions`, `.quality` in `PlayerView+tvOS.swift`. `tvActivateControl`. `lastTVOverlayDismissTime`. HUD construction in `PlayerView+ControlElements.swift`. `TVPlayerControlsUITests` (`testSpeedCaptionsQualityButtonsExistInControls`, picker-open tests, `testCenterTransportControlsDoNotOverlap`). Accessibility identifiers: `player.likeButton`, `player.dislikeButton`, `player.speedButton`, `player.captionsButton`, `player.qualityButton`, `player.speedPicker`, `player.captionPicker`. |
| Confidence | Confirmed |
| Dependencies | 2.1, 2.3, 2.4, 2.5, 2.6, 2.9, 2.10. |

Top-row order, left to right: Back, Channel, Like, Dislike, Speed, Captions, Quality, More.

Center row: Rewind, Play/Pause, Forward.

Bottom row: Previous video, previous chapter, next chapter, next video. Chapter buttons are omitted when the video has no chapters; left/right then jump between previous and next video.

D-pad while a HUD button is highlighted uses this map (the focus engine must not also move focus, or the highlight double-steps):

- Left/right move along the current row.
- Up from Play/Pause goes to Captions. Up from Rewind goes to Like. Up from Forward goes to More.
- Down from Captions goes to Play/Pause. Down from Back, Channel, Like, Dislike, or Speed goes to Rewind. Down from Quality or More goes to Forward.
- Up from the bottom row goes to Rewind for the left-side buttons and Forward for the right-side buttons.
- Down from the center row goes to the previous-chapter side or the next-chapter side, or to previous/next video when there are no chapters.

### 2.3 tvOS focus appearance

| | |
|---|---|
| Feature | One light-blue focus treatment for the player HUD, feed cards, chips, library rows, and channel rows. |
| User-facing behavior | Focused controls and cards show a light-blue highlight, about RGB (0.55, 0.82, 1.0), with a translucent fill around 0.32 opacity, a stroke, a slight scale, and a tinted shadow. Home and Library chips: focused chip is a light-blue capsule with black text. Unfocused selected chips keep the previous primary/black treatment. |
| Platform | tvOS. |
| Expected behavior | Feed cards, chips, more-menu rows, and HUD buttons are native `Button`s with a pass-through button style: pressed opacity only, no Liquid Glass platter, system focus effect disabled, custom chrome drawn on the label. One clickpad OK activates the focused card. |
| Edge cases | Shorts cards get the same stroke, shadow, and scale. The Current Queue row on Home and Library is a button with the same row chrome so OK activates it. Channel video lists on tvOS use the same video-card button. |
| Implementation clues | `TVFocusStyle`, `TVImmediateSelectButtonStyle`, `tvFocusRowChrome`, `playerMenuButtonStyle()` in `ViewHelpers.swift`. `VideoCardView`, `ShortsCardView`, `ShortsRowSection`, `HomeView`, `LibraryView`, `ChannelListView`, `ChannelView`. |
| Confidence | Confirmed |
| Dependencies | 2.4. Feed chrome can ship after the player HUD, but the button style is shared. |

### 2.4 Siri Remote clickpad Select and player focus

| | |
|---|---|
| Feature | Clickpad OK / Select activates the highlighted player control on the first press, including Siri Remote 2. |
| User-facing behavior | Highlight any HUD button and press the clickpad once: that button runs. Picker rows still activate on one click. Hardware Play/Pause always toggles. With controls hidden, OK toggles play/pause and highlights Play/Pause. |
| Platform | tvOS. |
| Expected behavior | Three different Select targets: (1) popups, the more menu, and HUD dropdowns are native buttons; (2) HUD chrome buttons are native buttons, and only the highlighted one is in the focus engine; (3) when no HUD button owns focus, a focusable host view under the HUD receives arrows, Select, Play/Pause, and Menu. The video layer does not become focused. |
| Edge cases | See the remote matrix below. Select on press-down is required. A tap gesture or a zero-duration long-press on a generic focusable view misses Remote 2. A full-screen invisible button used as the only focus target removes the player from the focus system so no click works. Do not put a full-screen player button around the overlay buttons. While an overlay is open, the player body must not also receive move commands; omitting the modifier is required, because a no-op handler still registers and double-steps. When a picker closes on a top-row button, do not move default focus back to the host view. The host handles Select on both press-began and press-ended, with about an 80 ms debounce, so Remote 2’s click and Remote 1’s tap each fire once. |
| Implementation clues | `TVRemoteFocusHost` in `PlayerView+tvOS.swift`. `handleTVSelectPress`, `handleTVMoveCommand`, `handleTVExitCommand`. `PlayerAVLayerView` `canBecomeFocused = false` in `PlayerView+AVLayer.swift`. `tvOverlayControl` in `PlayerView+ControlElements.swift`. |
| Confidence | Confirmed |
| Dependencies | 2.1, 2.2, 2.3. |

Remote behavior while the host view is focused (no picker or more menu, no skip toast):

| State | Select / OK | Left / Right | Up / Down | Menu |
|---|---|---|---|---|
| Controls hidden, nothing highlighted | Toggle play/pause and highlight Play/Pause | Seek ±10 seconds (this ±10 s behavior already existed upstream and was kept) | Show controls and highlight Play/Pause | Stop playback and leave the player |
| Controls visible, nothing highlighted | Same as hidden: toggle and highlight Play/Pause | Seek by the user’s rewind/forward settings | Highlight Play/Pause and show controls | Hide the controls |
| A HUD button is highlighted | Activate it. If that button is Play/Pause, toggle play/pause. | Move highlight along the row (2.2) and keep controls visible | Move highlight between rows (2.2) and keep controls visible | Clear the highlight. Controls stay until the hide timer. |
| A picker, more menu, or other overlay is open | The overlay’s own buttons handle Select. The host ignores it. | The overlay handles movement. The player body must not. | Same | Close the overlay first. Do not leave the player. |
| Skip toast visible | Host ignores Select | — | — | — |
| Less than ~350 ms after a picker closed | Host ignores Select so the leftover click does not move highlight | — | — | — |

Menu closes overlays in this order: more menu, quality, speed, sleep timer, captions, audio track, description, comments.

### 2.5 Playback speed steps

| | |
|---|---|
| Feature | Two extra playback speeds, and a stored-value migration. |
| User-facing behavior | Speed choices are 0.25, 0.5, 0.75, 1.0, 1.25, 1.5, **1.6**, 1.75, **1.85**, 2.0. There is no 1.7×. Labels use a general number format so 1.25, 1.6, and 1.85 stay readable. 1.0× is shown as Normal in Settings and as `1×` on the HUD. |
| Platform | Shared. Settings, the iOS/macOS speed sheet, the tvOS HUD, and the TOS player all read `AppSettings.availableSpeeds`. |
| Expected behavior | On decode of the global `playbackSpeed`, a stored value within 0.01 of 1.7 becomes 1.6. |
| Edge cases | The migration runs on the global setting only. A per-channel value of 1.7 is not rewritten by that decode path (2.9). |
| Implementation clues | `AppSettings.availableSpeeds`. Settings picker format `"%g"`. Tests `availableSpeedsIncludes16And185`, `playbackSpeed17MigratesTo16`. Catalog key `%g×` was added for the label; do not port the rest of the strings-catalog reorder. |
| Confidence | Confirmed |
| Dependencies | None. The HUD (2.2) and per-channel overrides (2.9) display and store these speeds. |

### 2.6 4K / UHD in the quality picker, and playback of that choice

| | |
|---|---|
| Feature | 1440p and 2160p stay selectable when the HLS master tops out at 1080p, and choosing one actually switches stream. |
| User-facing behavior | The quality list includes HLS heights and any 1440p+ `video/mp4` row that has a URL, even when the HLS master does not list that height. Rows are highest first. Choosing a height the master does list keeps the existing HLS switch. Choosing a UHD MP4 height the master does not list reloads that format through DASH. |
| Platform | Shared playback. visionOS has an extra picker-enrichment step. |
| Expected behavior | After an HLS master is parsed: keep formats whose height is in the master; keep 1440p+ MP4 formats with a URL; if the master lists a height that adaptive formats omitted, synthesize a picker row for that height. Do not clear the selected format merely because its height is missing from HLS when it is a UHD MP4. On visionOS, after H.264 HLS (capped at 1080p) starts, fetch Android VR player info and add 1440p/2160p MP4 rows that are not `rqh`-enforced, without replacing the playing HLS item. |
| Edge cases | A UHD row with no URL is not “playable outside HLS”. Duplicate heights/MIME types are not added twice. If the Android VR request fails or the video has changed, the picker stays as it was. The Simulator cannot decode VP9/AV1; tests should assert which row is offered and which reload path runs, not that the frame decoded. |
| Implementation clues | `qualityPickerFormats` and `VideoFormat.isUHDPlayableOutsideHLS` in `QualityAndHistoryHelpers.swift`. `PlaybackQualityManager` DASH reload when the height is absent from `hlsVariantURLs`. `enrichPickerWithUHDFormats` and `PlayerInfo.appendingFormats`. Tests in `QualityAndHistoryHelpersTests` and `VisionOSPlaybackTests.visionOSPickerKeepsUHDMP4`. |
| Confidence | Confirmed |
| Dependencies | None. Do not replace upstream HLS for heights the master already offers. |

### 2.7 Resume position and YouTube watch history

| | |
|---|---|
| Feature | Opening a video resumes at the further of the local playhead and YouTube’s watched percent. Watching in the app updates the signed-in YouTube history. |
| User-facing behavior | A half-watched video opened from YouTube history resumes near that position. Watching further in the app moves the YouTube history progress. A newer local position is not thrown away for an older YouTube percent, and the reverse is also true. |
| Platform | Shared. |
| Expected behavior | Resume position is `nil` (start at the beginning) unless one of these yields a position **greater than 5 seconds**: the local saved position, if it is already greater than 5 seconds; or YouTube `percentDurationWatched` converted with the video duration, when the fraction is greater than 0.02 and less than 0.95. If both exist, use the larger one. Percent values are accepted as an integer (`45`), a double percent (`45.0`), or a number already between 0 and 1 (`0.45`). Numbers greater than 1 are divided by 100. While history is enabled, playback has a duration, and the video is playing, report a watchtime checkpoint about every **15 seconds**. When playback actually starts, send the playback-started ping without a zero-length interval. If account-bound tracking URLs arrive after that ping was sent on fallback URLs, send playback-started again on the account-bound URLs. |
| Edge cases | History reporting runs only when `historyState == .enabled`. YouTube ignores a watchtime segment whose start equals its end; upstream already avoided that on video change, and the new playback-started ping must not reintroduce a zero-length segment. The “already a fraction” branch has no fixture proving InnerTube sends 0…1. A raw value of `1` (which may mean 1%) is kept as 1.0 and then dropped by the `< 0.95` cutoff. See [Known Limitations](#7-known-limitations-and-unresolved-issues). |
| Implementation clues | `playbackResumePosition`, `parsePercentDurationWatched`. Call sites in `parseTileRenderer`, `parseVideoRenderer`, and `parsePlaylistVideoRenderer` (`InnerTubeAPI+VideoRenderers.swift`). Resume in `PlaybackViewModel+Loading.swift` from `video.watchProgress ?? info.video.watchProgress`. `lastWatchtimeCheckpoint` and the periodic observer in `PlaybackViewModel+Observers.swift`. `WatchtimeTracker.notePlaybackBegan` and the re-ping inside `setTrackingURLs`. Tests: `resumePositionPrefersFurtherProgress`, `percentDurationWatchedParsesJSONNumbers`, `tileRendererParsesIntegerPercentWatched`. |
| Confidence | Confirmed for the resume rule, the percent parser, the 15-second checkpoint, and the playback-started re-ping. The living notes also mention resolving `videoId` from several endpoints; that change is **not** in the diff. See section 3. |
| Dependencies | History must stay behind the existing history-enabled setting. Do not replace upstream’s watchtime flush on video change. |

On a newer upstream, keep the user-visible result (resume at the further playhead; signed-in watching updates YouTube history). If current upstream already checkpoints watchtime, do not add a second 15-second reporter on top of it. The October 2026 port was explicitly told not to copy `notePlaybackBegan` and the old periodic observer blindly. That was an integration constraint, not a withdrawal of the history requirement.

### 2.8 tvOS navigation: six sections, no Home chip bar

| | |
|---|---|
| Feature | tvOS uses a six-item top tab bar. iOS and macOS stay on four destinations. |
| User-facing behavior | tvOS tabs, in order: **Home, Search, Playlists, History, Library, Settings**. Subscriptions is not a tab. Home on tvOS is the interleaved feed only; the Home chip bar is gone. Playlists and History are locked feeds, not chips. Library chips on tvOS are **Subs, Recommended, Channels, Playlists, RSS Feeds**. History is the tab, not a Library chip. Downloads stay off tvOS. Settings → Visible Sections is hidden on tvOS, because it only edited Home chips. |
| Platform | tvOS for the six tabs, locked feeds, Library chip set, and hidden Visible Sections. iOS and macOS keep Home, Search, Library, Settings, and the existing Home chip bar. |
| Expected behavior | Each tvOS tab has accessibility identifier `tab.<lowercase name>` (`tab.home`, `tab.playlists`, …). Locked Playlists and History views reload when they appear. `BrowseViewModel.select` does nothing when the section is already current, so the locked tab must call `reload`. From the Home tab, two Right presses reach Playlists, four reach Library, and five reach Settings. On Home, Down once reaches the Shorts row and Down again reaches the video grid (the old chip bar is no longer a stop). Search can still be selected when the app posts the existing navigate-to-search notification. |
| Edge cases | iOS shows at most five tabs; do not add Playlists and History there. Library on iOS/macOS keeps its previous sections, including History and Downloads. Recommended and Channels are tvOS Library chips. The Current Queue row remains on both Home and Library. |
| Implementation clues | `AppSection.compactTabs` and `AppSection.tvTabs` in `RootView.swift`. `HomeView(api:lockedSection:)`. `LibrarySection` tvOS `allCases`. `SettingsView` wraps Visible Sections in `#if !os(tvOS)`. `AppSymbol.playlists` (`list.and.film`). `TVUITestHelpers.rightsToPlaylists = 2`, `rightsToLibrary = 4`, `rightsToSettings = 5`. UI tests wait on `home.feed`, not `home.chipBar`. `TVShortsDownNavigationUITests` expects two Down presses. |
| Confidence | Confirmed |
| Dependencies | 2.3 for chip and card focus. UI tests in section 6. |

### 2.9 Per-channel playback speed and captions

| | |
|---|---|
| Feature | Speed and caption language can differ by channel. Channels with no override keep the Settings defaults. |
| User-facing behavior | Set 1.5× and Spanish captions while watching channel A. Open channel B and get the Settings defaults. Settings → Playback Speed does not change when the HUD changes the current channel. Turning captions Off on a channel stays Off even when a global caption language is set. |
| Platform | Shared persistence and playback. The HUD is tvOS; iOS/macOS sheets and the TOS player must use the same resolved values. |
| Expected behavior | Store `channelPlaybackPreferences` keyed by channel id. Each entry has an optional speed, an optional caption language, and a `captionsOff` flag. Missing entry, or a missing field, inherits `playbackSpeed` and `preferredCaptionLanguage`. HUD and sheet pickers persist through the channel setters, then push settings into the view model and apply them. They must not assign the global `playbackSpeed` or `preferredCaptionLanguage` on the settings store. On load, apply the resolved speed and caption language. If player info later fills in a channel id the video did not have, apply again. Auto-applied captions use the resolved language: exact code, then a BCP-47 prefix (`en` matches `en-US`). HUD, more menu, and quick-access labels show the resolved speed. |
| Edge cases | No channel id: the setters write the global defaults. `captionsOff` must survive decoding when the key is absent (default false). The view model may copy the resolved speed and caption language onto its own settings snapshot so the player uses them; that copy must not be written back as the global default. Shorts playback on non-tvOS uses the resolved speed for that channel. The small TOS player change does the same. |
| Implementation clues | `ChannelPlaybackPreference`, `resolvedPlaybackSpeed(for:)`, `resolvedCaptionLanguage(for:)`, `setPlaybackSpeed(_:forChannel:)`, `setCaptionLanguage(_:forChannel:)` on `AppSettings`. `applyChannelPlaybackPreferences()` on `PlaybackViewModel`. `persistPlaybackSpeed` / `persistCaptionSelection` in `PlayerView+PickerOverlays.swift` and `PlayerView+ControlElements.swift`. `autoApplyCaptionPreference` in `PlaybackViewModel+Captions.swift`. Tests `channelPlaybackPreferencesOverrideGlobal`, `channelCaptionsOffDoesNotInheritGlobal`, `channelPlaybackPreferencesRoundTrip`. |
| Confidence | Confirmed |
| Dependencies | 2.2, 2.5. Global Settings speed remains the default for channels without an entry. |

### 2.10 Player chrome auto-hides again after a picker closes

| | |
|---|---|
| Feature | The player overlay hides on the existing timer after a HUD picker or the more menu closes. |
| User-facing behavior | Open Speed, Captions, Quality, or More, then close it. The HUD stays during the overlay. After it closes, the HUD disappears after the normal hide interval (default **4 seconds**, `settings.controlsHideTimeout`; tvOS uses 1.5× that value when the existing landscape rule says so). The top-right button that was used stays highlighted until then. |
| Platform | tvOS player chrome. The restart helper lives on the shared view model. |
| Expected behavior | Opening a picker or menu calls show-controls and cancels the hide timer. Closing calls show-controls **without** cancelling the timer, so the timer starts again. When any overlay goes from visible to hidden, resume auto-hide if the controls are currently visible. Do not return early and leave the timer cancelled. Do not restart the timer while `--uitesting-show-controls` is set; that launch argument already forces the controls to stay up for UI tests. |
| Edge cases | The SponsorBlock skip toast is not an overlay for this timer. Closing a picker must not clear the top-row highlight (2.2, 2.4). |
| Implementation clues | `PlaybackViewModel.resumeControlsAutoHide()`. `PlayerView+Lifecycle.swift` `onChange(of: isAnyOverlayVisible)`. |
| Confidence | Confirmed |
| Dependencies | 2.2, 2.4. |

### 2.11 Dedicated Shorts browse list hides non-shorts

| | |
|---|---|
| Feature | The Shorts section and its next page drop items that are not classified as shorts. |
| User-facing behavior | The Shorts shelf does not show ordinary videos that the Shorts endpoint returned. |
| Platform | Shared browse model, so every platform that opens the Shorts section. |
| Expected behavior | After `fetchShorts()` and `fetchShortsMore`, keep only videos with `isShort == true`. |
| Edge cases | The Home interleaved shelf already filtered shorts before this change. This item is only the dedicated Shorts section. The living notes do not mention it. |
| Implementation clues | `BrowseViewModel` cases `.shorts` in the initial load and in `fetchNextPage`. |
| Confidence | Strongly supported by the diff. Motivation is not written down, so treat the filter as in-scope only if the Shorts section is still showing non-shorts on current upstream. |
| Dependencies | None. |

## 3. Original Customizations — Partially Recovered or Uncertain

### 3.1 Video id resolution described in the notes, not in the diff

`docs/keyhou-tvos-player-work.md` section 7 says history tiles should resolve `videoId` from `onSelectCommand.watchEndpoint`, `reelWatchEndpoint`, nested `innertubeCommand`, and `navigationEndpoint`.

The customization diff does not change video-id extraction. `InnerTubeAPI+VideoRenderers.swift` only changes `percentDurationWatched` parsing. The test `tileRendererInnertubeCommandPath` already existed on `64562f5`.

Treat multi-path video-id resolution as upstream behavior to leave alone, unless a fresh checkout still drops history tiles that the September note was trying to recover. Do not invent a new parser from the note alone.

### 3.2 Percent values of 1 or below

The parser and its test treat a number greater than 1 as a percent and a number in 0…1 as a fraction. The implementation review on 20 October 2026 found no fixture where YouTube sends an already-normalized fraction. InnerTube numbers arrive as `NSNumber`, so an integer percent and a double percent are the supported cases. The fraction branch is implemented and tested, but its real-world input is unverified. Reimplement the three accepted shapes, and keep the limitation in section 7.

### 3.3 Untracked package tree in the Desktop backup

`~/Desktop/SmartTubeIOS-backup` contains untracked `Package.swift`, `Sources/`, and `Tests/` that were **not** part of commit `0d82234` or `smarttube-changes.patch`. They look like a duplicate Swift package layout of the app sources, not additional product behavior. Do not mine that tree for requirements.

### 3.4 `Default Quality` catalog key

The strings catalog gained two keys: `%g×` and `Default Quality`. The speed format is part of 2.5. `Default Quality` is the existing Settings picker title; the customization diff does not add a new quality setting. The rest of the ~35,000-line `Localizable.xcstrings` diff is reorder. Do not port it.

## 4. Platform-Specific Requirements

### tvOS

- Six-tab bar and the Library chip set in 2.8.
- No Home chip bar. No Settings → Visible Sections.
- Player HUD, dropdowns, focus chrome, and clickpad handling in 2.2–2.4 and 2.10.
- Hardware Play/Pause debounce is required here even though the guard is shared (2.1).
- Shorts Down navigation is two presses from the tab bar: Shorts row, then video grid.
- Downloads stay unavailable. Subscriptions live under Library → Subs.

### iOS and macOS

- Tab bar / sidebar stay Home, Search, Library, Settings.
- Home chip bar stays, including Subscriptions and the other existing chips.
- Library sections stay as they were, including History and Downloads.
- Settings → Visible Sections stays.
- Speed list, per-channel speed and captions, resume position, watch-history reporting, and the UHD picker apply here too.
- Do not replace the upstream iOS behavior of toggling controls by tapping the video surface. That landed upstream after the customization baseline (pull request #161) and is not part of this customization.
- The TOS / web player and non-tvOS Shorts playback must apply the channel’s resolved speed instead of always applying the global default.

### visionOS

- After native HLS starts, the quality picker still offers rqh-free 1440p/2160p MP4 rows from Android VR player info, and choosing one uses DASH (2.6).
- Do not remove the existing visionOS H.264 / 1080p HLS cap for the stream that is already playing.

### Shared constraints

- `SmartTubeIOSCore` stays Foundation-only. `ChannelPlaybackPreference`, the quality-picker helper, and the resume helper belong there.
- One list of speeds: `AppSettings.availableSpeeds`.
- One hide timeout: the existing `controlsHideTimeout` (default 4 seconds). The customization restarts it; it does not invent a new duration.
- Like, dislike, seek distances, chapter skip, and next/previous video stay the existing view-model actions. The HUD only exposes them.

## 5. Cross-Feature Dependencies and Constraints

1. **Channel preferences sit under the HUD and the sheets.** Speed and caption controls display and save the channel override. Settings still edits the global default. Loading a video applies the override onto the view model’s settings snapshot and must not write that snapshot back over the global values.
2. **Auto-hide and focus are one gesture.** Opening a picker cancels the hide timer and moves highlight to that HUD button. Closing it restarts the timer, keeps that highlight, and ignores the follow-up Select for ~350 ms. Skipping any one of those steps leaves the HUD stuck or jumps highlight to Play/Pause.
3. **Select handling and the focus engine are one mechanism.** Only the highlighted HUD button is focusable. D-pad movement is the explicit map in 2.2. The host view exists only when no HUD button or picker owns focus. The AV player view does not accept focus.
4. **Play/Pause is orthogonal to focus.** The 120 ms guard must run for SwiftUI commands and for `MPRemoteCommandCenter`, including while a picker is open.
5. **UHD is picker plus switch.** Showing a 2160p row is not enough. Heights present in the HLS master stay on the HLS path. Heights absent from the master play through DASH. Do not grow the legacy fallback ladder if current upstream already has a stream-source seam; put the choice there.
6. **History has two directions.** YouTube → app is the resume rule. App → YouTube is the playback-started ping plus checkpoints while playing, only when history is enabled. Preserve upstream’s flush when the video changes, including its refusal to send `st == et`.
7. **Navigation and tests move together.** Removing the tvOS chip bar changes Home’s accessibility identifier to `home.feed`, the Right-press counts between tabs, the Library chip identifiers, and the Shorts Down count. Update those tests in the same change as the tabs.
8. **Do not carry local project settings with the features.** Signing, bundle ids, entitlements, and the strings-catalog reorder are not part of items 2.1–2.11.

Playback lifecycle to preserve:

- Loading a new video still clears the previous item, records the intended video id, and restores a resume position only after duration is known.
- Quality switches seek back to the saved time.
- Controls-hide scheduling still no-ops under `--uitesting-show-controls`.
- SponsorBlock skip, captions cues, and stats-for-nerds updates that already run from the time observer stay in place. The 15-second history checkpoint, if still needed, is an addition to that observer, not a replacement.

## 6. Relevant Tests and Validation

### Unit tests that protected the original behavior

Recreate these on the fresh checkout. They used Swift Testing (`@Test`), with no network and no `Task.sleep`.

| Test | Protects |
|---|---|
| `TogglePlayPauseDebounceTests.secondCallWithinWindowIsIgnored` | Second `togglePlayPause` inside 120 ms is ignored |
| `TogglePlayPauseDebounceTests.callAfterWindowApplies` | A later call toggles again |
| `availableSpeedsIncludes16And185` | Speed list includes 1.6 and 1.85 and excludes 1.7 |
| `playbackSpeed17MigratesTo16` | Stored global 1.7 becomes 1.6 |
| `qualityPickerKeepsAV1FourKWhenHLSStopsAt1080` | 1440p/2160p MP4 survives an HLS master that stops at 1080p |
| `qualityPickerSynthesizesHLSFourKRow` | An HLS height missing from adaptive formats still gets a row |
| `qualityPickerKeepsPlainMP4FourK` | Plain `video/mp4` UHD without codec tags stays |
| `appendingFormatsMergesNewURLs` | Extra formats merge by URL and skip duplicates |
| `percentDurationWatchedParsesJSONNumbers` | Int percent, double percent, and 0…1 fraction |
| `resumePositionPrefersFurtherProgress` | The further of local and YouTube progress wins |
| `tileRendererParsesIntegerPercentWatched` | A history/tile overlay with an integer percent parses |
| `channelPlaybackPreferencesOverrideGlobal` | Channel speed and captions override Settings |
| `channelCaptionsOffDoesNotInheritGlobal` | Explicit Off does not inherit the global language |
| `channelPlaybackPreferencesRoundTrip` | The channel map encodes and decodes |
| `visionOSPickerKeepsUHDMP4` | The visionOS H.264 filter does not drop UHD MP4 rows |

`ChannelPlaybackPreferenceTests.swift` in the later working tree is a split of the App Settings tests above. The original tests lived in `SmartTubeIOSTests.swift`. Either home is fine.

### tvOS UI tests that were updated with the navigation and HUD

These already existed. The customization changed what they wait for and added HUD coverage. They use accessibility identifiers and `waitForExistence`. They are not a product surface.

- Home waits on `home.feed` instead of `home.chipBar`.
- `TVUITestHelpers` Right-press counts: Playlists 2, Library 4, Settings 5.
- Subscriptions-chip test became a Playlists-tab test. Home-chip restore became Home-tab restore.
- Library: History chip expectations became Recommended; Downloads became Channels.
- `TVShortsDownNavigationUITests`: two Down presses from the tab bar reach the video grid.
- `TVPlayerControlsUITests`: like, dislike, speed, captions, and quality buttons exist; Select on speed, captions, and quality opens those pickers; center transport buttons do not overlap.
- Existing launch arguments `--uitesting-open-more-menu` and `--uitesting-show-controls` stayed. The customization did not add new deep-link arguments.

### Device checks (from the September notes)

On an Apple TV with a Siri Remote 2 clickpad:

1. Hardware Play/Pause toggles once, including while a picker is open.
2. HUD Speed, Captions, and Quality: one OK opens the dropdown; one OK on a row applies it; Menu closes it; that HUD button stays highlighted.
3. The More button shows a circle and the light-blue highlight when selected.
4. The quality list includes 1440p and 2160p when the video has them, and choosing a height the HLS master lacks switches via DASH.
5. A half-watched video from YouTube history resumes; watching while signed in, with history enabled, updates YouTube history.
6. Home cards and chips activate on one OK and use the light-blue focus.
7. Tabs are Home, Search, Playlists, History, Library, Settings. Subscriptions is only Library → Subs.
8. 1.5× and Spanish captions on channel A leave channel B and Settings → Playback Speed on the defaults.
9. After closing a picker or More, the HUD hides after the normal timeout (about 4 seconds, or the user’s `controlsHideTimeout`).

## 7. Known Limitations and Unresolved Issues

- **Resume fraction branch.** Values of 1 or below are treated as a 0…1 fraction. There is no captured InnerTube payload in the repo that proves YouTube sends that shape. A payload of `1` meaning 1% becomes 100% and is then ignored because resume requires a fraction below 0.95. Integer and double percents above 1 are the reliable path.
- **Global-only 1.7× migration.** Only the top-level `playbackSpeed` is rewritten from 1.7 to 1.6 during decode. A channel override of 1.7 is left as stored.
- **120 ms Play/Pause window.** A genuine second press inside that window is dropped.
- **350 ms post-picker Select swallow.** A very fast OK after confirming a row can be ignored.
- **Hidden-controls seek is ±10 seconds.** That was already upstream. Visible controls with no highlight use the user’s seek settings. Do not “fix” the hidden case into the user setting unless you intend a new behavior.
- **Like and Dislike do nothing when signed out.** No extra prompt was added.
- **Clickpad behavior is device-specific.** Remote 2 delivers Select on press-down. Gesture-based Select will look fine in the Simulator and fail on device.
- **4K on the Simulator.** Assert stream choice, not decoded frames. VP9/AV1 will not play there.
- **Shorts misclassification.** Upstream already had a known problem where some ordinary videos are marked as shorts (`docs/explanation/task-89-short-detection-issue.md`, unverified). The Shorts-section filter in 2.11 hides non-shorts; it does not fix false positives.
- **History reporting depends on account-bound tracking URLs.** If those URLs never arrive, the playback-started re-ping cannot attribute the view. The original code did not add a new login or token flow.
- **Type-checker load on tvOS modifiers.** The original player split tvOS gesture modifiers (`tvosPlayerGestureModifiers` and related slices) because one chain failed to type-check. Split again if the compiler times out. That is a build constraint, not a user-visible feature.

## 8. Local Environment Notes

These were in the customization diff and the Desktop patch. They are how that Mac was signed. They are not product requirements. A fresh fork should keep upstream’s signing until you choose your own, in a separate change.

The snapshot changed, and this document intentionally does not repeat the values:

- The development team.
- Bundle identifiers for the app, tvOS UI tests, iOS UI tests, and the Safari extension (upstream used the `com.void.smarttube` prefix).
- The App Group on the app, the share extension, and the macOS entitlements.
- The iCloud key-value store identifier, which follows the team prefix plus the bundle id.
- Code-sign identity strings and a block of macOS sandbox / resource-access build settings in `project.pbxproj`.
- A tvOS Firebase plist, if one exists locally. It was not part of commit `0d82234`. Do not copy plist contents into git.

`Info-macOS.plist` only moved the copyright key. That is noise.

UI-test launch arguments that already existed upstream (`--uitesting-open-more-menu`, `--uitesting-show-controls`, and the sign-in trigger added by upstream before this work) are test harness. Do not treat them as features.

## 9. Later Work — Not Confirmed as Original

The checked-out branch `integrate-upstream` at `e659ce9` (upstream pull request #161, iOS video-surface taps) contains an **uncommitted port** of sections 2.1–2.10 done on 20–22 October 2026. That port is evidence of how the behaviors were being adapted. It is not a new requirements source.

Do not treat these as original product requirements:

- **Personal signing left untouched during the port.** On 20 October 2026 the integration was told to keep upstream `com.void.smarttube` identifiers and the upstream team, and to apply personal signing later. The opposite edit exists only on `0d82234`.
- **Watchtime mechanism copied or not copied.** Increment 3 was told not to reintroduce the old periodic observer or `notePlaybackBegan`, and not to change the resume parser in that increment. The user-facing history and resume requirements remain section 2.7. The instruction was about not duplicating newer upstream reporting.
- **A few-line adaptations** in `PlaybackViewModel+AudioOnly.swift`, `PlaybackViewModel+Navigation.swift`, `ShortsEmbedPlayerViewModel+WebBridge.swift`, `TOSPlayerView.swift`, and `TOSPlayerViewModel+WebBridge.swift`. Those files were not part of the original customization diff (the TOS file there changed by a handful of lines for resolved speed only). On the port they exist because upstream had split files. Reapply channel speed and captions wherever the current player sets speed. Do not treat the web-bridge edits as a separate feature.
- **`ChannelPlaybackPreferenceTests.swift`** as a new file. Same tests as section 6, new location.
- **tvOS UI-test edits in the dirty `integrate-upstream` tree** beyond the identifier and navigation updates already listed in section 6. Retarget tests at the current upstream player. Do not add deep-link arguments as product behavior.
- **Upstream commits after 15 August 2026**, including iOS surface-tap controls, widget and watch-app work, and App Intents. Those are upstream. Keep them.
- **The strings-catalog reorder and the empty staged patch.**

Features that the task statement listed as examples of possible later work — quality and resume, Play/Pause debounce, per-channel preferences, overlay auto-hide, the tvOS HUD and remote focus, and the six-section tvOS navigation — are **in the 2 September 2026 notes and in commit `0d82234`**. They are confirmed original customizations, specified in section 2. The October port reimplemented them; it did not invent them.

## 10. Fresh-Fork Reimplementation Checklist

Do this on a clean latest upstream checkout. Do not merge `0d82234`. Do not copy `project.pbxproj`, entitlements, or `Localizable.xcstrings`.

1. **Speeds.** Extend `availableSpeeds` with 1.6× and 1.85×, remove any 1.7× choice, migrate a stored global 1.7 to 1.6, and format labels with a general number format.
2. **Channel preferences.** Add the channel map and resolvers. Persist HUD and sheet changes per channel. Apply them on load, when the channel id arrives late, and in the TOS player and Shorts player. Leave Settings → Playback Speed as the global default.
3. **Quality picker and switch.** Keep HLS heights, synthesize missing HLS rows, keep 1440p+ MP4, sort high to low. Play non-HLS UHD through DASH. On visionOS, enrich the picker after HLS starts. Add the helper unit tests.
4. **Resume.** Parse integer and double percents, and the 0…1 shape with the limitation in section 7. Resume at the further playhead past 5 seconds. Leave upstream watchtime flush intact. Add checkpointing only if current upstream does not already update signed-in YouTube history while playing.
5. **Play/Pause debounce.** 120 ms, covering both the SwiftUI command and the remote command center, including inside pickers.
6. **tvOS HUD.** Top row Back, Channel, Like, Dislike, Speed, Captions, Quality, More. Dropdowns under Speed, Captions, and Quality. More menu unchanged. Center buttons do not overlap. Highlight stays put after a picker closes.
7. **tvOS remote.** Native buttons for HUD and menus. Host view under the HUD only when no button owns focus. Video layer not focusable. D-pad map from section 2.2. Menu dismisses overlays first. One OK, one Play/Pause.
8. **Auto-hide.** Cancel the existing hide timer while a picker or menu is open. Restart it on close without clearing the top-row highlight.
9. **tvOS navigation.** Six tabs. No Home chips. Locked Playlists and History reload on appear. Library chips Subs, Recommended, Channels, Playlists, RSS. Hide Visible Sections on tvOS. iOS and macOS stay on four destinations.
10. **Focus chrome.** Light-blue focus, pass-through buttons, one OK on cards, chips, Shorts, channels, and the Current Queue row.
11. **Tests.** Add the unit tests in section 6. Point tvOS UI tests at `home.feed`, the new tab counts, the Library chips, two-Down Shorts navigation, and the HUD buttons.
12. **Device pass.** Run the nine checks in section 6 on Apple TV with a Siri Remote 2. Confirm iOS still toggles controls from a video-surface tap and still has four tabs.
13. **Signing, separately.** After the behaviors work, apply your own team, bundle ids, App Group, and Firebase plist locally. Do not take those values from the old commit, and do not commit secrets.
