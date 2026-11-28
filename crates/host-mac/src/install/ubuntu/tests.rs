use super::*;

const SUMS: &str = "\
c2afd538d66fdd77377d03f1ed2ac76a34f1c116baecc9a8170d68f833121f57 *ubuntu-26.04-desktop-arm64.iso
d31e9b3d01ac0fa8e488d4f8d5a7acfeee869f387674eaedf94335e174155901 *ubuntu-26.04-live-server-arm64+largemem.iso
c9aa567e6560b2eddae3af03fc686002e35b6fee96f97fd5df3271e846439fdd *ubuntu-26.04-live-server-arm64.iso
0e9f326f55dcc4244f15336ca1221e6d2f36722a4954fc544570da0a12067c3e *ubuntu-26.04-live-server-ppc64el.iso
";

#[test]
fn the_image_is_the_plain_arm64_server_disc_with_its_published_checksum() {
    let image = pick_image(SUMS).unwrap();
    assert_eq!(image.name, "ubuntu-26.04-live-server-arm64.iso");
    assert_eq!(
        image.sha256,
        "c9aa567e6560b2eddae3af03fc686002e35b6fee96f97fd5df3271e846439fdd"
    );
    assert_eq!(
        image.url,
        "https://cdimage.ubuntu.com/ubuntu/releases/26.04/release/ubuntu-26.04-live-server-arm64.iso"
    );
}

#[test]
fn a_list_with_no_such_image_or_a_bad_checksum_is_said_not_guessed() {
    assert!(
        pick_image("")
            .unwrap_err()
            .contains("no arm64 server image")
    );
    assert!(
        pick_image("abc *ubuntu-26.04-live-server-arm64.iso")
            .unwrap_err()
            .contains("not a SHA-256")
    );
    // The text form of a line, with two spaces, reads too.
    let text = format!("{}  ubuntu-26.04-live-server-arm64.iso", "a".repeat(64));
    assert_eq!(pick_image(&text).unwrap().sha256, "a".repeat(64));
}

#[test]
fn the_answers_install_with_no_questions_and_say_how_it_ended_on_the_serial_port() {
    let text = user_data("nick", "k7mn-p3xq-ab9d-w4ht", "guesthouse");
    assert!(text.starts_with("#cloud-config\nautoinstall:"));
    assert!(text.contains("username: nick"));
    assert!(text.contains("chpasswd") && text.contains("nick:k7mn-p3xq-ab9d-w4ht"));
    assert!(!text.contains("passwd -d"));
    assert!(text.contains(FINISHED) && text.contains(FAILED));
    assert!(text.contains("shutdown: poweroff"));
    assert!(text.contains("size: largest"));
}

#[test]
fn the_seed_names_the_instance() {
    assert_eq!(
        meta_data("ubuntu"),
        "instance-id: guesthouse-ubuntu\nlocal-hostname: ubuntu\n"
    );
}

#[test]
fn the_driver_step_says_plainly_what_is_missing() {
    assert!(DRIVER_PLACEHOLDER.contains("not packaged yet"));
}

fn line(sum: char, name: &str) -> String {
    format!("{} *{name}\n", sum.to_string().repeat(64))
}

#[test]
fn the_newest_point_release_in_the_list_is_the_one_taken() {
    // As the folder lists it: the release and its point releases together, other images and
    // architectures among them, the first point release's lines after the release's own.
    let mut sums = String::new();
    sums += &line('a', "ubuntu-26.04-live-server-arm64.iso");
    sums += &line('b', "ubuntu-26.04-live-server-arm64+largemem.iso");
    sums += &line('c', "ubuntu-26.04.1-live-server-arm64+largemem.iso");
    sums += &line('d', "ubuntu-26.04.1-live-server-arm64.iso");
    sums += &line('e', "ubuntu-26.04.1-live-server-s390x.iso");
    sums += &line('f', "ubuntu-26.04.1-desktop-arm64.iso");
    let image = pick_image(&sums).unwrap();
    assert_eq!(image.name, "ubuntu-26.04.1-live-server-arm64.iso");
    assert_eq!(image.sha256, "d".repeat(64));
    assert!(
        image
            .url
            .ends_with("/release/ubuntu-26.04.1-live-server-arm64.iso")
    );
}

#[test]
fn a_point_release_after_that_is_taken_too_and_the_order_in_the_list_does_not_matter() {
    let mut sums = String::new();
    sums += &line('2', "ubuntu-26.04.2-live-server-arm64.iso");
    sums += &line('1', "ubuntu-26.04.1-live-server-arm64.iso");
    sums += &line('0', "ubuntu-26.04-live-server-arm64.iso");
    sums += &line('9', "ubuntu-26.04.10-live-server-arm64.iso");
    assert_eq!(
        pick_image(&sums).unwrap().name,
        "ubuntu-26.04.10-live-server-arm64.iso",
        "by number, not by text"
    );
    let without_ten: String = sums
        .lines()
        .filter(|l| !l.contains(".10-"))
        .map(|l| format!("{l}\n"))
        .collect();
    assert_eq!(
        pick_image(&without_ten).unwrap().name,
        "ubuntu-26.04.2-live-server-arm64.iso"
    );
}

#[test]
fn a_list_of_only_the_release_with_no_point_release_still_gives_the_release() {
    assert_eq!(
        pick_image(&line('a', "ubuntu-26.04-live-server-arm64.iso"))
            .unwrap()
            .name,
        "ubuntu-26.04-live-server-arm64.iso"
    );
}

#[test]
fn names_that_only_look_alike_are_left_out() {
    for name in [
        "ubuntu-26.04.-live-server-arm64.iso",
        "ubuntu-26.04.x-live-server-arm64.iso",
        "ubuntu-26.04.1.2-live-server-arm64.iso",
        "ubuntu-26.045-live-server-arm64.iso",
        "ubuntu-26.04.1-live-server-arm64.iso.zsync",
    ] {
        assert!(pick_image(&line('a', name)).is_err(), "{name}");
    }
}
