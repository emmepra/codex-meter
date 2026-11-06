import Foundation
import Darwin

extension Process {
    func finishMeterRead() {
        // EOF normally closes the CLI immediately; bounded fallbacks prevent orphan processes.
        let gracefulDeadline = ProcessInfo.processInfo.systemUptime + 0.3
        while self.isRunning && ProcessInfo.processInfo.systemUptime < gracefulDeadline { usleep(10_000) }
        if self.isRunning {
            self.terminate()
            let terminateDeadline = ProcessInfo.processInfo.systemUptime + 0.3
            while self.isRunning && ProcessInfo.processInfo.systemUptime < terminateDeadline { usleep(10_000) }
        }
        if self.isRunning { kill(self.processIdentifier, SIGKILL) }
        self.waitUntilExit()
    }
}
