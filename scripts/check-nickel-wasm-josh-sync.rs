use std::collections::BTreeMap;
use std::env;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::process::{Command, ExitCode, Stdio};
use std::time::{SystemTime, UNIX_EPOCH};

const DEFAULT_SOURCE_REPO: &str = "../nickel-wasm";
const DEFAULT_VENDOR_DIR: &str = "vendor";
const DEFAULT_LOCK_FILE: &str = "flake.lock";
const DEFAULT_FILTER_FILE: &str = "josh/nickel-wasm.josh";
const NICKEL_WASM_VENDOR_NODE: &str = "\"nickel-wasm-vendor\"";
const LOCKED_KEY: &str = "\"locked\"";
const REV_KEY: &str = "\"rev\"";
const CORE_SOURCE_PATH: &str = "core";
const PARSER_SOURCE_PATH: &str = "parser";
const VECTOR_SOURCE_PATH: &str = "vector";
const CORE_VENDOR_PATH: &str = "nickel-lang-core";
const PARSER_VENDOR_PATH: &str = "nickel-lang-parser";
const VECTOR_VENDOR_PATH: &str = "nickel-lang-vector";
const CARGO_MANIFEST: &str = "Cargo.toml";
const DEV_DEPENDENCIES_HEADER: &str = "[dev-dependencies]";
const CORE_PARSER_SOURCE_PATH: &str = "path = \"../parser\"";
const CORE_PARSER_VENDOR_PATH: &str = "path = \"../nickel-lang-parser\"";
const CORE_VECTOR_SOURCE_PATH: &str = "path = \"../vector\"";
const CORE_VECTOR_VENDOR_PATH: &str = "path = \"../nickel-lang-vector\"";
const REQUIRED_FILTER_FRAGMENTS: &[&str] = &["::core/", "::parser/", "::vector/"];
const SELECTED_SOURCE_PATHS: &[&str] = &[CORE_SOURCE_PATH, PARSER_SOURCE_PATH, VECTOR_SOURCE_PATH];
const CRATE_MAPPINGS: &[CrateMapping] = &[
    CrateMapping {
        source_path: CORE_SOURCE_PATH,
        vendor_path: CORE_VENDOR_PATH,
    },
    CrateMapping {
        source_path: PARSER_SOURCE_PATH,
        vendor_path: PARSER_VENDOR_PATH,
    },
    CrateMapping {
        source_path: VECTOR_SOURCE_PATH,
        vendor_path: VECTOR_VENDOR_PATH,
    },
];

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct CrateMapping {
    source_path: &'static str,
    vendor_path: &'static str,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct Config {
    source_repo: PathBuf,
    vendor_dir: PathBuf,
    lock_file: PathBuf,
    filter_file: PathBuf,
    revision_override: Option<String>,
    config_only: bool,
    refresh: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
enum EntryKind {
    Directory,
    File,
    Symlink,
}

struct TempDir {
    path: PathBuf,
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ignored = fs::remove_dir_all(&self.path);
    }
}

fn main() -> ExitCode {
    match run() {
        Ok(()) => ExitCode::SUCCESS,
        Err(error) => {
            eprintln!("error: {error}");
            ExitCode::FAILURE
        }
    }
}

fn run() -> Result<(), String> {
    let config = parse_args(env::args().skip(1))?;
    validate_filter_file(&config.filter_file)?;
    let locked_revision = read_locked_revision(&config.lock_file)?;
    if config.config_only {
        println!("nickel-wasm Josh filter and locked revision are valid");
        return Ok(());
    }

    let revision = config.revision_override.clone().unwrap_or(locked_revision);
    ensure_git_checkout(&config.source_repo)?;
    ensure_revision_exists(&config.source_repo, &revision)?;

    let temp_dir = create_temp_dir()?;
    let source_dir = temp_dir.path.join("source");
    let expected_dir = temp_dir.path.join("expected-vendor");
    fs::create_dir_all(&source_dir).map_err(|error| {
        format!(
            "failed to create source export directory {}: {error}",
            source_dir.display()
        )
    })?;
    fs::create_dir_all(&expected_dir).map_err(|error| {
        format!(
            "failed to create expected vendor directory {}: {error}",
            expected_dir.display()
        )
    })?;

    export_revision_tree(&config.source_repo, &revision, &source_dir)?;
    transform_source_tree(&source_dir, &expected_dir)?;

    if config.refresh {
        refresh_vendor_tree(&expected_dir, &config.vendor_dir)?;
        println!(
            "refreshed {} from nickel-wasm revision {revision} using Josh filter {}",
            config.vendor_dir.display(),
            config.filter_file.display()
        );
    } else {
        compare_trees(&expected_dir, &config.vendor_dir)?;
        println!(
            "{} matches nickel-wasm revision {revision} using Josh filter {}",
            config.vendor_dir.display(),
            config.filter_file.display()
        );
    }
    Ok(())
}

