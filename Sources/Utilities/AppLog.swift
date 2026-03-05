import Foundation
import os

enum AppLog {
    private static let logger = Logger(
        subsystem: "com.bioself.somatiq",
        category: "app"
    )

    static func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    static func error(_ context: String, error: Error) {
        let nsError = error as NSError
        logger.error(
            "\(context, privacy: .public) | domain=\(nsError.domain, privacy: .public) code=\(nsError.code) message=\(nsError.localizedDescription, privacy: .public)"
        )
    }
}
