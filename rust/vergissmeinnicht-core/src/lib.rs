uniffi::setup_scaffolding!();

use std::sync::{Arc, Mutex};

use std::str::FromStr;

use taskchampion::{
    chrono::{DateTime, Utc},
    storage::AccessMode,
    Annotation, Operations, Replica, ServerConfig, SqliteStorage, Status, Tag,
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
    #[error("Not found: {uuid}")]
    NotFound { uuid: String },
    #[error("Sync: {msg}")]
    Sync { msg: String },
    #[error("Internal: {msg}")]
    Internal { msg: String },
}

impl From<taskchampion::Error> for VmError {
    fn from(e: taskchampion::Error) -> Self {
        match e {
            taskchampion::Error::Database(s) => Self::Storage { msg: s },
            taskchampion::Error::Usage(s) => Self::Internal { msg: s },
            taskchampion::Error::Server(s) => Self::Sync { msg: s },
            other => Self::Internal { msg: other.to_string() },
        }
    }
}

fn parse_uuid(uuid: &str) -> Result<Uuid, VmError> {
    Uuid::parse_str(uuid).map_err(|e| VmError::Conversion { msg: e.to_string() })
}

/// Konvertiert Unix-Sekunden in einen `DateTime<Utc>`. Out-of-range-Werte werden als
/// Conversion-Error gemeldet, statt zu panicen.
fn timestamp_from_secs(secs: i64) -> Result<DateTime<Utc>, VmError> {
    DateTime::<Utc>::from_timestamp(secs, 0)
        .ok_or_else(|| VmError::Conversion { msg: format!("due timestamp out of range: {secs}") })
}

/// Baut ein `TaskInfo` aus einem `taskchampion::Task` plus optionaler Working-Set-ID.
/// Zentralisiert die Property-Extraktion (project, tags, due, entry, priority, annotations).
fn build_task_info(task: &taskchampion::Task, uuid: Uuid, working_set_id: Option<u32>) -> TaskInfo {
    let project = task
        .get_value("project")
        .map(|s| s.to_owned())
        .filter(|s| !s.is_empty());
    let tags: Vec<String> = task
        .get_tags()
        .filter(|t| t.is_user())
        .map(|t| t.to_string())
        .collect();
    let due = task.get_due().map(|ts| ts.timestamp());
    let entry = task.get_entry().map(|ts| ts.timestamp());
    let priority = {
        let p = task.get_priority();
        if p.is_empty() { None } else { Some(p.to_owned()) }
    };
    let annotations: Vec<AnnotationInfo> = task
        .get_annotations()
        .map(|a| AnnotationInfo {
            entry: a.entry.timestamp(),
            description: a.description,
        })
        .collect();
    let wait = task.get_wait().map(|ts| ts.timestamp());
    let recur = task
        .get_value("recur")
        .map(|s| s.to_owned())
        .filter(|s| !s.is_empty());
    let scheduled = task
        .get_value("scheduled")
        .and_then(|s| s.parse::<i64>().ok());
    let status = match task.get_status() {
        Status::Pending => TaskStatus::Pending,
        Status::Completed => TaskStatus::Completed,
        _ => TaskStatus::Deleted,
    };
    TaskInfo {
        uuid: uuid.to_string(),
        description: task.get_description().to_owned(),
        project,
        tags,
        due,
        status,
        entry,
        working_set_id,
        priority,
        annotations,
        wait,
        recur,
        scheduled,
    }
}


// ─── FFI Records ────────────────────────────────────────────────────────────