fn parse_args<I>(args: I) -> Result<Config, String>
where
    I: IntoIterator<Item = String>,
{
    let mut config = Config {
        source_repo: PathBuf::from(DEFAULT_SOURCE_REPO),
        vendor_dir: PathBuf::from(DEFAULT_VENDOR_DIR),
        lock_file: PathBuf::from(DEFAULT_LOCK_FILE),
        filter_file: PathBuf::from(DEFAULT_FILTER_FILE),
        revision_override: None,
        config_only: false,
        refresh: false,
    };

    let mut iter = args.into_iter();
    while let Some(arg) = iter.next() {
        match arg.as_str() {
            "--source-repo" => {
                config.source_repo = PathBuf::from(required_value(&mut iter, "--source-repo")?)
            }
            "--vendor-dir" => {
                config.vendor_dir = PathBuf::from(required_value(&mut iter, "--vendor-dir")?)
            }
            "--lock-file" => {
                config.lock_file = PathBuf::from(required_value(&mut iter, "--lock-file")?)
            }
            "--filter-file" => {
                config.filter_file = PathBuf::from(required_value(&mut iter, "--filter-file")?)
            }
            "--revision" => {
                config.revision_override = Some(required_value(&mut iter, "--revision")?)
            }
            "--config-only" => config.config_only = true,
            "--refresh" => config.refresh = true,
            "--help" | "-h" => return Err(help_text()),
            unknown => return Err(format!("unknown argument {unknown}\n{}", help_text())),
        }
    }

    if config.config_only && config.refresh {
        return Err("--config-only and --refresh cannot be used together".to_owned());
    }

    Ok(config)
}

fn required_value<I>(iter: &mut I, flag: &str) -> Result<String, String>
where
    I: Iterator<Item = String>,
{
    iter.next()
        .filter(|value| !value.is_empty())
        .ok_or_else(|| format!("{flag} requires a value"))
}

fn help_text() -> String {
    format!(
        "usage: check-nickel-wasm-josh-sync [--source-repo PATH] [--vendor-dir PATH] [--lock-file PATH] [--filter-file PATH] [--revision REF] [--config-only] [--refresh]\n\nDefaults: source={DEFAULT_SOURCE_REPO}, vendor={DEFAULT_VENDOR_DIR}, lock-file={DEFAULT_LOCK_FILE}, filter={DEFAULT_FILTER_FILE}"
    )
}

fn validate_filter_file(path: &Path) -> Result<(), String> {
    let text = fs::read_to_string(path)
        .map_err(|error| format!("failed to read Josh filter {}: {error}", path.display()))?;
    let missing = REQUIRED_FILTER_FRAGMENTS
        .iter()
        .copied()
        .filter(|fragment| !text.contains(fragment))
        .collect::<Vec<_>>();
    if missing.is_empty() {
        Ok(())
    } else {
        Err(format!(
            "Josh filter {} is missing required fragments: {}",
            path.display(),
            missing.join(", ")
        ))
    }
}

fn read_locked_revision(path: &Path) -> Result<String, String> {
    let text = fs::read_to_string(path)
        .map_err(|error| format!("failed to read flake lock {}: {error}", path.display()))?;
    parse_locked_revision(&text)
}

fn parse_locked_revision(text: &str) -> Result<String, String> {
    let node_start = text
        .find(NICKEL_WASM_VENDOR_NODE)
        .ok_or_else(|| "flake.lock is missing nickel-wasm-vendor node".to_owned())?;
    let locked_start = find_after(text, node_start, LOCKED_KEY)?;
    let rev_key = find_after(text, locked_start, REV_KEY)?;
    let revision =
        parse_json_string_value(text, rev_key + REV_KEY.len(), "locked nickel-wasm revision")?;
    if revision.trim().is_empty() {
        Err("locked nickel-wasm revision is empty".to_owned())
    } else {
        Ok(revision)
    }
}

