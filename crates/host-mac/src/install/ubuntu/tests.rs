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
        "https://cdimage.ubuntu.com/releases/26.04/release/ubuntu-26.04-live-server-arm64.iso"
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
    let text = user_data("nick", "guesthouse");
    assert!(text.starts_with("#cloud-config\nautoinstall:"));
    assert!(text.contains("username: nick"));
    // The password comes from the account file on the disc, so no command the installer prints
    // and no log it keeps holds it.
    assert!(text.contains("chpasswd") && text.contains(ACCOUNT_FILE));
    assert_eq!(
        account_file("nick", "k7mn-p3xq-ab9d-w4ht"),
        "nick:k7mn-p3xq-ab9d-w4ht\n"
    );
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

#[test]
fn the_installer_runs_with_no_questions_and_its_console_on_the_screen() {
    assert!(INSTALLER_COMMAND_LINE.starts_with("autoinstall ds=nocloud "));
    let (installer, installed) = INSTALLER_COMMAND_LINE.split_once(" --- ").unwrap();
    assert!(!installer.contains("ttyAMA0"));
    assert!(installed.contains("console=ttyAMA0,115200"));
}

#[test]
fn the_answers_put_the_drivers_service_into_the_installed_system_before_saying_finished() {
    let text = user_data("nick", "guesthouse");
    let enable = text
        .find(&format!("systemctl enable {DRIVER_SERVICE_FILE}"))
        .unwrap();
    assert!(text.contains("mount -o ro LABEL=CIDATA"));
    assert!(text.contains("/target/usr/local/sbin/guesthouse-driver"));
    assert!(enable < text.find(&format!("echo {FINISHED}")).unwrap());
}

#[test]
fn the_drivers_service_runs_install_sh_from_the_ruxn_disk_once_a_version() {
    assert!(DRIVER_SERVICE.contains("ExecStart=/bin/sh /usr/local/sbin/guesthouse-driver"));
    assert!(DRIVER_SERVICE.contains("WantedBy=multi-user.target"));
    assert!(DRIVER_RUNNER.contains("/dev/disk/by-label/RUXN"));
    assert!(DRIVER_RUNNER.contains("sh ./install.sh"));
    assert!(DRIVER_RUNNER.contains(crate::install::driver::LINUX.manifest));
    assert!(DRIVER_RUNNER.contains("driver-version"));
    // Worked: into the desktop; failed: off, so Try Again is a start of its own.
    assert!(DRIVER_RUNNER.contains("systemctl --no-block reboot"));
    assert!(DRIVER_RUNNER.contains("systemctl --no-block poweroff"));
    assert!(DRIVER_RUNNER.contains(&format!("{} exit-", "driver failed")));
}
