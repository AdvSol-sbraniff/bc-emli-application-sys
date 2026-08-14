# Admin PDF Viewer Revision Workspace Placement Plan

## Plan status

Reviewed before implementation, implemented, and verified locally on 2026-08-14. This document is the programmer-facing structure-first plan and execution record for a user-selectable Revision Issues placement in the admin PDF viewer.

## Objective

Allow an administrator to move the existing Revision Issues workspace between:

- **Top**: the current position above the evidence and advice accordions.
- **Side**: the existing auxiliary side-panel position used by Conversation and Internal Notes.

The change must make the screen easier to maintain without turning one large file into many small forwarding modules.

## Safety backup

The current working copy of the React screen, including all pre-existing uncommitted work, was copied before planning to:

```text
.codex_tmp/backups/admin-pdf-viewer-revision-placement/20260814-131332/invoice-versions-index.tsx
```

The source and backup SHA-256 values both equal:

```text
F23CD104662A9DAE3FE8C4CC7869AF0DFC13327F0128E804F5557DD9552B33BC
```

The backup is recovery material only and must not be imported by the application.

## Scope and constraints

- No backend, API, database, DDL, seed, or workflow-state changes.
- Do not duplicate `AdminRevisionWorkspace`, its hook, drafts, or network calls.
- The workspace must render in only one physical location at a time.
- Placement changes must not reload revision data or discard unsaved decisions.
- Conversation and Internal Notes remain mutually exclusive.
- In side placement, Conversation or Internal Notes temporarily replaces Revision Issues; closing that communication panel reveals Revision Issues again.
- Preserve all current evidence, document, drawer, workflow, and status behaviour.
- Preserve unrelated working-tree changes.
- Do not introduce a global state library, generic panel framework, or one-file-per-helper fragmentation.
- Persist placement as a browser preference, not invoice business state.

## Current structure and problem boundary

The route component is currently approximately 4,900 lines:

```text
app/frontend/components/domains/invoice-versions/index.tsx
```

It owns invoice loading, PDF rendering, located fields, advice, supporting documents, revision integration, communication panels, drawers, toolbar controls, and physical layout.

Revision behaviour is already substantially isolated:

```text
app/frontend/components/shared/claims/admin-inline-revision-issues.tsx
```

That module owns the revision data hook, drafts, issue actions, categories, and workspace UI. This implementation will retain that ownership rather than copying revision logic into a second side-panel component.

The layout boundary is the correct extraction point because the new feature changes physical placement rather than revision-domain behaviour.

## Target module structure

Only two layout-focused modules are added beside the existing route component:

```text
app/frontend/components/domains/invoice-versions/
├── index.tsx
├── invoice-review-layout.tsx
└── use-invoice-review-layout.ts
```

The existing revision-domain module remains in place:

```text
app/frontend/components/shared/claims/admin-inline-revision-issues.tsx
```

### 1. `use-invoice-review-layout.ts`

Owns only local presentation state:

```ts
type RevisionWorkspacePlacement = 'top' | 'side';
type CommunicationPanel = 'conversation' | 'internal_notes' | null;
type EffectiveAuxiliaryPanel = 'revision_issues' | 'conversation' | 'internal_notes' | null;
```

Public contract:

```ts
const layout = useInvoiceReviewLayout();

layout.documentVisible;
layout.toggleDocument();

layout.revisionPlacement;
layout.toggleRevisionPlacement();

layout.communicationPanel;
layout.toggleCommunicationPanel(panel);
layout.closeCommunicationPanel();

layout.mountedCommunicationPanels;

layout.auxiliaryPanelWidth;
layout.setAuxiliaryPanelWidth(width);

layout.showRevisionWorkspace();
layout.effectiveAuxiliaryPanel({
  revisionWorkspaceAvailable: boolean,
});
```

The module also exports two pure state functions for deterministic testing:

```ts
normalizeRevisionWorkspacePlacement(storedValue);
effectiveAuxiliaryPanelFor({
  revisionPlacement,
  communicationPanel,
  revisionWorkspaceAvailable,
});
```

Rules:

- The default revision placement is `top`.
- Valid stored placement is restored from local storage.
- Invalid stored values fall back to `top`.
- Changing placement writes one local-storage preference.
- Moving to `side` closes a communication panel so Revision Issues is immediately visible.
- Moving to `top` does not close a currently open communication panel.
- When placement is `side` and no communication panel is active, the effective auxiliary panel is `revision_issues`.
- When Conversation or Internal Notes is active, it takes temporary precedence.
- Closing the communication panel automatically exposes side-positioned Revision Issues again.
- `showRevisionWorkspace()` closes the temporary communication panel only when placement is `side`.
- The existing auxiliary width remains clamped to 340–640 pixels and persisted with its existing storage key.

This hook contains no invoice IDs, revision records, fetch calls, permissions, or workflow logic.

