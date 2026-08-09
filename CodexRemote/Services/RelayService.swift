import Foundation

@MainActor
protocol RelayServiceProtocol: AnyObject {
    func events() -> AsyncStream<RelayEvent>
    func connect() async
    func configure(url: String, reconnectAutomatically: Bool) async
    func requestProjects() async
    func requestThreads(projectID: String) async
    func startTurn(projectID: String, threadID: String?, prompt: String) async
    func interruptTurn() async
    func loadScenario(_ scenario: DemoScenario) async
}
