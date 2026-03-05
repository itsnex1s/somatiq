import Foundation

enum AppErrorMapper {
    static func userMessage(
        for error: Error,
        fallback: String = "Something went wrong. Please try again."
    ) -> String {
        if let healthError = error as? HealthKitError {
            switch healthError {
            case .unavailable:
                return "Apple Health is unavailable on this device."
            case .unauthorized:
                return "Apple Health access is not authorized. Update permissions in Settings."
            case .noData:
                return "No health data found yet."
            case .queryFailure:
                return "Apple Health query failed. Please try again."
            }
        }

        if error is CancellationError {
            return "Operation was cancelled."
        }

        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription,
           !description.isEmpty {
            return description
        }

        let nsError = error as NSError
        if nsError.domain == NSCocoaErrorDomain {
            return "Local data access failed. Please retry."
        }

        return fallback
    }
}