### 2. `invoice-review-layout.tsx`

Owns the physical three-slot layout and auxiliary resize mechanics.

Public contract:

```tsx
<InvoiceReviewLayout
  main={...}
  document={...}
  auxiliary={...}
  auxiliaryWidth={layout.auxiliaryPanelWidth}
  onAuxiliaryWidthChange={layout.setAuxiliaryPanelWidth}
/>
```

Responsibilities:

- Render `Main | Document | Auxiliary`.
- Keep the current horizontally resizable Main panel behaviour.
- Render Document only when supplied.
- Render the auxiliary shell and resize handle only when supplied.
- Clamp auxiliary width to 340–640 pixels.
- Support pointer resize and keyboard ArrowLeft/ArrowRight resize.
- Contain no invoice, revision, conversation, or internal-note logic.

### 3. Existing `index.tsx`

Remains the route-level composition owner.

It will:

- call `useInvoiceReviewLayout`;
- render the new placement button;
- construct one `revisionWorkspaceContent` value;
- supply that value to the top slot or side slot, never both;
- map Conversation and Internal Notes into the auxiliary slot;
- wrap all source actions that open a revision issue so side placement becomes visible before focus runs;
- keep all existing invoice, evidence, PDF, revision, and API state.

No broad evidence-panel or PDF-panel extraction is included in this change.

## Target call hierarchy

```text
InvoiceVersionsScreen
├── useInvoiceReviewLayout
├── useAdminInlineRevisionWorkspace
├── toolbar
│   ├── Document toggle
│   ├── Conversation toggle
│   ├── Internal Notes toggle
│   └── Move Revision Issues to Side/Top
└── InvoiceReviewLayout
    ├── Main
    │   ├── AdminRevisionWorkspace when placement = top
    │   └── existing evidence/advice accordions
    ├── Document
    │   └── existing PDF/image viewer
    └── Auxiliary
        ├── AdminRevisionWorkspace when placement = side
        ├── AdminConversationPanel when active
        └── AdminInternalNotesPanel when active
```

Only one branch of Auxiliary is visible. Only one `AdminRevisionWorkspace` instance exists in the rendered tree.

## State flow

### Initial load

```text
read local placement preference
├── valid 'side' -> side
└── absent/invalid/'top' -> top

revision hook loads once from invoice id
└── workspace data/drafts remain independent of placement
```

### Move Top to Side

```text
click “Move Revision Issues to Side”
├── revisionPlacement = side
├── communicationPanel = null
├── persist side preference
└── same workspace props render in Auxiliary
```

### Move Side to Top

```text
click “Move Revision Issues to Top”
├── revisionPlacement = top
├── persist top preference
└── same workspace props render above evidence
```

### Communication precedence while placement is Side

```text
Revision Issues visible in side
└── open Conversation/Internal Notes
    ├── communication panel temporarily replaces Revision Issues
    └── close/toggle communication panel
        └── Revision Issues becomes visible in side again
```

### Focus from an advice field or rule

```text
source action requests issue focus
├── if placement = side, close temporary communication panel
├── allow the workspace location to render
├── expand/select requested issue and decision mode
└── reveal and focus the issue
```

The current arbitrary 60 ms reveal delay will be replaced with render-frame coordination so conditional placement does not introduce a timing race.

## UI contract

The toolbar shows a single explicit button only when the revision workspace is available:

- Top placement: **Move Revision Issues to Side**
- Side placement: **Move Revision Issues to Top**

The button includes a tooltip explaining the destination. It changes placement; it does not create another workspace.

The Revision Issues appearance and workflow controls remain unchanged.

## Error and edge behaviour

- No revision history and an ineligible invoice status: no workspace and no placement button.
- Stored invalid placement: use `top`.
- Historical snapshot route: preserve current rule that workflow actions/workspace are unavailable.
- Side placement with Document hidden: Main and Auxiliary remain.
- Side placement with Conversation open: Conversation wins temporarily; closing it restores Revision Issues.
- Placement change with unsaved drafts: drafts remain in the existing hook and are preserved.
- Focus while Conversation/Internal Notes is open: side Revision Issues becomes visible before reveal.
- Window narrower than total panel widths: preserve horizontal overflow rather than silently compressing the PDF.
- Auxiliary resize remains keyboard accessible.

## Implementation sequence

1. Verify and record the safety backup.
2. Write this plan.
3. Perform and record a second-pass simplicity review.
4. Add `use-invoice-review-layout.ts`.
5. Add `invoice-review-layout.tsx`.
6. Replace layout-only state and resize code in `index.tsx` with the hook/component.
7. Add the placement button and one-instance workspace routing.
8. Make revision focus placement-aware and remove the fixed reveal delay.
9. Run formatting/diff checks.
10. Run targeted ESLint and TypeScript/Vite compilation.
11. Run focused Claims revision backend regression to prove no workflow contract was disturbed.
12. Exercise layout state paths with deterministic checks and, where available, local runtime/manual HTTP or browser smoke checks.
13. Record actual test evidence and final module boundaries in this plan.