#[derive(Debug, Clone, Copy, PartialEq, Eq, uniffi::Enum)]
pub enum TaskStatus {
    Pending,
    Completed,
    Deleted,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct AnnotationInfo {
    /// Entry-Zeitpunkt der Annotation als Unix-Sekunden (i64). Dient gleichzeitig als
    /// Schlüssel beim Entfernen.
    pub entry: i64,
    pub description: String,
}

#[derive(Debug, Clone, uniffi::Record)]
pub struct TaskInfo {
    pub uuid: String,
    pub description: String,
    /// Wert der `project`-Property; leer falls nicht gesetzt.
    pub project: Option<String>,
    /// User-Tags (synthetische TaskChampion-Tags wie PENDING/OVERDUE sind herausgefiltert).
    pub tags: Vec<String>,
    /// Due-Date als Unix-Sekunden (i64). UniFFI bildet `Option<chrono::DateTime>` nicht direkt
    /// auf Swift ab; der i64-Pfad ist robust und auf Swift-Seite via `Date(timeIntervalSince1970:)`
    /// trivial konvertierbar.
    pub due: Option<i64>,
    /// Status des Tasks (pending / completed / deleted).
    pub status: TaskStatus,
    /// Entry-Zeitpunkt der Task (Anlage-Datum) als Unix-Sekunden. Wird beim Anlegen gesetzt.
    pub entry: Option<i64>,
    /// Working-Set-ID (Taskwarrior-typische numerische ID, 1-N). Nur für Pending-Tasks
    /// definiert; für Completed/Deleted ist `None`.
    pub working_set_id: Option<u32>,
    /// Priority-Property als Rohwert (typisch `H` / `M` / `L`); nicht validiert.
    pub priority: Option<String>,
    /// Annotations zum Task, in beliebiger Reihenfolge.
    pub annotations: Vec<AnnotationInfo>,
    /// Wait-Property (Snooze) als Unix-Sekunden. Liegt ein Wert in der Zukunft,
    /// gilt der Task als „wartend" — Taskwarrior versteckt solche Tasks per Default
    /// aus `task list`; die App zeigt sie in einer eigenen Sidebar-Sektion.
    pub wait: Option<i64>,
    /// Recur-Property als Rohstring (z.B. `daily`, `weekly`, `monthly`, `1d`, `2w`).
    /// Wir interpretieren es App-seitig — TaskChampion-Lib generiert keine Children.
    pub recur: Option<String>,
    /// Scheduled-Property (Start-Datum / Defer-Until) als Unix-Sekunden. Tasks mit
    /// `scheduled` in der Zukunft sind „geplant" und werden aus ToDo/Inbox/Überfällig
    /// ausgeblendet, bis das Datum erreicht ist (Hide-until-date).
    pub scheduled: Option<i64>,
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

    /// Legt einen neuen Task mit voller Metadaten-Persistierung an: project (raw value),
    /// User-Tags und due (Unix-Sekunden). Leere Tags und None/Empty-Project werden
    /// nicht geschrieben. Tag-Strings müssen TaskChampion-konform sein
    /// (kein Whitespace, kein Operator-Zeichen am Anfang, kein Doppelpunkt darin).
    pub fn add_task_full(
        &self,
        description: String,
        project: Option<String>,
        tags: Vec<String>,
        due: Option<i64>,
    ) -> Result<String, VmError> {
        let mut guard = self
            .replica
            .lock()
            .map_err(|e| VmError::Internal { msg: format!("mutex poisoned: {e}") })?;
        let replica: &mut AppReplica = &mut *guard;

        let due_ts = match due {
            Some(secs) => Some(timestamp_from_secs(secs)?),
            None => None,
        };

        let uuid = self.rt.block_on(async {
            let new_uuid = Uuid::new_v4();
            let mut ops = Operations::new();
            let mut task = replica.create_task(new_uuid, &mut ops).await?;
            task.set_description(description, &mut ops)?;
            task.set_status(Status::Pending, &mut ops)?;
            task.set_entry(Some(Utc::now()), &mut ops)?;

            if let Some(p) = project.as_ref().filter(|s| !s.is_empty()) {
                task.set_value("project", Some(p.clone()), &mut ops)?;
            }
            for tag_str in &tags {
                let tag = Tag::from_str(tag_str)
                    .map_err(|e| VmError::Conversion { msg: format!("invalid tag {tag_str:?}: {e}") })?;
                task.add_tag(&tag, &mut ops)?;
            }
            if let Some(ts) = due_ts {
                task.set_due(Some(ts), &mut ops)?;
            }

            replica.commit_operations(ops).await?;
            Ok::<_, VmError>(new_uuid)
        })?;

        Ok(uuid.to_string())
    }

