# Phase 2 API Cheat-Sheet: TaskChampion 3.0.1 + UniFFI 0.29

**Erstellt**: 2026-05-10 — Referenz für Phase-2-Implementor

> **Historische Referenz (Stand 2026-05-10).** Versions- und API-Angaben können
> gegenüber dem aktuellen Code veraltet sein; maßgeblich ist `rust/vergissmeinnicht-core/`.
> Als Einstiegshilfe für die FFI-Grenze weiterhin nützlich.

---

## ⚠️ Versions-Warnung

> Task-Beschreibung nennt `0.8`, crates.io liefert **`3.0.1`** (Stand 2026-01-06, Rust ≥ 1.88).
> Version 0.8 ist veraltet. Wichtigste Breaking-Change:
> **alle Replica-Methoden sind jetzt `async fn`** → Tokio-Runtime erforderlich.

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

`storage-sqlite` aktiviert `SqliteStorage`. `bundled` (taskchampion-default) linkt SQLite statisch — gut für macOS/iOS.

---

## 2. Open – Storage + Replica

```rust
use taskchampion::{storage::{AccessMode, SqliteStorage}, Replica};

// Typ-Alias wegen Generics (UniFFI kann keine Generics exportieren)
type AppReplica = Replica<SqliteStorage>;

async fn open_replica(path: std::path::PathBuf) -> Result<AppReplica, taskchampion::Error> {
    let storage = SqliteStorage::new(path, AccessMode::ReadWrite, true).await?;
    Ok(Replica::new(storage))
}
```

---

## 3. Add – Task anlegen

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

    replica.commit_operations(ops).await?;  // ← vergessen = Task weg
    Ok(uuid)
}
```

`task.set_*()` schreibt nur in `ops`, **nicht** in die DB. Erst `commit_operations` persistiert.

---

## 4. List – Pending-Tasks auflisten

```rust
async fn list_pending(
    replica: &mut AppReplica,
) -> Result<Vec<(u64, String, String)>, taskchampion::Error> {
    let ws = replica.working_set().await?;  // Snapshot Pending-Tasks
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
// Alternativ: replica.all_tasks().await? → HashMap<Uuid, Task> (alle Status)
```

---

## 5. Error-Enum

```rust
// taskchampion::Error — #[non_exhaustive] → match braucht _ =>
pub enum Error {
    Server(String),       // Sync-Server-Fehler
    Database(String),     // SQLite/Storage
    OutOfSync,            // Replica veraltet, Sync unmöglich
    Usage(String),        // API-Missbrauch
    Other(anyhow::Error), // Catch-all (via From<io::Error> etc.)
}
```

---

## 6. UniFFI 0.29 Skelett (lib.rs)

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
    rt: tokio::runtime::Runtime, // einmal cachen, nicht pro Aufruf neu erstellen
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

## 7. Stolpersteine

| # | Problem | Lösung |
|---|---------|--------|
| 1 | **Alles async** — `SqliteStorage::new`, `create_task`, `commit_operations` | `rt.block_on(...)` im FFI-Wrapper; Runtime als Feld cachen |
| 2 | **`&mut self` auf Replica** — UniFFI braucht `&self` | `Mutex<AppReplica>` + `lock().unwrap()` |
| 3 | **Generischer `Replica<S>`** — UniFFI exportiert keine Generics | Typ-Alias `AppReplica = Replica<SqliteStorage>` |
| 4 | **`Operations` nicht über FFI** — interner Puffer, darf die Grenze nicht kreuzen | Intern in Wrapper-Fns halten, nie exponieren |
| 5 | **`Task` nicht exportierbar** — hat `&mut self`-Methoden + Lifetime | Nur Primitives (uuid: String, description: String) über FFI liefern |
| 6 | **`Uuid` kein UniFFI-Basistyp** | Als `String` übergeben, intern `Uuid::parse_str(s)?` |
| 7 | **`#[non_exhaustive]` Error** | Match immer mit `_ =>` Arm |
| 8 | **feature `storage-sqlite` fehlt** | Explizit in `Cargo.toml` — ohne it kein `SqliteStorage` |
| 9 | **`chrono` Dep** | `taskchampion` re-exportiert `chrono`; `use taskchampion::chrono::Utc` |
