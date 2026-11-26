//! Validate cached translations in memory without modifying the cache or dump.
use std::{fs, path::PathBuf, time::{Duration, Instant}};
use victory_shader::emit::validator::Validator;

fn main() -> Result<(), String> {
    let root = std::env::args_os().nth(1).map(PathBuf::from).ok_or("expected shader cache path")?;
    let dll = std::env::args_os().nth(2).map(PathBuf::from);
    let mut validator = Validator::load(dll.as_deref())?;
    let (mut good, mut bad, mut skipped) = (0usize, 0usize, 0usize);
    let started = Instant::now();
    let mut pending = vec![root];
    while let Some(path) = pending.pop() {
        if started.elapsed() >= Duration::from_secs(110) {
            println!("time limit: valid={good} invalid={bad} skipped={skipped}");
            return Err("audit incomplete".into());
        }
        if path.is_dir() {
            pending.extend(fs::read_dir(&path).map_err(|e| e.to_string())?.filter_map(Result::ok).map(|e| e.path()));
            continue;
        }
        let mut bytes = fs::read(&path).map_err(|e| e.to_string())?;
        if bytes.len() < 12 || &bytes[..4] != b"VSH1" {
            skipped += 1;
            continue;
        }
        let length = u32::from_le_bytes(bytes[8..12].try_into().unwrap()) as usize;
        let Some(dxil) = bytes.get_mut(12..12 + length) else {
            bad += 1;
            continue;
        };
        match validator.validate(dxil) {
            Ok(()) => good += 1,
            Err(error) => {
                bad += 1;
                if bad <= 10 {
                    println!("invalid {}: {}", path.display(), error.chars().take(350).collect::<String>());
                }
            }
        }
    }
    println!("valid={good} invalid={bad} skipped={skipped} seconds={:.2}", started.elapsed().as_secs_f64());
    if bad == 0 { Ok(()) } else { Err("DXIL validation failed".into()) }
}