fn find_after(text: &str, start: usize, needle: &str) -> Result<usize, String> {
    text[start..]
        .find(needle)
        .map(|relative| start + relative)
        .ok_or_else(|| format!("could not find {needle} after byte offset {start}"))
}

fn parse_json_string_value(text: &str, key_end: usize, label: &str) -> Result<String, String> {
    let suffix = &text[key_end..];
    let colon = suffix
        .find(':')
        .ok_or_else(|| format!("{label} key is missing ':'"))?;
    let after_colon = &suffix[colon + ':'.len_utf8()..];
    let first_quote = after_colon
        .find('"')
        .ok_or_else(|| format!("{label} value is missing opening quote"))?;
    let value_start = colon + ':'.len_utf8() + first_quote + '"'.len_utf8();
    let value_suffix = &suffix[value_start..];
    let value_end = value_suffix
        .find('"')
        .ok_or_else(|| format!("{label} value is missing closing quote"))?;
    Ok(value_suffix[..value_end].to_owned())
}

fn ensure_git_checkout(repo: &Path) -> Result<(), String> {
    let status = Command::new("git")
        .arg("-C")
        .arg(repo)
        .arg("rev-parse")
        .arg("--show-toplevel")
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map_err(|error| format!("failed to invoke git for {}: {error}", repo.display()))?;
    if status.success() {
        Ok(())
    } else {
        Err(format!(
            "source repo {} is not a git checkout",
            repo.display()
        ))
    }
}

fn ensure_revision_exists(repo: &Path, revision: &str) -> Result<(), String> {
    let status = Command::new("git")
        .arg("-C")
        .arg(repo)
        .arg("cat-file")
        .arg("-e")
        .arg(format!("{revision}^{{commit}}"))
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map_err(|error| format!("failed to invoke git for {}: {error}", repo.display()))?;
    if status.success() {
        Ok(())
    } else {
        Err(format!(
            "revision {revision} is not present in source repo {}",
            repo.display()
        ))
    }
}

fn create_temp_dir() -> Result<TempDir, String> {
    let timestamp = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map_err(|error| format!("system clock is before UNIX_EPOCH: {error}"))?
        .as_nanos();
    let path = env::temp_dir().join(format!(
        "onix-wasm-nickel-wasm-josh-sync-{}-{timestamp}",
        std::process::id()
    ));
    fs::create_dir_all(&path).map_err(|error| {
        format!(
            "failed to create temporary directory {}: {error}",
            path.display()
        )
    })?;
    Ok(TempDir { path })
}

fn export_revision_tree(repo: &Path, revision: &str, destination: &Path) -> Result<(), String> {
    for path in SELECTED_SOURCE_PATHS {
        ensure_tree_path_exists(repo, revision, path)?;
    }

    let mut git = Command::new("git")
        .arg("-C")
        .arg(repo)
        .arg("archive")
        .arg("--format=tar")
        .arg(revision)
        .args(SELECTED_SOURCE_PATHS)
        .stdout(Stdio::piped())
        .spawn()
        .map_err(|error| {
            format!(
                "failed to start git archive for {}: {error}",
                repo.display()
            )
        })?;

    let git_stdout = git
        .stdout
        .take()
        .ok_or_else(|| "failed to capture git archive stdout".to_owned())?;

    let mut tar = Command::new("tar")
        .arg("-x")
        .arg("-C")
        .arg(destination)
        .stdin(Stdio::from(git_stdout))
        .spawn()
        .map_err(|error| {
            format!(
                "failed to start tar extraction into {}: {error}",
                destination.display()
            )
        })?;

    let tar_status = tar
        .wait()
        .map_err(|error| format!("failed to wait for tar extraction: {error}"))?;
    let git_status = git
        .wait()
        .map_err(|error| format!("failed to wait for git archive: {error}"))?;

    if !git_status.success() {
        return Err(format!("git archive failed for revision {revision}"));
    }
    if !tar_status.success() {
        return Err(format!("tar extraction failed for revision {revision}"));
    }
    Ok(())
}

fn ensure_tree_path_exists(repo: &Path, revision: &str, path: &str) -> Result<(), String> {
    let status = Command::new("git")
        .arg("-C")
        .arg(repo)
        .arg("cat-file")
        .arg("-e")
        .arg(format!("{revision}:{path}"))
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map_err(|error| format!("failed to inspect {path} in {}: {error}", repo.display()))?;
    if status.success() {
        Ok(())
    } else {
        Err(format!(
            "required path {path} is missing from source repo {} at {revision}",
            repo.display()
        ))
    }
}

