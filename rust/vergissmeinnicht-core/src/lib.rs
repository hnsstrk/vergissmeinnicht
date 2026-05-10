uniffi::setup_scaffolding!();

use std::sync::{Arc, Mutex};

use taskchampion::{
    chrono::Utc,
    storage::AccessMode,
    Operations, Replica, SqliteStorage, Status,
};
use uuid::Uuid;

// UniFFI kann keine Generics exportieren — Typ-Alias auf konkrete Replica-Variante.
type AppReplica = Replica<SqliteStorage>;

// ─── Phase 1: Smoketest bleibt erhalten ─────────────────────────────────────

#[uniffi::export]
pub fn ping() -> String {
    "pong".to_string()
}

// ─── FFI Error ──────────────────────────────────────────────────────────────

#[derive(Debug, thiserror::Error, uniffi::Error)]
pub enum VmError {
    #[error("Storage: {msg}")]
    Storage { msg: String },
    #[error("Conversion: {msg}")]
    Conversion { msg: String },
    #[error("Internal: {msg}")]
    Internal { msg: String },
}

impl From<taskchampion::Error> for VmError {
    fn from(e: taskchampion::Error) -> Self {
        match e {
            taskchampion::Error::Database(s) => Self::Storage { msg: s },
            taskchampion::Error::Usage(s) => Self::Internal { msg: s },
            other => Self::Internal { msg: other.to_string() },
        }
    }
}

// ─── FFI Record ─────────────────────────────────────────────────────────────

#[derive(Debug, Clone, uniffi::Record)]
pub struct TaskInfo {
    pub uuid: String,
    pub description: String,
}

// ─── FFI Object ─────────────────────────────────────────────────────────────

#[derive(uniffi::Object)]
pub struct TaskStore {
    replica: Mutex<AppReplica>,
    rt: tokio::runtime::Runtime,
}

#[uniffi::export]
impl TaskStore {
    /// Öffnet (oder legt an) eine TaskChampion-SQLite-Replica unter `db_path`.
    /// Der Pfad muss ein Verzeichnis sein (TaskChampion legt darin SQLite-Dateien an).
    #[uniffi::constructor]
    pub fn new(db_path: String) -> Result<Arc<Self>, VmError> {
        // current-thread runtime — passt zu features = ["rt", "macros", "sync"]
        // (Runtime::new() würde rt-multi-thread voraussetzen).
        let rt = tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .map_err(|e| VmError::Internal { msg: e.to_string() })?;

        let replica = rt.block_on(async {
            let storage =
                SqliteStorage::new(std::path::PathBuf::from(db_path), AccessMode::ReadWrite, true)
                    .await?;
            Ok::<_, taskchampion::Error>(Replica::new(storage))
        })?;

        Ok(Arc::new(Self {
            replica: Mutex::new(replica),
            rt,
        }))
    }

    /// Legt einen neuen Task mit der gegebenen Description an und gibt seine UUID zurück.
    pub fn add_task(&self, description: String) -> Result<String, VmError> {
        let mut guard = self
            .replica
            .lock()
            .map_err(|e| VmError::Internal { msg: format!("mutex poisoned: {e}") })?;
        let replica: &mut AppReplica = &mut *guard;

        let uuid = self.rt.block_on(async {
            let new_uuid = Uuid::new_v4();
            let mut ops = Operations::new();
            let mut task = replica.create_task(new_uuid, &mut ops).await?;
            task.set_description(description, &mut ops)?;
            task.set_status(Status::Pending, &mut ops)?;
            task.set_entry(Some(Utc::now()), &mut ops)?;
            replica.commit_operations(ops).await?;
            Ok::<_, taskchampion::Error>(new_uuid)
        })?;

        Ok(uuid.to_string())
    }

    /// Listet alle aktuell pendenden Tasks (Working Set) als `TaskInfo` mit UUID + Description.
    pub fn list_pending(&self) -> Result<Vec<TaskInfo>, VmError> {
        let mut guard = self
            .replica
            .lock()
            .map_err(|e| VmError::Internal { msg: format!("mutex poisoned: {e}") })?;
        let replica: &mut AppReplica = &mut *guard;

        let infos = self.rt.block_on(async {
            let ws = replica.working_set().await?;
            let mut out = Vec::new();
            for (_index, uuid) in ws.iter() {
                if let Some(task) = replica.get_task(uuid).await? {
                    if task.get_status() == Status::Pending {
                        out.push(TaskInfo {
                            uuid: uuid.to_string(),
                            description: task.get_description().to_owned(),
                        });
                    }
                }
            }
            Ok::<_, taskchampion::Error>(out)
        })?;

        Ok(infos)
    }
}
