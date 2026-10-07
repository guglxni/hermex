# Hermex Domain

Canonical language for Hermex concepts that need consistent names across the product, planning, and support.

## Kanban

**Kanban**:
The Hermex destination for organizing and operating server-backed work across workflow states.
_Avoid_: Boards, Tasks

**Board**:
A named container of Kanban work and its workflow states.
_Avoid_: Kanban, project

**Card**:
An individual unit of work on a Board.
_Avoid_: Task, Kanban task, work item

**Status**:
The workflow state of a Card: Triage, To Do, Ready, Running, Blocked, Done, or Archived.
_Avoid_: Column, lane, stage

**Column**:
A visual grouping of Cards that share a Status.
_Avoid_: Status, lane

**Lane**:
An optional visual grouping of Cards by Profile, including an Unassigned lane.
_Avoid_: Status, column

**Profile**:
A Hermes agent configuration that can perform Card work.
_Avoid_: Assignee, user, agent

**Assignment**:
The relationship between a Card and the Profile selected to perform it. A Card without that relationship is Unassigned.
_Avoid_: Ownership

**Prerequisite**:
A Card that must precede another Card in a dependency relationship.
_Avoid_: Parent, blocker

**Dependent**:
A Card that relies on a Prerequisite.
_Avoid_: Child, blocked card

**Dispatcher**:
The server operation that claims eligible Ready Cards and may launch worker processes.
_Avoid_: Runner, launcher

**Preview Dispatch**:
A dry run that reports expected Dispatcher outcomes without launching workers.
_Avoid_: Test run, simulate dispatcher

**Run Dispatcher**:
The action that invokes the Dispatcher and may launch workers or consume API budget.
_Avoid_: Dispatch, run

**Dispatch Run**:
The recorded execution of the Dispatcher.
_Avoid_: Run, dispatcher result

**Archived**:
The Status of a Card removed from the active workflow.
_Avoid_: Deleted

**Archive Card**:
The action that changes a Card's Status to Archived.
_Avoid_: Delete Card, remove Card

**Archive Board**:
The action that removes a non-default Board from active use. Hermex cannot restore an archived Board in-app.
_Avoid_: Delete Board, remove Board

**Bulk Action**:
A named operation applied to multiple selected Cards.
_Avoid_: Bulk update, batch operation

**Select Cards**:
The mode for choosing Cards before applying a Bulk Action.
_Avoid_: Multi-select, bulk mode

## Watch companion

**Watch companion**:
The Apple Watch app (`HermexWatchApp`). It is a control surface for sessions already configured on iPhone, not a standalone Hermes client.
_Avoid_: Watch server, watch backend

**Phone broker**:
The iPhone `WatchCompanionServicing` implementation (`PhoneCompanionBroker`) that maps watch envelopes onto `APIClient`.
_Avoid_: Watch API, watch relay

**Watch scope**:
A `ServerScope` derived from the phone install epoch and a stable per-URL `ServerID`. Watch payloads must not carry the server URL or credentials.
_Avoid_: Server URL on watch

**Now**:
The watch home surface: the preferred session plus reply controls (type, speak, photo, listen) and stop. Preference is a running session, then one that needs attention, then a pinned session, then the most recently updated.
_Avoid_: Watch chat, mini iPhone, Active session (that copy is reserved for a truthful live state)

**Watch glance**:
A screen below Now that answers one question from the phone's data: Sessions, Tasks, Kanban, Usage, Profile, Skills, Memory, or Projects. Glances are read-only except Profile, which switches the active profile.
_Avoid_: Watch Kanban editor, watch settings

**Watch voice note**:
A wrist recording (up to 5 minutes, matching iOS) sent to the iPhone over WatchConnectivity. Clips that no longer fit `sendMessage` travel through `WCSession.transferFile`. The phone transcribes through `/api/transcribe`, uploads the same clip through `/api/upload`, and starts chat with the bare transcript plus that attachment — the same contract as iOS Composer voice notes. The watch does not talk to `hermes-webui`.
_Avoid_: Watch STT server, watch attachment upload