fn transform_source_tree(source_root: &Path, expected_vendor_root: &Path) -> Result<(), String> {
    for mapping in CRATE_MAPPINGS {
        copy_tree(
            &source_root.join(mapping.source_path),
            &expected_vendor_root.join(mapping.vendor_path),
        )?;
    }
    transform_vendor_manifests(expected_vendor_root)
}

fn transform_vendor_manifests(expected_vendor_root: &Path) -> Result<(), String> {
    let core_manifest = expected_vendor_root
        .join(CORE_VENDOR_PATH)
        .join(CARGO_MANIFEST);
    let parser_manifest = expected_vendor_root
        .join(PARSER_VENDOR_PATH)
        .join(CARGO_MANIFEST);

    let core_text = fs::read_to_string(&core_manifest)
        .map_err(|error| format!("failed to read {}: {error}", core_manifest.display()))?;
    let core_text = transform_core_manifest(&core_text)?;
    fs::write(&core_manifest, core_text)
        .map_err(|error| format!("failed to write {}: {error}", core_manifest.display()))?;

    let parser_text = fs::read_to_string(&parser_manifest)
        .map_err(|error| format!("failed to read {}: {error}", parser_manifest.display()))?;
    let parser_text = transform_parser_manifest(&parser_text)?;
    fs::write(&parser_manifest, parser_text)
        .map_err(|error| format!("failed to write {}: {error}", parser_manifest.display()))?;

    Ok(())
}

fn transform_core_manifest(text: &str) -> Result<String, String> {
    let text = replace_required(text, CORE_PARSER_SOURCE_PATH, CORE_PARSER_VENDOR_PATH)?;
    let text = replace_required(&text, CORE_VECTOR_SOURCE_PATH, CORE_VECTOR_VENDOR_PATH)?;
    Ok(strip_toml_section(&text, DEV_DEPENDENCIES_HEADER))
}

fn transform_parser_manifest(text: &str) -> Result<String, String> {
    replace_required(text, CORE_VECTOR_SOURCE_PATH, CORE_VECTOR_VENDOR_PATH)
}

fn replace_required(text: &str, from: &str, to: &str) -> Result<String, String> {
    if text.contains(from) {
        Ok(text.replace(from, to))
    } else {
        Err(format!("required manifest fragment missing: {from}"))
    }
}

fn strip_toml_section(text: &str, header: &str) -> String {
    let mut output = String::new();
    let mut skipping = false;
    for segment in text.split_inclusive('\n') {
        let line = segment.trim_end_matches('\n').trim_end_matches('\r');
        let trimmed = line.trim();
        if trimmed == header {
            skipping = true;
            continue;
        }
        if skipping && trimmed.starts_with('[') {
            skipping = false;
        }
        if !skipping {
            output.push_str(segment);
        }
    }
    output
}

fn copy_tree(source: &Path, destination: &Path) -> Result<(), String> {
    let metadata = fs::symlink_metadata(source)
        .map_err(|error| format!("failed to inspect {}: {error}", source.display()))?;
    let file_type = metadata.file_type();
    if file_type.is_dir() {
        fs::create_dir_all(destination)
            .map_err(|error| format!("failed to create {}: {error}", destination.display()))?;
        let mut children = fs::read_dir(source)
            .map_err(|error| format!("failed to read directory {}: {error}", source.display()))?
            .collect::<Result<Vec<_>, io::Error>>()
            .map_err(|error| {
                format!(
                    "failed to collect directory entries from {}: {error}",
                    source.display()
                )
            })?;
        children.sort_by_key(|entry| entry.path());
        for child in children {
            copy_tree(&child.path(), &destination.join(child.file_name()))?;
        }
    } else if file_type.is_file() {
        if let Some(parent) = destination.parent() {
            fs::create_dir_all(parent)
                .map_err(|error| format!("failed to create {}: {error}", parent.display()))?;
        }
        fs::copy(source, destination).map_err(|error| {
            format!(
                "failed to copy {} to {}: {error}",
                source.display(),
                destination.display()
            )
        })?;
    } else if file_type.is_symlink() {
        copy_symlink(source, destination)?;
    } else {
        return Err(format!("unsupported file type at {}", source.display()));
    }
    Ok(())
}

