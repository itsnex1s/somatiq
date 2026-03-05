import Foundation
import HealthKit

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
            case .noRecentWatchData:
                return "No recent Apple Watch metrics found. Pair/unlock the watch, open Health once, then try again."
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
        if nsError.domain == HKErrorDomain {
            switch HKError.Code(rawValue: nsError.code) {
            case .errorHealthDataUnavailable:
                return "Apple Health is unavailable on this device."
            case .errorHealthDataRestricted:
                return "Apple Health access is restricted on this device."
            case .errorAuthorizationDenied, .errorAuthorizationNotDetermined, .errorRequiredAuthorizationDenied:
                return "Apple Health access is not granted. Open iOS Settings → Privacy & Security → Health → Somatiq and allow access."
            case .errorDatabaseInaccessible:
                return "Health data is temporarily unavailable while the device is locked."
            case .errorNoData:
                return "No health data found yet. Wear Apple Watch for a while and try again."
            case .errorUserCanceled:
                return "Health access request was cancelled."
            default:
                break
            }
            if !nsError.localizedDescription.isEmpty {
                return nsError.localizedDescription
            }
            return "Apple Health request failed. Please try again."
        }

        if nsError.domain == NSCocoaErrorDomain {
            return "Local data access failed. Please retry."
        }

        return fallback
    }
}