    /// Aktualisiert Metadaten eines bestehenden Tasks in einer einzigen Commit-Batch:
    /// Description, project (None = clear), Tags (komplette Ersetzung), due (None = clear).
    /// Verwendet vom Reparatur-Lauf, der Legacy-Tasks (`+tag` / `project:foo` in der
    /// Description als Text) in saubere Properties überführt.
    pub fn update_task_metadata(
        &self,
        uuid: String,
        description: String,
        project: Option<String>,
        tags: Vec<String>,
        due: Option<i64>,
    ) -> Result<(), VmError> {
        let task_uuid = parse_uuid(&uuid)?;
        let mut guard = self
            .replica
            .lock()
            .map_err(|e| VmError::Internal { msg: format!("mutex poisoned: {e}") })?;
        let replica: &mut AppReplica = &mut *guard;

        let due_ts = match due {
            Some(secs) => Some(timestamp_from_secs(secs)?),
            None => None,
        };

        self.rt.block_on(async {
            let mut ops = Operations::new();
            let mut task = replica
                .get_task(task_uuid)
                .await?
                .ok_or(VmError::NotFound { uuid: uuid.clone() })?;

            task.set_description(description, &mut ops)?;

            // Project: explizit setzen oder clearen.
            let project_value = project.filter(|s| !s.is_empty());
            task.set_value("project", project_value, &mut ops)?;

            // Tags: User-Tags vorher entfernen, dann neue setzen (Synthetics bleiben).
            let current_user_tags: Vec<Tag> = task
                .get_tags()
                .filter(|t| t.is_user())
                .collect();
            for t in &current_user_tags {
                task.remove_tag(t, &mut ops)?;
            }
            for tag_str in &tags {
                let tag = Tag::from_str(tag_str)
                    .map_err(|e| VmError::Conversion { msg: format!("invalid tag {tag_str:?}: {e}") })?;
                task.add_tag(&tag, &mut ops)?;
            }

            task.set_due(due_ts, &mut ops)?;

            replica.commit_operations(ops).await?;
            Ok::<_, VmError>(())
        })
    }

    /// Listet alle Tasks (Pending oder optional auch Completed).
    /// Deleted-Tasks bleiben immer aussen vor.
    ///
    /// Bei `include_completed = false` wird das Working Set in seiner natürlichen
    /// Reihenfolge durchlaufen (so haben Pending-Tasks einen stabilen
    /// `working_set_id`). Bei `true` werden alle Pending zuerst ausgegeben (mit ID),
    /// danach alle Completed (ohne ID) — die App kann clientseitig sortieren.
    pub fn list_tasks(&self, include_completed: bool) -> Result<Vec<TaskInfo>, VmError> {
        let mut guard = self
            .replica
            .lock()
            .map_err(|e| VmError::Internal { msg: format!("mutex poisoned: {e}") })?;
        let replica: &mut AppReplica = &mut *guard;

        let infos = self.rt.block_on(async {
            let ws = replica.working_set().await?;
            let mut out = Vec::new();
            let mut seen_pending = std::collections::HashSet::new();

            for (index, uuid) in ws.iter() {
                if let Some(task) = replica.get_task(uuid).await? {
                    if task.get_status() == Status::Pending {
                        seen_pending.insert(uuid);
                        out.push(build_task_info(&task, uuid, Some(index as u32)));
                    }
                }
            }

            if include_completed {
                let all = replica.all_tasks().await?;
                for (uuid, task) in all.iter() {
                    if task.get_status() == Status::Completed {
                        out.push(build_task_info(task, *uuid, None));
                    }
                }
                // Pending, die nicht im Working Set waren (sollte nicht vorkommen,
                // aber theoretisch möglich), gerätsicherheitshalber ergänzen.
                for (uuid, task) in all.iter() {
                    if task.get_status() == Status::Pending && !seen_pending.contains(uuid) {
                        out.push(build_task_info(task, *uuid, None));
                    }
                }
            }

            Ok::<_, taskchampion::Error>(out)
        })?;

        Ok(infos)
    }

    /// Backwards-Compat-Alias für die App: nur Pending, mit Working-Set-IDs.
    pub fn list_pending(&self) -> Result<Vec<TaskInfo>, VmError> {
        self.list_tasks(false)
    }