#[cfg(unix)]
fn copy_symlink(source: &Path, destination: &Path) -> Result<(), String> {
    let target = fs::read_link(source)
        .map_err(|error| format!("failed to read symlink {}: {error}", source.display()))?;
    if let Some(parent) = destination.parent() {
        fs::create_dir_all(parent)
            .map_err(|error| format!("failed to create {}: {error}", parent.display()))?;
    }
    std::os::unix::fs::symlink(&target, destination).map_err(|error| {
        format!(
            "failed to create symlink {} -> {}: {error}",
            destination.display(),
            target.display()
        )
    })
}

#[cfg(not(unix))]
fn copy_symlink(_source: &Path, _destination: &Path) -> Result<(), String> {
    Err("symlink copying currently requires Unix".to_owned())
}

fn refresh_vendor_tree(expected_vendor_root: &Path, vendor_dir: &Path) -> Result<(), String> {
    fs::create_dir_all(vendor_dir).map_err(|error| {
        format!(
            "failed to create vendor dir {}: {error}",
            vendor_dir.display()
        )
    })?;
    for mapping in CRATE_MAPPINGS {
        let destination = vendor_dir.join(mapping.vendor_path);
        if destination.exists() {
            fs::remove_dir_all(&destination)
                .map_err(|error| format!("failed to remove {}: {error}", destination.display()))?;
        }
        copy_tree(
            &expected_vendor_root.join(mapping.vendor_path),
            &destination,
        )?;
    }
    Ok(())
}

fn compare_trees(expected: &Path, actual: &Path) -> Result<(), String> {
    let expected_entries = collect_entries(expected)?;
    let actual_entries = collect_entries(actual)?;
    let mut differences = Vec::new();

    for (relative, expected_kind) in &expected_entries {
        match actual_entries.get(relative) {
            Some(actual_kind) if actual_kind == expected_kind => {
                compare_entry_contents(
                    expected,
                    actual,
                    relative,
                    expected_kind,
                    &mut differences,
                )?;
            }
            Some(actual_kind) => differences.push(format!(
                "kind mismatch for {}: expected {:?}, got {:?}",
                relative.display(),
                expected_kind,
                actual_kind
            )),
            None => differences.push(format!("missing vendored path {}", relative.display())),
        }
    }

    for relative in actual_entries.keys() {
        if !expected_entries.contains_key(relative) {
            differences.push(format!("extra vendored path {}", relative.display()));
        }
    }

    if differences.is_empty() {
        Ok(())
    } else {
        Err(format!(
            "vendored Nickel tree differs from filtered source:\n{}",
            differences.join("\n")
        ))
    }
}

fn collect_entries(root: &Path) -> Result<BTreeMap<PathBuf, EntryKind>, String> {
    let mut entries = BTreeMap::new();
    collect_entries_from(root, root, &mut entries)?;
    Ok(entries)
}

fn collect_entries_from(
    root: &Path,
    current: &Path,
    entries: &mut BTreeMap<PathBuf, EntryKind>,
) -> Result<(), String> {
    let mut children = fs::read_dir(current)
        .map_err(|error| format!("failed to read directory {}: {error}", current.display()))?
        .collect::<Result<Vec<_>, io::Error>>()
        .map_err(|error| {
            format!(
                "failed to collect directory entries from {}: {error}",
                current.display()
            )
        })?;
    children.sort_by_key(|entry| entry.path());

    for child in children {
        let path = child.path();
        let metadata = fs::symlink_metadata(&path)
            .map_err(|error| format!("failed to inspect {}: {error}", path.display()))?;
        let relative = path
            .strip_prefix(root)
            .map_err(|error| format!("failed to relativize {}: {error}", path.display()))?
            .to_path_buf();
        let file_type = metadata.file_type();
        if file_type.is_dir() {
            entries.insert(relative, EntryKind::Directory);
            collect_entries_from(root, &path, entries)?;
        } else if file_type.is_file() {
            entries.insert(relative, EntryKind::File);
        } else if file_type.is_symlink() {
            entries.insert(relative, EntryKind::Symlink);
        } else {
            return Err(format!("unsupported file type at {}", path.display()));
        }
    }
    Ok(())
}

