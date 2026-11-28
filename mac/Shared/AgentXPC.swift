import Foundation

/// What the app asks of the agent over XPC. A message is one line of the agent's JSON, the same
/// words the Unix socket carries (core/src/protocol.rs).
@objc nonisolated protocol AgentService {
    /// Sends one request line; the reply is the answer line.
    func request(_ line: String, reply: @escaping (String) -> Void)
    /// Asks for state-change lines to be sent to `listener` from now on.
    func subscribe(_ listener: AgentListener)
}

/// What the agent tells the app without being asked.
@objc nonisolated protocol AgentListener {
    func event(_ line: String)
}

/// The mach service the launchd form of the agent answers on, as in its plist.
nonisolated let agentMachService = "com.ruxn.guesthouse.agent"

/// The service's interface for either end of the connection. `subscribe` passes an object, so
/// XPC has to be told that argument is itself a remote object with the listener's interface.
nonisolated func agentServiceInterface() -> NSXPCInterface {
    let interface = NSXPCInterface(with: AgentService.self)
    interface.setInterface(
        NSXPCInterface(with: AgentListener.self),
        for: #selector(AgentService.subscribe(_:)),
        argumentIndex: 0,
        ofReply: false
    )
    return interface
}