    /// Markiert die Task mit `uuid` als erledigt (`Status::Completed`) und committet.
    pub fn mark_done(&self, uuid: String) -> Result<(), VmError> {
        let task_uuid = parse_uuid(&uuid)?;
        let mut guard = self
            .replica
            .lock()
            .map_err(|e| VmError::Internal { msg: format!("mutex poisoned: {e}") })?;
        let replica: &mut AppReplica = &mut *guard;

        self.rt.block_on(async {
            let mut ops = Operations::new();
            let mut task = replica
                .get_task(task_uuid)
                .await?
                .ok_or(VmError::NotFound { uuid: uuid.clone() })?;
            task.set_status(Status::Completed, &mut ops)?;
            replica.commit_operations(ops).await?;
            Ok::<_, VmError>(())
        })
    }

    /// Ändert die Beschreibung der Task mit `uuid` und committet.
    pub fn modify_description(
        &self,
        uuid: String,
        new_description: String,
    ) -> Result<(), VmError> {
        let task_uuid = parse_uuid(&uuid)?;
        let mut guard = self
            .replica
            .lock()
            .map_err(|e| VmError::Internal { msg: format!("mutex poisoned: {e}") })?;
        let replica: &mut AppReplica = &mut *guard;

        self.rt.block_on(async {
            let mut ops = Operations::new();
            let mut task = replica
                .get_task(task_uuid)
                .await?
                .ok_or(VmError::NotFound { uuid: uuid.clone() })?;
            task.set_description(new_description, &mut ops)?;
            replica.commit_operations(ops).await?;
            Ok::<_, VmError>(())
        })
    }

    /// Markiert die Task mit `uuid` als gelöscht (`Status::Deleted`) und committet.
    /// Das Operations-Log bleibt erhalten — kein Purge.
    pub fn delete_task(&self, uuid: String) -> Result<(), VmError> {
        let task_uuid = parse_uuid(&uuid)?;
        let mut guard = self
            .replica
            .lock()
            .map_err(|e| VmError::Internal { msg: format!("mutex poisoned: {e}") })?;
        let replica: &mut AppReplica = &mut *guard;

        self.rt.block_on(async {
            let mut ops = Operations::new();
            let mut task = replica
                .get_task(task_uuid)
                .await?
                .ok_or(VmError::NotFound { uuid: uuid.clone() })?;
            task.set_status(Status::Deleted, &mut ops)?;
            replica.commit_operations(ops).await?;
            Ok::<_, VmError>(())
        })
    }

    /// Hängt eine Annotation an die Task mit `uuid` an. Entry-Zeitstempel = `Utc::now()`.
    pub fn add_annotation(&self, uuid: String, annotation: String) -> Result<(), VmError> {
        let task_uuid = parse_uuid(&uuid)?;
        let mut guard = self
            .replica
            .lock()
            .map_err(|e| VmError::Internal { msg: format!("mutex poisoned: {e}") })?;
        let replica: &mut AppReplica = &mut *guard;

        self.rt.block_on(async {
            let mut ops = Operations::new();
            let mut task = replica
                .get_task(task_uuid)
                .await?
                .ok_or(VmError::NotFound { uuid: uuid.clone() })?;
            task.add_annotation(
                Annotation {
                    entry: Utc::now(),
                    description: annotation,
                },
                &mut ops,
            )?;
            replica.commit_operations(ops).await?;
            Ok::<_, VmError>(())
        })
    }

    /// Entfernt die Annotation mit dem gegebenen Entry-Zeitstempel (Unix-Sekunden).
    /// Wird vom Detail-Editor zum Löschen einzelner Annotations genutzt.
    pub fn remove_annotation(&self, uuid: String, entry: i64) -> Result<(), VmError> {
        let task_uuid = parse_uuid(&uuid)?;
        let ts = timestamp_from_secs(entry)?;
        let mut guard = self
            .replica
            .lock()
            .map_err(|e| VmError::Internal { msg: format!("mutex poisoned: {e}") })?;
        let replica: &mut AppReplica = &mut *guard;

        self.rt.block_on(async {
            let mut ops = Operations::new();
            let mut task = replica
                .get_task(task_uuid)
                .await?
                .ok_or(VmError::NotFound { uuid: uuid.clone() })?;
            task.remove_annotation(ts, &mut ops)?;
            replica.commit_operations(ops).await?;
            Ok::<_, VmError>(())
        })
    }