fn compare_entry_contents(
    expected_root: &Path,
    actual_root: &Path,
    relative: &Path,
    kind: &EntryKind,
    differences: &mut Vec<String>,
) -> Result<(), String> {
    match kind {
        EntryKind::Directory => Ok(()),
        EntryKind::File => {
            let expected_path = expected_root.join(relative);
            let actual_path = actual_root.join(relative);
            let expected = fs::read(&expected_path)
                .map_err(|error| format!("failed to read {}: {error}", expected_path.display()))?;
            let actual = fs::read(&actual_path)
                .map_err(|error| format!("failed to read {}: {error}", actual_path.display()))?;
            if expected != actual {
                differences.push(format!("content mismatch for {}", relative.display()));
            }
            Ok(())
        }
        EntryKind::Symlink => {
            let expected_path = expected_root.join(relative);
            let actual_path = actual_root.join(relative);
            let expected = fs::read_link(&expected_path).map_err(|error| {
                format!(
                    "failed to read symlink {}: {error}",
                    expected_path.display()
                )
            })?;
            let actual = fs::read_link(&actual_path).map_err(|error| {
                format!("failed to read symlink {}: {error}", actual_path.display())
            })?;
            if expected != actual {
                differences.push(format!(
                    "symlink mismatch for {}: expected {}, got {}",
                    relative.display(),
                    expected.display(),
                    actual.display()
                ));
            }
            Ok(())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const SAMPLE_REVISION: &str = "472dfa6b027f2b27e8e9ab83406d4fde14c77c76";
    const SAMPLE_LOCK: &str = r#"{
  "nodes": {
    "nickel-wasm-vendor": {
      "flake": false,
      "locked": {
        "rev": "472dfa6b027f2b27e8e9ab83406d4fde14c77c76",
        "type": "github"
      },
      "original": {
        "ref": "wasm-vendor"
      }
    }
  }
}
"#;

    #[test]
    fn parses_locked_revision() {
        let revision = parse_locked_revision(SAMPLE_LOCK).expect("revision should parse");

        assert_eq!(revision, SAMPLE_REVISION);
    }

    #[test]
    fn rejects_lock_without_vendor_node() {
        let error = parse_locked_revision("{}").expect_err("missing node should fail");

        assert!(
            error.contains("missing nickel-wasm-vendor"),
            "unexpected error: {error}"
        );
    }

    #[test]
    fn transforms_core_manifest_paths_and_strips_dev_dependencies() {
        let source = "[dependencies]\nnickel-lang-parser = { path = \"../parser\" }\nnickel-lang-vector = { path = \"../vector\" }\n\n[dev-dependencies]\nnickel-lang-utils = { path = \"../utils\" }\n\n[lints.clippy]\nnew_without_default = \"allow\"\n";

        let transformed = transform_core_manifest(source).expect("core manifest should transform");

        assert!(transformed.contains(CORE_PARSER_VENDOR_PATH));
        assert!(transformed.contains(CORE_VECTOR_VENDOR_PATH));
        assert!(!transformed.contains(DEV_DEPENDENCIES_HEADER));
        assert!(!transformed.contains("nickel-lang-utils"));
        assert!(transformed.contains("[lints.clippy]"));
    }

    #[test]
    fn rejects_manifest_missing_required_path_fragment() {
        let error = transform_parser_manifest("[dependencies]\n")
            .expect_err("missing vector path should fail");

        assert!(
            error.contains("required manifest fragment missing"),
            "unexpected error: {error}"
        );
    }

    #[test]
    fn parses_custom_arguments() {
        let args = [
            "--source-repo",
            "../nickel-wasm",
            "--vendor-dir",
            "vendor",
            "--lock-file",
            "flake.lock",
            "--filter-file",
            "josh/nickel-wasm.josh",
            "--revision",
            SAMPLE_REVISION,
            "--refresh",
        ];

        let config =
            parse_args(args.iter().map(|arg| (*arg).to_owned())).expect("args should parse");

        assert_eq!(config.source_repo, PathBuf::from("../nickel-wasm"));
        assert_eq!(config.vendor_dir, PathBuf::from("vendor"));
        assert_eq!(config.lock_file, PathBuf::from("flake.lock"));
        assert_eq!(config.filter_file, PathBuf::from("josh/nickel-wasm.josh"));
        assert_eq!(config.revision_override.as_deref(), Some(SAMPLE_REVISION));
        assert!(config.refresh);
        assert!(!config.config_only);
    }

    #[test]
    fn rejects_config_only_refresh_combination() {
        let args = ["--config-only", "--refresh"];

        let error = parse_args(args.iter().map(|arg| (*arg).to_owned()))
            .expect_err("mode conflict should fail");

        assert!(
            error.contains("cannot be used together"),
            "unexpected error: {error}"
        );
    }
}
