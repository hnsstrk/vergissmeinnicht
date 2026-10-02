// Seed a TaskChampion replica with a deterministic demo dataset for screenshots
// and manual testing. Usage:
//
//     cargo run --release --example seed_demo -- <replica-path>
//
// The replica directory will be created if it does not exist. Existing tasks
// are not deleted; run against an empty directory for a clean dataset.

use std::env;
use std::process;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use taskchampion::{storage::AccessMode, Operations, Replica, SqliteStorage};
use uuid::Uuid;
use vergissmeinnicht_core::TaskStore;

struct Demo {
    description: &'static str,
    project: Option<&'static str>,
    tags: &'static [&'static str],
    due_offset_days: Option<i64>,
    priority: Option<&'static str>,
    annotation: Option<&'static str>,
}

const DEMO_TASKS: &[Demo] = &[
    Demo {
        description: "Pay car insurance invoice",
        project: Some("finance"),
        tags: &["urgent"],
        due_offset_days: Some(-2),
        priority: Some("H"),
        annotation: Some("Invoice #4711 is in the inbox."),
    },
    Demo {
        description: "Weekly meal prep",
        project: Some("household"),
        tags: &["routine"],
        due_offset_days: Some(0),
        priority: None,
        annotation: None,
    },
    Demo {
        description: "Review pull request: sync retries",
        project: Some("vergissmeinnicht"),
        tags: &["code", "review"],
        due_offset_days: Some(1),
        priority: Some("M"),
        annotation: None,
    },
    Demo {
        description: "5k run in the park",
        project: Some("health"),
        tags: &["sport"],
        due_offset_days: Some(0),
        priority: None,
        annotation: None,
    },
    Demo {
        description: "Book dentist appointment",
        project: Some("admin"),
        tags: &["phone"],
        due_offset_days: Some(14),
        priority: Some("M"),
        annotation: None,
    },
    Demo {
        description: "Plan weekend trip with Anna",
        project: Some("family"),
        tags: &[],
        due_offset_days: Some(7),
        priority: None,
        annotation: None,
    },
    Demo {
        description: "Read \"Designing Data-Intensive Applications\"",
        project: Some("learning"),
        tags: &["reading"],
        due_offset_days: None,
        priority: None,
        annotation: None,
    },
    Demo {
        description: "Prepare board game night",
        project: Some("leisure"),
        tags: &["friends"],
        due_offset_days: Some(3),
        priority: None,
        annotation: None,
    },
    Demo {
        description: "Declutter the basement",
        project: Some("household"),
        tags: &["project"],
        due_offset_days: None,
        priority: Some("L"),
        annotation: None,
    },
    Demo {
        description: "Replace smoke detector batteries",
        project: Some("household"),
        tags: &["maintenance"],
        due_offset_days: Some(10),
        priority: None,
        annotation: None,
    },
    Demo {
        description: "Draft App Store release notes",
        project: Some("vergissmeinnicht"),
        tags: &["release"],
        due_offset_days: Some(21),
        priority: Some("M"),
        annotation: None,
    },
    Demo {
        description: "Call grandma about Sunday lunch",
        project: Some("family"),
        tags: &[],
        due_offset_days: Some(2),
        priority: None,
        annotation: None,
    },
];

/// Dependency demo: (key, description, project, tags, due offset in days, priority).
type DepTask = (
    &'static str,
    &'static str,
    &'static str,
    &'static [&'static str],
    Option<i64>,
    Option<&'static str>,
);

const DEP_TASKS: &[DepTask] = &[
    ("launch", "Launch personal website", "website", &["milestone"], Some(12), Some("H")),
    ("about", "Write about page", "website", &["writing"], Some(8), Some("M")),
    ("hosting", "Set up hosting", "website", &["devops"], Some(10), None),
    ("domain", "Register domain", "website", &["admin"], None, Some("M")),
    ("design", "Choose a colour palette", "website", &["design"], None, Some("L")),
    ("header", "Design header banner", "website", &["design"], Some(6), None),
    ("footer", "Design footer layout", "website", &[], None, None),
];

/// (task, depends on) — "launch" waits for "about" and "hosting"; "hosting" waits for
/// "domain" (chain, completed below); "header" and "footer" both wait for "design" (diamond).
const DEPENDENCIES: &[(&str, &str)] = &[
    ("launch", "about"),
    ("launch", "hosting"),
    ("hosting", "domain"),
    ("header", "design"),
    ("footer", "design"),
    ("launch", "header"),
];

