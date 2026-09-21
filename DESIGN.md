# Scrapnote design system

## Product posture

Scrapnote is a local-first writing tool for desktop, Android, and foldable screens. Its interface should feel like
a well-made Braun instrument and behave like a quiet code editor: immediate,
legible, and free of promotional chrome. User content is the dominant visual
material.

## Structural contract

The application uses an **Index-First editor shell**.

1. A fixed 48 px activity rail contains icon-only destinations and the vault
   action. It never overlays feature content.
2. Scraps and Notes add a 232 px hierarchy pane immediately to the right of the
   activity rail. The pane owns the entire available height.
3. The document area begins with a 38 px tab strip and uses all remaining space
   for editing. There is no page title, dashboard header, preview switch, or
   visible save toolbar.
4. Timeline does not use the hierarchy pane. Its date dial is clipped to the
   timeline content bounds and can never render beneath the activity rail.
5. Without a selected vault, feature content is replaced by one centered,
   sequential setup prompt. The activity rail remains available.

Below 600 logical pixels the shell uses labelled bottom navigation and a compact
header. Below 700 pixels of available workspace width, the hierarchy and editor
share a single surface with a 48 px list/edit toggle; both stay mounted.
At larger widths the hierarchy and editor are visible together. Android uses
48 px touch actions for new, image attachment, and save at every width.

Screen cutouts, system bars, and keyboard insets are respected. A separating
hinge or half-open fold uses the unobstructed top/leading sub-screen. Flat unfolded
screens use the full available width. Rotation and folding retain draft text and
selected documents. Android Back returns from the editor to its list first.

Mobile Expenses use a vertical ledger with an explicit add action and a scrollable
form. The full spreadsheet-style ledger remains on wider screens. The Scrap picker
in narrow Note editors opens on demand, preserving space for the software keyboard.

## Geometry

- Activity rail: 48 px
- Hierarchy pane: 232 px
- Tab strip: 38 px
- Status line: 24 px when needed
- Interactive hit target: at least 44 × 44 px, except the compact sync status action
- Rules: 1 px
- Corners: 2–4 px; dialogs may use 6 px
- Spacing base: 4 px; common steps are 8, 12, 16, 24, and 32 px

Panels meet edge-to-edge. Cards, floating containers, and decorative shadows do
not belong in the workspace.

## Color and type

The palette is warm paper, charcoal ink, and one muted signal orange. The
existing Flutter color constants remain the single source of truth:

- `paper` / `paperRaised` / `paperSunken` for depth
- `charcoal` / `charcoalSoft` / `mutedInk` for text hierarchy
- `rule` / `ruleStrong` for structure and focus separation
- `signalOrange` only for selection, focus, and meaningful status
- `destructive` and `success` only for their semantic states

Interface labels use the platform sans serif. Document text, line numbers,
dates, and file-like labels use the platform monospace. Body text is at least
13 px and editor text is 15 px with a relaxed line height.

## Navigation and hierarchy

- Activity buttons are icon-only with tooltips and semantic labels.
- Selection is shown with both a 2 px orange edge marker and a surface change.
- The vault action is an icon button fixed to the bottom of the rail. Its
  tooltip exposes the selected path or the action to choose one.
- Explorer rows are dense but retain 44 px hit targets. Selected rows use a
  quiet sunken surface, not a filled brand color.
- `Cmd/Ctrl+1`, `2`, and `3` switch primary destinations.

## Editing model

- Recently opened scraps and notes appear as document tabs.
- A new document is named `Untitled` until its first save.
- Dirty documents display a dot in the tab. Clean documents display a close
  control on hover/focus; both remain accessible to keyboard and semantics.
- `Cmd/Ctrl+S` saves the active document. Touch and compact layouts expose a Save
  action. There is no automatic save into the vault. The sync account page can
  explicitly save all drafts before synchronizing.
- `Cmd/Ctrl+W` closes the active Scrap or Note tab. Dirty documents use the
  same save/discard/cancel guard as clicking the tab close control.