## Test matrix

### Static and compilation

- ESLint for all three invoice-version modules and the revision module.
- TypeScript/Vite production build with the repository-required Node 20+ runtime and sufficient heap.
- `git diff --check`.
- Audit that no backend, SQL, DDL, seed, or API files changed for this feature.

### Layout-state cases

- Missing preference defaults to Top.
- Stored Top restores Top.
- Stored Side restores Side.
- Invalid preference restores Top.
- Top to Side persists Side and exposes Revision Issues.
- Side to Top persists Top.
- Side + Conversation shows Conversation.
- Closing Conversation returns to side Revision Issues.
- Side + Internal Notes shows Internal Notes.
- Closing Internal Notes returns to side Revision Issues.
- No workspace availability produces no revision auxiliary content.

### Workflow-preservation cases

- Revision workspace data hook is instantiated once.
- Top mode renders one workspace.
- Side mode renders one workspace.
- No mode renders duplicate issue DOM IDs.
- Unsaved draft state survives placement changes.
- Recommend Action and Close Issue selection survive because domain state remains in the existing hook.
- Source status badge opens/focuses the appropriate issue in both placements.
- Source Recommend Action and Close Issue buttons select the correct mode in both placements.
- Focus replaces a temporary communication panel when placement is Side.
- Send confirmation and status categories remain unchanged.

### Existing behaviour regression

- Document toggle.
- PDF pagination, zoom, fit, rotation, and highlighting compile unchanged.
- Conversation and Internal Notes remain mutually exclusive.
- Auxiliary pointer and keyboard resize.
- Current-version versus fixed-version route permissions.
- Existing revision request/service specs.

## Completion criteria

The work is complete only when:

- the reviewed plan is recorded;
- the safety backup remains available;
- Top and Side placement are both available from the screen;
- placement persists locally;
- only one revision workspace is rendered;
- no additional revision API call occurs solely because placement changes;
- unsaved revision state is retained;
- source focus works through side placement;
- Conversation and Internal Notes temporarily replace and then restore side Revision Issues;
- targeted lint/build/regression checks pass;
- no unauthorized backend or DDL changes occur;
- the implementation and test results are recorded below.

## Simplicity review

Completed before implementation on 2026-08-14.

### Review conclusion

The two-module boundary is justified and is the smallest structure that cleanly separates the physical layout from the existing 4,900-line route component. A direct in-file toggle was rejected because it would add another conditional panel path beside the existing document, conversation, notes, resize, and workspace paths without giving any module ownership to that state.

The earlier broader idea of extracting route, controller, evidence, document, toolbar, drawers, and revision submodules was rejected for this change. It would move too much stable code, create a large review surface, and force future AI sessions to traverse many files. Only the layout state and physical layout earn new modules now.

### State simplification

Revision Issues will not be stored as another independently mutable auxiliary-panel selection. The effective auxiliary content is derived from:

1. `revisionPlacement`;
2. `communicationPanel`; and
3. whether the revision workspace is available.

This gives one precedence rule:

```text
open communication panel
  -> conversation/internal notes
otherwise side placement + available workspace
  -> revision issues
otherwise
  -> no auxiliary panel
```

That derivation prevents impossible combinations such as a `side` placement with a separately stored `null` Revision Issues selection, and it makes closing Conversation or Internal Notes automatically restore Revision Issues.

### Modules rejected

- No generic `PanelManager`, panel registry, provider, reducer, or context.
- No global state library.
- No separate `RevisionWorkspaceHost` component that only forwards props.
- No extraction of invoice loading, evidence accordions, PDF internals, drawers, or toolbar in this change.
- No second revision workspace component for the side presentation.
- No new frontend testing framework solely for this feature.

### Focus simplification

The existing revision hook remains the owner of issue expansion and selection. The route adds one placement-aware wrapper that exposes side Revision Issues before calling the existing focus operation. The fixed 60 ms DOM lookup is replaced with animation-frame render coordination in the existing revision module; a new focus service or event bus is not introduced.

### Testing simplification

The two pure state functions provide executable coverage of placement normalization and auxiliary precedence without mounting the entire 4,900-line screen. The full Vite build verifies React composition. Existing revision request/service specs verify the unchanged backend workflow. A new frontend framework or broad snapshot suite would add more maintenance than confidence for this layout-only change.

### Complexity budget

- Exactly two new production files.
- No new persisted business state.
- No duplicate workspace rendering or data hook.
- No production module whose only purpose is forwarding a call.
- Prefer deletion of old layout state/resize code from `index.tsx` over wrapping it.
- Net new logic is limited to placement preference, auxiliary precedence, and the toolbar action.

