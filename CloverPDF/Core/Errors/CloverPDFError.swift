import Foundation

enum CloverPDFError: Error, LocalizedError, Sendable {
    case invalidPDF
    case lockedPDF
    case incorrectPassword
    case noPages
    case invalidPageRange
    case outputFailed
    case converterUnavailable
    case converterProtocol
    case conversionFailed(String)
    case cancelled
    case premiumRequired

    var errorDescription: String? {
        switch self {
        case .invalidPDF: String(localized: "The PDF is damaged or unsupported.")
        case .lockedPDF: String(localized: "This PDF requires a password.")
        case .incorrectPassword: String(localized: "The PDF password is incorrect.")
        case .noPages: String(localized: "No pages are available to process.")
        case .invalidPageRange: String(localized: "The selected page range is invalid.")
        case .outputFailed: String(localized: "The output file could not be created.")
        case .converterUnavailable: String(localized: "The Word converter is unavailable.")
        case .converterProtocol: String(localized: "The converter returned an invalid response.")
        case .conversionFailed(let code): String(localized: "Conversion failed: \(code)")
        case .cancelled: String(localized: "The task was cancelled.")
        case .premiumRequired: String(localized: "Premium is required for this conversion.")
        }
    }

    var code: String {
        switch self {
        case .invalidPDF: "invalid_pdf"
        case .lockedPDF: "password_required"
        case .incorrectPassword: "incorrect_password"
        case .noPages: "no_pages"
        case .invalidPageRange: "invalid_page_range"
        case .outputFailed: "output_failed"
        case .converterUnavailable: "converter_unavailable"
        case .converterProtocol: "converter_protocol"
        case .conversionFailed(let code): "conversion_failed:\(code)"
        case .cancelled: "cancelled"
        case .premiumRequired: "premium_required"
        }
    }

    static func localizedDescription(for code: String) -> String {
        if code.hasPrefix("conversion_failed:") {
            let detail = String(code.dropFirst("conversion_failed:".count))
            return String(localized: "Conversion failed: \(detail)")
        }
        return switch code {
        case "invalid_pdf": CloverPDFError.invalidPDF.localizedDescription
        case "password_required": CloverPDFError.lockedPDF.localizedDescription
        case "incorrect_password": CloverPDFError.incorrectPassword.localizedDescription
        case "no_pages": CloverPDFError.noPages.localizedDescription
        case "invalid_page_range": CloverPDFError.invalidPageRange.localizedDescription
        case "output_failed": CloverPDFError.outputFailed.localizedDescription
        case "converter_unavailable": CloverPDFError.converterUnavailable.localizedDescription
        case "converter_protocol": CloverPDFError.converterProtocol.localizedDescription
        case "cancelled": CloverPDFError.cancelled.localizedDescription
        case "premium_required": CloverPDFError.premiumRequired.localizedDescription
        default: String(localized: "The task could not be completed.")
        }
    }
}
