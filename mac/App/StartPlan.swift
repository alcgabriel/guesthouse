// SPDX-License-Identifier: GPL-2.0-or-later
import Foundation

/// The programs one start runs.
struct StartPlan {
    let qemu: String
    /// The graphics process, for a machine on the protected path.
    let pvgHost: String?
}

extension Library {
    /// The programs an install is started with: the protected QEMU and graphics process, when
    /// they can be found. The agent has its own for anything left out.
    func startPlan(forInstall: ()) -> (qemu: String?, pvgHost: String?) {
        let setting = Self.qemuSetting
        return (ToolLocation.find(.pvgQemu, setting: setting).path, ToolLocation.find(.pvgHost).path)
    }

    /// What Start would run for `machine`, or the sentence saying what is missing. A machine on
    /// the protected path needs the graphics process (one that can publish the screen) and a
    /// QEMU that has the forwarding device; one on QEMU's own device needs a QEMU. The core
    /// has checked what each program can do before it is named here.
    func startPlan(for machine: Machine) -> (plan: StartPlan?, problem: String?) {
        let setting = Self.qemuSetting
        if machine.graphics == "qemu" {
            switch ToolLocation.find(.qemu, setting: setting) {
            case .found(let path, _, _): return (StartPlan(qemu: path, pvgHost: nil), nil)
            case .missing(let sentence): return (nil, sentence)
            }
        }
        guard case .found(let qemu, _, _) = ToolLocation.find(.pvgQemu, setting: setting) else {
            if case .missing(let sentence) = ToolLocation.find(.pvgQemu, setting: setting) { return (nil, sentence) }
            return (nil, nil)
        }
        switch ToolLocation.find(.pvgHost) {
        case .found(let host, _, _): return (StartPlan(qemu: qemu, pvgHost: host), nil)
        case .missing(let sentence): return (nil, sentence)
        }
    }
}