    /// Setzt das `project`-Property. `None` oder leerer String entfernt es.
    pub fn set_project(&self, uuid: String, project: Option<String>) -> Result<(), VmError> {
        let task_uuid = parse_uuid(&uuid)?;
        let mut guard = self
            .replica
            .lock()
            .map_err(|e| VmError::Internal { msg: format!("mutex poisoned: {e}") })?;
        let replica: &mut AppReplica = &mut *guard;

        self.rt.block_on(async {
            let mut ops = Operations::new();
            let mut task = replica
                .get_task(task_uuid)
                .await?
                .ok_or(VmError::NotFound { uuid: uuid.clone() })?;
            let value = project.filter(|s| !s.is_empty());
            task.set_value("project", value, &mut ops)?;
            replica.commit_operations(ops).await?;
            Ok::<_, VmError>(())
        })
    }

    /// Setzt das `due`-Property (Unix-Sekunden). `None` entfernt die Fälligkeit.
    pub fn set_due(&self, uuid: String, due: Option<i64>) -> Result<(), VmError> {
        let task_uuid = parse_uuid(&uuid)?;
        let due_ts = match due {
            Some(secs) => Some(timestamp_from_secs(secs)?),
            None => None,
        };
        let mut guard = self
            .replica
            .lock()
            .map_err(|e| VmError::Internal { msg: format!("mutex poisoned: {e}") })?;
        let replica: &mut AppReplica = &mut *guard;

        self.rt.block_on(async {
            let mut ops = Operations::new();
            let mut task = replica
                .get_task(task_uuid)
                .await?
                .ok_or(VmError::NotFound { uuid: uuid.clone() })?;
            task.set_due(due_ts, &mut ops)?;
            replica.commit_operations(ops).await?;
            Ok::<_, VmError>(())
        })
    }

    /// Markiert eine Pending-Task als erledigt und legt — sofern `recur` und
    /// `new_due` gesetzt sind — in derselben Operations-Batch eine neue Pending-
    /// Instanz an. Description/Project/Tags/Priority werden kopiert; Annotations
    /// werden bewusst NICHT übertragen, da Annotations zeitpunktbezogen sind.
    /// Gibt die UUID der neu erzeugten Folge-Instanz zurück (`None`, wenn keine).
    pub fn mark_done_with_followup(
        &self,
        uuid: String,
        new_due: Option<i64>,
        recur: Option<String>,
        priority: Option<String>,
        project: Option<String>,
        tags: Vec<String>,
        description: String,
    ) -> Result<Option<String>, VmError> {
        let task_uuid = parse_uuid(&uuid)?;
        let due_ts = match new_due {
            Some(secs) => Some(timestamp_from_secs(secs)?),
            None => None,
        };
        let mut guard = self
            .replica
            .lock()
            .map_err(|e| VmError::Internal { msg: format!("mutex poisoned: {e}") })?;
        let replica: &mut AppReplica = &mut *guard;

        let new_uuid: Option<Uuid> = self.rt.block_on(async {
            let mut ops = Operations::new();
            let mut task = replica
                .get_task(task_uuid)
                .await?
                .ok_or(VmError::NotFound { uuid: uuid.clone() })?;
            task.set_status(Status::Completed, &mut ops)?;

            // Folge-Instanz nur, wenn recur UND new_due gesetzt.
            let create_followup = recur.as_ref().map(|s| !s.is_empty()).unwrap_or(false) && due_ts.is_some();
            let new_uuid = if create_followup {
                let new_uuid = Uuid::new_v4();
                let mut new_task = replica.create_task(new_uuid, &mut ops).await?;
                new_task.set_description(description, &mut ops)?;
                new_task.set_status(Status::Pending, &mut ops)?;
                new_task.set_entry(Some(Utc::now()), &mut ops)?;
                if let Some(p) = project.as_ref().filter(|s| !s.is_empty()) {
                    new_task.set_value("project", Some(p.clone()), &mut ops)?;
                }
                for tag_str in &tags {
                    let tag = Tag::from_str(tag_str)
                        .map_err(|e| VmError::Conversion { msg: format!("invalid tag {tag_str:?}: {e}") })?;
                    new_task.add_tag(&tag, &mut ops)?;
                }
                if let Some(ts) = due_ts {
                    new_task.set_due(Some(ts), &mut ops)?;
                }
                if let Some(p) = priority.as_ref().filter(|s| !s.is_empty()) {
                    new_task.set_value("priority", Some(p.clone()), &mut ops)?;
                }
                if let Some(r) = recur.as_ref().filter(|s| !s.is_empty()) {
                    new_task.set_value("recur", Some(r.clone()), &mut ops)?;
                }
                Some(new_uuid)
            } else {
                None
            };

            replica.commit_operations(ops).await?;
            Ok::<_, VmError>(new_uuid)
        })?;

        Ok(new_uuid.map(|u| u.to_string()))
    }

