# Architecture Notes

Design rationale for the storage layer of Vergissmeinnicht. This document explains
*why* a few non-obvious choices look the way they do in the code; for the build
toolchain and failure modes read [`building.md`](building.md), and for the layer
overview read [`../README.md`](../README.md).

Three things tend to surprise readers of the source: the deeply nested replica
path, the `u32` working-set ID on `TaskInfo`, and the single long-lived replica
behind a `Mutex`. Each is covered below, grounded in the current code.

## Container hierarchy

The on-disk replica lives at:

```
~/Library/Containers/de.hnsstrk.vergissmeinnicht/Data/Library/Application Support/vergissmeinnicht/replica/
```

That full path is **not** constructed by the app. The relevant code is
`replicaURL()` in
`app/Vergissmeinnicht/Sources/VergissmeinnichtApp/AppContainer.swift`:

```swift
let appSupport = try fm.url(
    for: .applicationSupportDirectory,
    in: .userDomainMask,
    appropriateFor: nil,
    create: true
)
let replicaDir = appSupport
    .appendingPathComponent("vergissmeinnicht", isDirectory: true)
    .appendingPathComponent("replica", isDirectory: true)
```

The app only asks for a *logical* location — the user-domain Application Support
directory — and appends `vergissmeinnicht/replica`. The
`Containers/de.hnsstrk.vergissmeinnicht/Data/…` prefix is supplied by macOS: the
app ships sandboxed (`com.apple.security.app-sandbox`), and the sandbox
**redirects** `~/Library/Application Support` into the per-app container. The app
never hardcodes the container path; it asks for a logical location and the
sandbox decides the physical one.

**Why sandboxed at all.** The sandbox is what lets the app be distributed without
ambient access to the user's home directory. The relevant consequence for storage
is the inverse of the redirect: a sandboxed app has **no read access to the
Taskwarrior CLI's `~/.task/`** directory. The two stores are deliberately
separate.

**How data crosses the boundary.** Because the app cannot reach `~/.task/`, it
does not share a database with the CLI. Both sides are independent TaskChampion
replicas that converge through the *same sync server*: the app's replica syncs to
a user-configured `taskchampion-sync-server` over HTTPS, and the CLI syncs to the
same server. There is no file-level data exchange — sync is the only channel.
(Sync credentials live in the Keychain, never in `UserDefaults`; see
`KeychainStore.swift`.)

This is why the path looks the way it does and why the app feels isolated from a
local `task` install: it is, by design, and the only shared state is whatever both
replicas push to and pull from the server.

To inspect or reset the replica on disk, see *Replica location and reset* in
[`building.md`](building.md).

## Working-set ID (`u32`)

`TaskInfo` in `rust/vergissmeinnicht-core/src/lib.rs` carries:

```rust
/// Working-Set-ID (Taskwarrior-typische numerische ID, 1-N). Nur für Pending-Tasks
/// definiert; für Completed/Deleted ist `None`.
pub working_set_id: Option<u32>,
```

This is the small numeric id Taskwarrior users know — the `1`, `2`, `3` …
in `task list`. It is derived from TaskChampion's *working set*, the index of
currently pending tasks. In `list_tasks` the field is filled only inside the
working-set loop:

```rust
let ws = replica.working_set().await?;
for (index, uuid) in ws.iter() {
    if let Some(task) = replica.get_task(uuid).await? {
        if task.get_status() == Status::Pending {
            out.push(build_task_info(&task, uuid, Some(index as u32)));
        }
    }
}
```

**Why `Option`.** The id exists only for tasks in the working set, i.e. pending
tasks. Completed, deleted, or recurring-master tasks have no working-set index,
so the field is `None` for them. `Option<u32>` encodes exactly that.

**Why a fixed-width integer.** `working_set().iter()` yields `usize` indices.
`usize` cannot cross the UniFFI boundary — UniFFI has no `usize` type — so a
fixed-width integer is required at the FFI surface. (The same constraint shows up
elsewhere: `pending_count` returns `u64` because its `usize` count has to be
widened for FFI.) The code casts `index as u32`.

**Why `u32` is enough.** The working-set index counts pending tasks. `u32` tops
out at ~4.3 billion, which trivially exceeds any realistic pending-task count, so
the cast cannot overflow in practice. The code does not document a reason to
prefer `u32` over `u64` here, and this note does not invent one — it is simply a
fixed-width type wide enough for the bounds. Note that the field width is not
uniform across the FFI surface (`pending_count` is `u64`); `working_set_id` is
`u32` and that is the only claim made here.

**It is not a stable identifier.** The working-set id is recomputed from
`working_set()` on every `list_tasks` call. It can change when tasks are
completed, added, or the working set is otherwise renumbered. The **stable**
identity of a task is its UUID (`TaskInfo.uuid`); the working-set id is a
display/convenience number only. Any persistence, cross-reference, or lookup must
use the UUID, never the working-set id.

## Replica lifecycle

The replica is **opened once** and kept alive for the lifetime of the process —
there is no per-operation open/close. The relevant types and the constructor in
`lib.rs`:

```rust
type AppReplica = Replica<SqliteStorage>;

#[derive(uniffi::Object)]
pub struct TaskStore {
    replica: Mutex<AppReplica>,
    rt: tokio::runtime::Runtime,
}
```

`AppReplica` is a type alias because UniFFI cannot export the generic
`Replica<SqliteStorage>` directly.

**Open.** In the `TaskStore::new` constructor the SQLite storage is opened in
read-write mode (creating it if missing) and wrapped in a `Replica`, once:

```rust
let storage =
    SqliteStorage::new(PathBuf::from(db_path), AccessMode::ReadWrite, true).await?;
Ok::<_, taskchampion::Error>(Replica::new(storage))
```

The resulting `Replica` is stored in `Mutex<AppReplica>` and reused for every
subsequent call.

**Two distinct locks.** "Locking" means two different things here, and conflating
them is a common mistake:

- *In-process* — the Rust `Mutex<AppReplica>`. `Replica<SqliteStorage>` is
  `!Send`, so the `MutexGuard` is held across the entire `rt.block_on(...)` call.
  The Tokio runtime is intentionally **current-thread** (`new_current_thread()`,
  features `rt`/`macros`/`sync` — *not* `rt-multi-thread`); a single thread drives
  the `!Send` replica, and the mutex serialises all FFI calls so no two run
  concurrently. (On a poisoned mutex the guard is recovered via `into_inner()`
  rather than failing every later call until restart — see the `lock_replica`
  doc comment for the safety argument.)
- *Cross-process* — the SQLite file lock on the on-disk database. This is what
  produces the "SQLite busy" / "Replica locked" failure when a second app
  instance tries to open the same replica (see *Common failures* in
  [`building.md`](building.md)). It is enforced by SQLite, not by this code.

**Commit.** Writes follow TaskChampion's operation model: each mutating call
builds an `Operations` batch, applies the changes to the in-memory task, then
commits the whole batch atomically:

```rust
let mut ops = Operations::new();
let mut task = replica.create_task(new_uuid, &mut ops).await?;
task.set_description(description, &mut ops)?;
task.set_status(Status::Pending, &mut ops)?;
task.set_entry(Some(Utc::now()), &mut ops)?;
replica.commit_operations(ops).await?;
```

`commit_operations` is the single durability point — all setters before it only
mutate the in-memory `Operations`; nothing reaches SQLite until the commit. Every
write method in `TaskStore` follows this open-once / batch-ops / `commit_operations`
shape under the same mutex guard.