The reviewed plan is structurally approved for implementation.

## Implementation record

Completed on 2026-08-14.

### Final module ownership

- `use-invoice-review-layout.ts` owns the browser placement preference, document visibility, communication-panel selection, auxiliary width, and the pure auxiliary-panel precedence calculation. It makes no API calls and has no invoice or revision-domain knowledge.
- `invoice-review-layout.tsx` owns the physical Main, Document, and Auxiliary pane arrangement plus pointer and keyboard resizing. It contains no invoice or workflow logic.
- `index.tsx` remains the route-level composition owner. It instantiates the revision hook once, constructs one `AdminRevisionWorkspace`, and routes that one workspace to the top or side location.
- `admin-inline-revision-issues.tsx` remains the revision-domain owner. Only its DOM reveal coordination changed: two animation frames now replace the former fixed 60 ms mount guess.

### Implemented state flow

- Top remains the default and an invalid stored preference safely normalizes to Top.
- The explicit toolbar action switches between **Move Revision Issues to Side** and **Move Revision Issues to Top**.
- The preference is stored locally and is not invoice business state.
- Moving Top to Side closes an open communication panel so the requested destination is visible immediately.
- Conversation and Internal Notes temporarily take precedence over a side-positioned Revision Issues workspace. Closing either panel automatically returns Revision Issues.
- Every rule/field source action uses one placement-aware focus wrapper. In Side mode it exposes Revision Issues before the existing revision hook selects and reveals the requested issue.
- Historical/current-version availability guards remain the source of whether the workspace and placement action exist.

### Simplicity result

- Exactly two production modules were added, matching the reviewed complexity budget.
- No panel framework, context, reducer, global store, duplicate revision component, or duplicate revision hook was introduced.
- The route component became smaller by moving cohesive presentation concerns out of it; the feature did not trigger a broad evidence/PDF/workflow refactor.
- There are no backend, API, DDL, SQL, seed, or database changes for this feature.
- The pre-change backup remains unchanged at the path and SHA-256 recorded above.

### Main-panel resize follow-up

After implementation, interactive review exposed a pre-existing conflict in the main-panel resize contract. The browser-native CSS resize handle changed the flex item's requested width, while `flex-grow: 1` immediately returned the released space to that same item. A first controlled-width correction made the main panel move but exposed the second structural issue: Document and Auxiliary were still independent fixed-width siblings, so they could not receive the released space.

The final design is a true nested split layout: `Main | Right region`, with `Document | Auxiliary` inside the right region. The full-height divider changes Main's explicit width and the right region automatically receives the remainder. Document is the flexible right-side consumer; Auxiliary retains its independently controlled width when Document is present. When Document is hidden, Auxiliary fills the right region. The PDF width observer now follows the flexible document container rather than imposing the former 560-pixel ceiling.

The divider supports pointer capture and keyboard Left/Right resizing, starts from the actual rendered width, and clamps Main so the visible right-side panels retain their calculated minimum width. This remains presentation-only state inside the existing layout component; no new module or persistence mechanism was added.

## Test execution record

Completed locally on 2026-08-14.

| Check                                   | Result                                                                                                                                                                                                                                               |
| --------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Deterministic placement/precedence test | 16 assertions passed, covering preference normalization, both placement transitions, both communication-panel precedence paths, unavailable-workspace behaviour, and width clamping.                                                                 |
| Targeted ESLint                         | Passed for `index.tsx`, both new layout modules, and `admin-inline-revision-issues.tsx`; no warnings.                                                                                                                                                |
| Frontend production build               | Passed with Vite under the repository's Node 20 container; 11,552 modules transformed and the build completed in 33.42 seconds.                                                                                                                      |
| Revision workflow backend regression    | 30 examples, 0 failures across the request and service workflow specs.                                                                                                                                                                               |
| Structural invariant audit              | One revision hook call, one `AdminRevisionWorkspace` JSX instance, zero fetch calls in the new layout modules, and zero remaining fixed reveal-delay calls.                                                                                          |
| Source integrity                        | `git diff --check` passed and the backup SHA-256 still matches the recorded value.                                                                                                                                                                   |
| Local service smoke                     | Rails `/up` returned HTTP 200; the Vite root returned its expected base-path redirect and accepted the final module updates.                                                                                                                         |
| Split-panel resize correction           | Targeted ESLint passed and the complete 11,552-module Vite production build passed after introducing the nested Main/Right region, flexible Document sizing, auxiliary fill fallback, calculated right-side minimum, and responsive PDF measurement. |

The production build retained existing non-failing repository warnings concerning Quill `eval`, CSS parsing, mixed dynamic/static imports, and bundle size. The RSpec run retained existing non-failing Bullet/deprecation warnings. None was introduced by or blocks this feature.