    /// Setzt das `scheduled`-Property (Start-Datum als Unix-Sekunden). `None`
    /// entfernt es. Tasks mit `scheduled` in der Zukunft gelten App-seitig als
    /// „geplant".
    pub fn set_scheduled(&self, uuid: String, scheduled: Option<i64>) -> Result<(), VmError> {
        let task_uuid = parse_uuid(&uuid)?;
        let mut guard = self
            .replica
            .lock()
            .map_err(|e| VmError::Internal { msg: format!("mutex poisoned: {e}") })?;
        let replica: &mut AppReplica = &mut *guard;

        self.rt.block_on(async {
            let mut ops = Operations::new();
            let mut task = replica
                .get_task(task_uuid)
                .await?
                .ok_or(VmError::NotFound { uuid: uuid.clone() })?;
            let value = scheduled.map(|s| s.to_string());
            task.set_value("scheduled", value, &mut ops)?;
            replica.commit_operations(ops).await?;
            Ok::<_, VmError>(())
        })
    }

    /// Setzt das `recur`-Property (z.B. `daily`, `weekly`, `1d`, `2w`). `None` oder
    /// leerer String entfernen es. Wird app-seitig interpretiert — TaskChampion-Lib
    /// generiert keine Children automatisch.
    pub fn set_recur(&self, uuid: String, recur: Option<String>) -> Result<(), VmError> {
        let task_uuid = parse_uuid(&uuid)?;
        let mut guard = self
            .replica
            .lock()
            .map_err(|e| VmError::Internal { msg: format!("mutex poisoned: {e}") })?;
        let replica: &mut AppReplica = &mut *guard;

        self.rt.block_on(async {
            let mut ops = Operations::new();
            let mut task = replica
                .get_task(task_uuid)
                .await?
                .ok_or(VmError::NotFound { uuid: uuid.clone() })?;
            let value = recur.filter(|s| !s.is_empty());
            task.set_value("recur", value, &mut ops)?;
            replica.commit_operations(ops).await?;
            Ok::<_, VmError>(())
        })
    }

    /// Setzt das `priority`-Property (`H` / `M` / `L`). `None` oder leerer String
    /// entfernt es. Es wird nicht validiert — Taskwarrior toleriert beliebige
    /// Strings, sortiert aber clientseitig nach diesem Wert.
    pub fn set_priority(&self, uuid: String, priority: Option<String>) -> Result<(), VmError> {
        let task_uuid = parse_uuid(&uuid)?;
        let mut guard = self
            .replica
            .lock()
            .map_err(|e| VmError::Internal { msg: format!("mutex poisoned: {e}") })?;
        let replica: &mut AppReplica = &mut *guard;

        self.rt.block_on(async {
            let mut ops = Operations::new();
            let mut task = replica
                .get_task(task_uuid)
                .await?
                .ok_or(VmError::NotFound { uuid: uuid.clone() })?;
            let value = priority.filter(|s| !s.is_empty());
            task.set_value("priority", value, &mut ops)?;
            replica.commit_operations(ops).await?;
            Ok::<_, VmError>(())
        })
    }

    /// Fügt einen einzelnen User-Tag hinzu. No-op, falls der Tag bereits existiert.
    pub fn add_tag(&self, uuid: String, tag: String) -> Result<(), VmError> {
        let task_uuid = parse_uuid(&uuid)?;
        let tag_obj = Tag::from_str(&tag)
            .map_err(|e| VmError::Conversion { msg: format!("invalid tag {tag:?}: {e}") })?;
        let mut guard = self
            .replica
            .lock()
            .map_err(|e| VmError::Internal { msg: format!("mutex poisoned: {e}") })?;
        let replica: &mut AppReplica = &mut *guard;

        self.rt.block_on(async {
            let mut ops = Operations::new();
            let mut task = replica
                .get_task(task_uuid)
                .await?
                .ok_or(VmError::NotFound { uuid: uuid.clone() })?;
            if !task.has_tag(&tag_obj) {
                task.add_tag(&tag_obj, &mut ops)?;
                replica.commit_operations(ops).await?;
            }
            Ok::<_, VmError>(())
        })
    }

