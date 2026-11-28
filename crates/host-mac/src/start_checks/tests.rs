use super::*;

fn run(request: Value) -> Value {
    serde_json::from_str(&answer(&request.to_string())).unwrap()
}

#[test]
fn memory_names_the_machine_that_runs_and_says_what_to_do() {
    let said = run(
        json!({"check": "memory", "machine": "Ubuntu", "wanted_mb": 4096, "host_mb": 16384,
        "running": [{"name": "Windows 11", "memory_mb": 12288}]}),
    );
    let problem = &said["problem"];
    assert_eq!(problem["title"], "Not enough memory to start Ubuntu");
    assert!(
        problem["message"]
            .as_str()
            .unwrap()
            .contains("because Windows 11 is running with 12 GB")
    );
    assert_eq!(problem["running"], "Windows 11");
    assert_eq!(problem["start_anyway"], false);
}

#[test]
fn nothing_is_said_when_there_is_room_or_nothing_else_runs() {
    assert_eq!(
        run(json!({"check": "memory", "machine": "U", "wanted_mb": 4096, "host_mb": 16384}))["problem"],
        Value::Null
    );
    let roomy = json!({"check": "memory", "machine": "U", "wanted_mb": 4096, "host_mb": 32768,
        "running": [{"name": "W", "memory_mb": 6144}]});
    assert_eq!(run(roomy)["problem"], Value::Null);
}

#[test]
fn two_machines_running_are_not_named_one_by_one() {
    let said = run(
        json!({"check": "memory", "machine": "U", "wanted_mb": 8192, "host_mb": 16384,
        "running": [{"name": "A", "memory_mb": 4096}, {"name": "B", "memory_mb": 4096}]}),
    );
    assert_eq!(said["problem"]["running"], Value::Null);
    assert_eq!(said["problem"]["running_mb"], 8192);
}

#[test]
fn memory_free_now_is_compared_and_offers_to_start_anyway() {
    let tight = run(
        json!({"check": "memory_now", "machine": "W", "wanted_mb": 6144, "available_mb": 4000}),
    );
    assert_eq!(tight["problem"]["spare_mb"], 4000 - HEADROOM_MB);
    assert_eq!(tight["problem"]["start_anyway"], true);
    assert_eq!(
        run(
            json!({"check": "memory_now", "machine": "W", "wanted_mb": 6144, "available_mb": 9000})
        )["problem"],
        Value::Null
    );
    assert_eq!(
        run(
            json!({"check": "memory_now", "machine": "W", "wanted_mb": 6144, "available_mb": null})
        )["problem"],
        Value::Null,
        "unknown says nothing"
    );
}

#[test]
fn the_disk_can_grow_to_its_whole_size_and_needs_that_much_room() {
    let gb = 1_000_000_000i64;
    let lack = run(
        json!({"check": "disk", "machine": "W", "size_bytes": 64 * gb, "on_disk_bytes": 20 * gb, "free_bytes": 30 * gb}),
    );
    assert_eq!(lack["problem"]["needed_gb"], 46);
    assert_eq!(lack["problem"]["free_gb"], 30);
    assert!(
        lack["problem"]["message"]
            .as_str()
            .unwrap()
            .contains("can grow by up to 46 GB and this Mac has 30 GB free")
    );
    let roomy = run(
        json!({"check": "disk", "machine": "W", "size_bytes": 64 * gb, "on_disk_bytes": 20 * gb, "free_bytes": 100 * gb}),
    );
    assert_eq!(roomy["problem"], Value::Null);
}

#[test]
fn creating_a_machine_next_to_one_that_runs_gets_the_warning_only_when_tight() {
    assert_eq!(
        run(json!({"check": "advice", "new_mb": 6144, "running_mb": 0, "host_mb": 16384}))["warning"],
        Value::Null
    );
    assert_eq!(
        run(json!({"check": "advice", "new_mb": 2048, "running_mb": 2048, "host_mb": 16384}))["warning"],
        Value::Null
    );
    let said =
        run(json!({"check": "advice", "new_mb": 6144, "running_mb": 6144, "host_mb": 16384}));
    let warning = said["warning"].as_str().unwrap();
    assert!(warning.contains("Another machine is running with 6 GB"));
    assert!(warning.contains("would leave this Mac 4 GB"));
}

#[test]
fn memory_is_said_in_whole_gigabytes_or_one_decimal() {
    assert_eq!(memory_words(6144), "6 GB");
    assert_eq!(memory_words(2976), "2.9 GB");
    assert_eq!(memory_words(0), "0 GB");
}

#[test]
fn a_request_that_is_not_a_check_is_an_error_not_a_guess() {
    assert!(run(json!({"check": "nothing"}))["error"].is_string());
}
