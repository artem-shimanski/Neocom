import Foundation
import MailKit
import Testing

private let now = Date(timeIntervalSince1970: 1_792_238_400)
private let me: Int64 = 90_000_001

private func mail(_ id: Int64, from: Int64 = 91_000_000, read: Bool = false) -> MailHeader {
    MailHeader(id: id, from: from, subject: "Mail \(id)", date: now, isRead: read, labels: [MailLabelID.inbox],
               recipients: [MailRecipient(id: me, kind: .character)])
}

@Suite struct MailWatchTests {
    @Test func firstCheckOnlyRecords() {
        let result = MailWatch.check([mail(10), mail(12)], characterID: me, baseline: nil)
        #expect(result.new.isEmpty)
        #expect(result.baseline == 12)
        #expect(MailWatch.check([], characterID: me, baseline: nil).baseline == 0)
    }

    @Test func unreadFromOthersAboveTheBaseline() {
        let headers = [mail(9), mail(11), mail(12, read: true), mail(13, from: me), mail(14)]
        let result = MailWatch.check(headers, characterID: me, baseline: 10)
        #expect(result.new.map(\.id) == [14, 11])
        #expect(result.baseline == 14)
        // Nothing loaded: the baseline stays.
        #expect(MailWatch.check([], characterID: me, baseline: 14).baseline == 14)
    }
}
