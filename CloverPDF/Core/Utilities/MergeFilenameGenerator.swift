import Foundation

enum MergeFilenameGenerator {
    static func filename(at date: Date = Date(), timeZone: TimeZone = .current) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyyMMddHHmm"
        return formatter.string(from: date) + ".pdf"
    }
}
