import Foundation

/// What a background check finds new in the inbox since the last one, against a baseline the
/// app keeps: the newest mail id seen. EVE hands out mail ids in increasing order, so a mail is
/// new exactly when its id is above that.
public enum MailWatch {
    /// The newest mail id seen at the last check; `nil` before the first one.
    public typealias Baseline = Int64

    /// The unread mail from someone else that arrived after `baseline`, newest first, and the
    /// baseline for the next check. Without a baseline nothing is reported: the first check
    /// only records where the inbox stands.
    public static func check(_ headers: [MailHeader], characterID: Int64,
                             baseline: Baseline?) -> (new: [MailHeader], baseline: Baseline) {
        let newest = headers.map(\.id).max()
        guard let baseline else { return ([], newest ?? 0) }
        let new = headers
            .filter { $0.id > baseline && !$0.isRead && $0.from != characterID }
            .sorted { $0.id > $1.id }
        return (new, max(baseline, newest ?? baseline))
    }
}