/// Task started by `start_task` (shows the "active" urgency term).
const ACTIVE_KEY: &str = "about";

/// `start` has no FFI method; set it by reopening the replica directly after the store
/// is dropped.
fn start_task(path: &str, uuid: &str) -> Result<(), Box<dyn std::error::Error>> {
    let rt = tokio::runtime::Builder::new_current_thread().enable_all().build()?;
    rt.block_on(async {
        let storage =
            SqliteStorage::new(std::path::PathBuf::from(path), AccessMode::ReadWrite, true).await?;
        let mut replica = Replica::new(storage);
        let mut ops = Operations::new();
        let mut task = replica
            .get_task(Uuid::parse_str(uuid)?)
            .await?
            .ok_or("task not found")?;
        task.start(&mut ops)?;
        replica.commit_operations(ops).await?;
        Ok(())
    })
}

fn main() {
    let path = match env::args().nth(1) {
        Some(p) => p,
        None => {
            eprintln!("usage: cargo run --release --example seed_demo -- <replica-path>");
            process::exit(2);
        }
    };

    let store = match TaskStore::new(path.clone()) {
        Ok(s) => s,
        Err(e) => {
            eprintln!("failed to open replica at {path}: {e:?}");
            process::exit(1);
        }
    };

    let now = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs() as i64;
    let day = Duration::from_secs(60 * 60 * 24).as_secs() as i64;

    let mut created = 0usize;
    for demo in DEMO_TASKS {
        let due = demo.due_offset_days.map(|d| now + d * day);
        let tags: Vec<String> = demo.tags.iter().map(|s| s.to_string()).collect();
        let project = demo.project.map(|s| s.to_string());

        let uuid = match store.add_task_full(demo.description.to_string(), project, tags, due) {
            Ok(u) => u,
            Err(e) => {
                eprintln!("add_task_full failed for {:?}: {e:?}", demo.description);
                continue;
            }
        };

        if let Some(prio) = demo.priority {
            if let Err(e) = store.set_priority(uuid.clone(), Some(prio.to_string())) {
                eprintln!("set_priority failed for {uuid}: {e:?}");
            }
        }
        if let Some(note) = demo.annotation {
            if let Err(e) = store.add_annotation(uuid.clone(), note.to_string()) {
                eprintln!("add_annotation failed for {uuid}: {e:?}");
            }
        }

        created += 1;
    }

    // Dependency subset: tree view with chain (depth 2), diamond, completed dependency
    // and one active task.
    let mut keys: Vec<(&str, String)> = Vec::new();
    for (key, description, project, tags, due_days, prio) in DEP_TASKS {
        let due = due_days.map(|d| now + d * day);
        let tags: Vec<String> = tags.iter().map(|s| s.to_string()).collect();
        match store.add_task_full(description.to_string(), Some(project.to_string()), tags, due) {
            Ok(uuid) => {
                if let Some(p) = prio {
                    if let Err(e) = store.set_priority(uuid.clone(), Some(p.to_string())) {
                        eprintln!("set_priority failed for {uuid}: {e:?}");
                    }
                }
                keys.push((key, uuid));
                created += 1;
            }
            Err(e) => eprintln!("add_task_full failed for {description:?}: {e:?}"),
        }
    }
    let lookup = |key: &str| keys.iter().find(|(k, _)| *k == key).map(|(_, u)| u.clone());
    for (task, dep) in DEPENDENCIES {
        if let (Some(t), Some(d)) = (lookup(task), lookup(dep)) {
            if let Err(e) = store.add_dependency(t, d) {
                eprintln!("add_dependency {task} -> {dep} failed: {e:?}");
            }
        }
    }
    if let Some(domain) = lookup("domain") {
        if let Err(e) = store.mark_done(domain) {
            eprintln!("mark_done failed for domain: {e:?}");
        }
    }

    println!("seeded {created} demo tasks at {path}");

    if let Some(uuid) = lookup(ACTIVE_KEY) {
        drop(store);
        if let Err(e) = start_task(&path, &uuid) {
            eprintln!("start failed for {ACTIVE_KEY}: {e}");
        }
    }
}