    /// Entfernt einen User-Tag. No-op, falls der Tag nicht existiert.
    pub fn remove_tag(&self, uuid: String, tag: String) -> Result<(), VmError> {
        let task_uuid = parse_uuid(&uuid)?;
        let tag_obj = Tag::from_str(&tag)
            .map_err(|e| VmError::Conversion { msg: format!("invalid tag {tag:?}: {e}") })?;
        let mut guard = self
            .replica
            .lock()
            .map_err(|e| VmError::Internal { msg: format!("mutex poisoned: {e}") })?;
        let replica: &mut AppReplica = &mut *guard;

        self.rt.block_on(async {
            let mut ops = Operations::new();
            let mut task = replica
                .get_task(task_uuid)
                .await?
                .ok_or(VmError::NotFound { uuid: uuid.clone() })?;
            if task.has_tag(&tag_obj) {
                task.remove_tag(&tag_obj, &mut ops)?;
                replica.commit_operations(ops).await?;
            }
            Ok::<_, VmError>(())
        })
    }

    /// Setzt das `wait`-Property (Unix-Sekunden). `None` entfernt es. Tasks mit
    /// `wait` in der Zukunft gelten als „wartend" (Snooze).
    pub fn set_wait(&self, uuid: String, wait: Option<i64>) -> Result<(), VmError> {
        let task_uuid = parse_uuid(&uuid)?;
        let wait_ts = match wait {
            Some(secs) => Some(timestamp_from_secs(secs)?),
            None => None,
        };
        let mut guard = self
            .replica
            .lock()
            .map_err(|e| VmError::Internal { msg: format!("mutex poisoned: {e}") })?;
        let replica: &mut AppReplica = &mut *guard;

        self.rt.block_on(async {
            let mut ops = Operations::new();
            let mut task = replica
                .get_task(task_uuid)
                .await?
                .ok_or(VmError::NotFound { uuid: uuid.clone() })?;
            task.set_wait(wait_ts, &mut ops)?;
            replica.commit_operations(ops).await?;
            Ok::<_, VmError>(())
        })
    }

    /// Reaktiviert einen Task: Status zurück auf Pending. Aufgerufen z.B., wenn
    /// User einen versehentlich erledigten Task wiederherstellen will.
    pub fn reactivate(&self, uuid: String) -> Result<(), VmError> {
        let task_uuid = parse_uuid(&uuid)?;
        let mut guard = self
            .replica
            .lock()
            .map_err(|e| VmError::Internal { msg: format!("mutex poisoned: {e}") })?;
        let replica: &mut AppReplica = &mut *guard;

        self.rt.block_on(async {
            let mut ops = Operations::new();
            let mut task = replica
                .get_task(task_uuid)
                .await?
                .ok_or(VmError::NotFound { uuid: uuid.clone() })?;
            task.set_status(Status::Pending, &mut ops)?;
            replica.commit_operations(ops).await?;
            Ok::<_, VmError>(())
        })
    }

    /// Synchronisiert die Replica gegen einen TaskChampion-Sync-Server.
    /// `client_id` muss ein UUID-String sein. `encryption_secret` wird als UTF-8-Bytes verwendet.
    pub fn sync(
        &self,
        server_url: String,
        client_id: String,
        encryption_secret: String,
    ) -> Result<(), VmError> {
        let client_uuid = parse_uuid(&client_id)?;
        let mut guard = self
            .replica
            .lock()
            .map_err(|e| VmError::Internal { msg: format!("mutex poisoned: {e}") })?;
        let replica: &mut AppReplica = &mut *guard;

        self.rt.block_on(async {
            let mut server = ServerConfig::Remote {
                url: server_url,
                client_id: client_uuid,
                encryption_secret: encryption_secret.into_bytes(),
            }
            .into_server()
            .await?;
            replica.sync(&mut server, false).await?;
            Ok::<_, taskchampion::Error>(())
        })?;

        Ok(())
    }
}
