# Phase 2 API Cheat-Sheet: TaskChampion 3.0.1 + UniFFI 0.29

**Created**: 2026-05-10 — reference for the Phase 2 implementor

> **Historical reference (as of 2026-05-10).** Version and API details may be
> outdated relative to the current code; `rust/vergissmeinnicht-core/` is authoritative.
> Still useful as an entry point for the FFI boundary.

---

## ⚠️ Version Warning

> Task description mentions `0.8`, crates.io delivers **`3.0.1`** (as of 2026-01-06, Rust ≥ 1.88).
> Version 0.8 is outdated. Most important breaking change:
> **all Replica methods are now `async fn`** → Tokio runtime required.

---

## 1. Cargo.toml

```toml
[dependencies]
uniffi       = { version = "0.29", features = ["cli"] }
taskchampion = { version = "3.0.1", features = ["storage-sqlite"] }
tokio        = { version = "1", features = ["rt", "macros", "sync"] }
uuid         = { version = "1", features = ["v4"] }
thiserror    = "2.0"

[build-dependencies]
uniffi = { version = "0.29", features = ["build"] }
```

`storage-sqlite` enables `SqliteStorage`. `bundled` (taskchampion default) links SQLite statically — good for macOS/iOS.

---

## 2. Open – Storage + Replica

```rust
use taskchampion::{storage::{AccessMode, SqliteStorage}, Replica};

// Type alias because of generics (UniFFI cannot export generics)
type AppReplica = Replica<SqliteStorage>;

async fn open_replica(path: std::path::PathBuf) -> Result<AppReplica, taskchampion::Error> {
    let storage = SqliteStorage::new(path, AccessMode::ReadWrite, true).await?;
    Ok(Replica::new(storage))
}
```

---

## 3. Add – Create a task

```rust
use taskchampion::{Operations, Status};
use uuid::Uuid;

async fn add_task(
    replica: &mut AppReplica,
    description: &str,
) -> Result<Uuid, taskchampion::Error> {
    let uuid = Uuid::new_v4();
    let mut ops = Operations::new();

    let mut task = replica.create_task(uuid, &mut ops).await?;
    task.set_description(description.to_owned(), &mut ops)?;
    task.set_status(Status::Pending, &mut ops)?;
    task.set_entry(Some(chrono::Utc::now()), &mut ops)?;

    replica.commit_operations(ops).await?;  // ← forgotten = task gone
    Ok(uuid)
}
```

`task.set_*()` only writes into `ops`, **not** into the DB. Only `commit_operations` persists.

---

## 4. List – List pending tasks

```rust
async fn list_pending(
    replica: &mut AppReplica,
) -> Result<Vec<(u64, String, String)>, taskchampion::Error> {
    let ws = replica.working_set().await?;  // snapshot of pending tasks
    let mut result = Vec::new();
    for (index, uuid) in ws.iter() {
        if let Some(task) = replica.get_task(uuid).await? {
            if task.get_status() == Status::Pending {
                result.push((index as u64, uuid.to_string(), task.get_description().to_owned()));
            }
        }
    }
    Ok(result)
}
// Alternatively: replica.all_tasks().await? → HashMap<Uuid, Task> (all statuses)
```

---

## 5. Error enum

```rust
// taskchampion::Error — #[non_exhaustive] → match needs _ =>
pub enum Error {
    Server(String),       // sync server error
    Database(String),     // SQLite/Storage
    OutOfSync,            // Replica outdated, sync impossible
    Usage(String),        // API misuse
    Other(anyhow::Error), // catch-all (via From<io::Error> etc.)
}
```

---

## 6. UniFFI 0.29 skeleton (lib.rs)

```rust
uniffi::setup_scaffolding!();
use std::sync::{Arc, Mutex};
use taskchampion::{storage::{AccessMode, SqliteStorage}, Operations, Replica, Status};
type AppReplica = Replica<SqliteStorage>;

// ─── FFI Error ───────────────────────────────────────────────────────────
#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum VmError {
    #[error("Storage: {msg}")]  Storage { msg: String },
    #[error("Not found")]        NotFound,
    #[error("Internal: {msg}")] Internal { msg: String },
}
impl From<taskchampion::Error> for VmError {
    fn from(e: taskchampion::Error) -> Self {
        match e {
            taskchampion::Error::Database(s) => Self::Storage { msg: s },
            taskchampion::Error::Usage(s)    => Self::Internal { msg: s },
            other => Self::Internal { msg: other.to_string() },
        }
    }
}

// ─── FFI Object ──────────────────────────────────────────────────────────
#[derive(uniffi::Object)]
pub struct TaskStore {
    replica: Mutex<AppReplica>,
    rt: tokio::runtime::Runtime, // cache once, don't recreate per call
}

#[uniffi::export]
impl TaskStore {
    #[uniffi::constructor]
    pub fn new(db_path: String) -> Result<Arc<Self>, VmError> {
        let rt = tokio::runtime::Runtime::new()
            .map_err(|e| VmError::Internal { msg: e.to_string() })?;
        let replica = rt.block_on(async {
            let s = SqliteStorage::new(db_path.into(), AccessMode::ReadWrite, true).await?;
            Ok::<_, taskchampion::Error>(Replica::new(s))
        })?;
        Ok(Arc::new(Self { replica: Mutex::new(replica), rt }))
    }

    pub fn add_task(&self, description: String) -> Result<String, VmError> {
        let mut replica = self.replica.lock().unwrap();
        let uuid = self.rt.block_on(add_task(&mut *replica, &description))?;
        Ok(uuid.to_string())
    }

    pub fn list_pending(&self) -> Result<Vec<String>, VmError> {
        let mut replica = self.replica.lock().unwrap();
        let tasks = self.rt.block_on(list_pending(&mut *replica))?;
        Ok(tasks.into_iter().map(|(_, _, desc)| desc).collect())
    }
}
```

---

## 7. Pitfalls

| # | Problem | Solution |
|---|---------|--------|
| 1 | **Everything async** — `SqliteStorage::new`, `create_task`, `commit_operations` | `rt.block_on(...)` in the FFI wrapper; cache runtime as a field |
| 2 | **`&mut self` on Replica** — UniFFI needs `&self` | `Mutex<AppReplica>` + `lock().unwrap()` |
| 3 | **Generic `Replica<S>`** — UniFFI exports no generics | Type alias `AppReplica = Replica<SqliteStorage>` |
| 4 | **`Operations` not over FFI** — internal buffer, must not cross the boundary | Keep internal to wrapper fns, never expose |
| 5 | **`Task` not exportable** — has `&mut self` methods + lifetime | Only return primitives (uuid: String, description: String) over FFI |
| 6 | **`Uuid` not a UniFFI base type** | Pass as `String`, internally `Uuid::parse_str(s)?` |
| 7 | **`#[non_exhaustive]` Error** | Always match with a `_ =>` arm |
| 8 | **feature `storage-sqlite` missing** | Explicitly in `Cargo.toml` — without it no `SqliteStorage` |
| 9 | **`chrono` dep** | `taskchampion` re-exports `chrono`; `use taskchampion::chrono::Utc` |