- Dirty tabs and dirty window-close requests ask `Save`, `Don’t Save`, or
  `Cancel`. Clean tabs close immediately.
- Unsaved contents are mirrored to an app-support recovery draft so an
  unexpected process exit does not erase work. Recovery data is not part of
  the user’s vault and is cleared once all restored changes are saved or
  discarded.
- Image paste, drag-and-drop, and native file picking remain supported. Images
  render inside the editing surface while their portable relative Markdown
  links remain the saved source of truth. Pending attachments use a compact
  editor status line rather than toolbar chrome.
- Large static photos are resized and compressed in the background when saved
  into the Vault; picked originals remain untouched. A manual sync also repairs
  previously stored photos above the server's 25 MiB limit, relinks Notes and
  Scraps, and keeps their original files and Markdown in recoverable Vault trash.
- Image-bearing editors scroll as one fully measured document. Blocks remain
  mounted across viewport boundaries, so estimated lazy-list heights cannot
  change the scroll extent or move the reader by an image-sized step.

## States and feedback

Every control has default, hover, keyboard-focus, pressed, disabled, loading,
and error treatment where applicable. Focus indicators appear instantly and
do not change geometry. Successful saves are silent: the dirty marker simply
disappears. Errors appear in one compact, dismissible strip and never rely on
color alone.

Motion is limited to 100–160 ms color or opacity changes that clarify state.
There are no entrance animations, hover scaling, gradients, blur, or decorative
illustrations.

## Feature-specific rules

### Scraps

The Inbox hierarchy is modified-first. Selecting a scrap opens or focuses its
tab. The editor is always the largest surface. Markdown is edited directly; a
separate Preview mode is intentionally absent. The right-side metadata control
opens an edge drawer with capture and modification metadata, GPS coordinates,
and a map when a saved location is available. A saved Scrap without coordinates
shows a compact editor status line and a distinct unavailable-location icon. The
drawer offers retrying the device location, opening the app's system permission
settings, or entering latitude and longitude manually. Manual coordinates are
labelled as manual rather than claiming device accuracy.

### Notes

Folders and notes share the same hierarchy grammar as Inbox. The main surface
is a persistent Markdown editor, not a management dashboard. Empty states offer
one direct creation action; new Notes inherit the selected folder and support
the same image input and rendering model as Scraps.

### Timeline

The vertically scrollable chronological list and editor-sized reading surface
stay above the linear dial. Entries render Markdown, including local images,
and use each Scrap's modified timestamp. The former Location Trail panel is
removed. The dial is clipped inside the feature body, supports pointer, wheel,
and keyboard input, and is accompanied by a textual date so selection is never
communicated by color alone.

## Personal sync

The cloud action opens account and sync settings on every screen size. The first
upload and every subsequent sync are started explicitly by the user. Saving,
app resumes, and elapsed time never trigger sync or retry it. The bottom-right
sync button saves open drafts before synchronizing; signed-out users are directed
to the account page. A compact status states whether
files are synchronized, remain local, or require conflict resolution. This status
occupies a 32 px line at the bottom of the workspace, below the feature surface,
with an extra-small, icon-only sync action at its right edge. Its label remains
available through a tooltip and accessibility semantics.
When signed in, the account page reports the current session, last successful sync,
local sync file size, Scrap/Note/attachment/expense counts, and the previous synced
item count. Logout is always available on the same page and leaves local Vault files
untouched.

A three-way file merge uses the last common local baseline, with server revision
checks to prevent concurrent overwrites. Conflicting edits/deletes require a choice
per file. Downloads are checked with SHA-256 before application. Replaced/deleted
local files are copied to `.trash/sync/`; drafts and local trash are not uploaded.
Each local vault is bound to one server/account to prevent accidental cross-account
uploads. Authentication sessions use platform secure storage.

References: [Flutter adaptive design](https://docs.flutter.dev/ui/adaptive-responsive),
[display feature sub-screens](https://api.flutter.dev/flutter/widgets/DisplayFeatureSubScreen-class.html),
[Forui navigation](https://forui.dev/docs/widgets/navigation/bottom-navigation-bar).
