import Foundation
import MailKit
import Testing

private let now = Date(timeIntervalSince1970: 1_792_238_400) // 2026-10-17 12:00 UTC
private let hour: TimeInterval = 3600
private let day: TimeInterval = 86_400
private let me: Int64 = 90_000_001

private func header(_ id: Int64, date: Date = now, read: Bool = false, labels: [Int64] = [MailLabelID.inbox],
                    to recipients: [MailRecipient] = [MailRecipient(id: me, kind: .character)]) -> MailHeader {
    MailHeader(id: id, from: 91_000_000 + id, subject: "Mail \(id)", date: date, isRead: read,
               labels: labels, recipients: recipients)
}

private func page(_ ids: ClosedRange<Int64>) -> [MailHeader] {
    ids.reversed().map { header($0, date: now.addingTimeInterval(Double($0 - 1000) * 60)) }
}

@Suite struct ModelTests {
    @Test func labelColoursAreESIsEighteen() {
        #expect(MailLabelColor.all.count == 18)
        #expect(Set(MailLabelColor.all).count == 18)
        #expect(MailLabelColor.isAllowed("#FF6600"))
        #expect(!MailLabelColor.isAllowed("#123456"))
    }

    @Test func mailboxesAlwaysFour() {
        let labels = MailLabels(labels: [MailLabel(id: 1, name: "Inbox", color: "#ffffff", unreadCount: 3),
                                         MailLabel(id: 4, name: "[Corp]", color: nil, unreadCount: 2),
                                         MailLabel(id: 256, name: "Trade", color: "#0099ff", unreadCount: 0),
                                         MailLabel(id: 128, name: "Fleet Ops", color: "#ff6600", unreadCount: 1)],
                                totalUnread: 5)
        #expect(labels.mailboxes.map(\.id) == [1, 2, 4, 8])
        #expect(labels.mailboxes[1].name == "Sent")
        #expect(labels.custom.map(\.name) == ["Fleet Ops", "Trade"])
        let summary = MailUnreadSummary(labels)
        #expect(summary.totalUnread == 5)
        #expect(summary.mailboxesLine == "Inbox 3 · [Corp] 2")
    }

    @Test func unreadCountsFollowAMail() {
        let labels = MailLabels(labels: [MailLabel(id: 1, name: "Inbox", color: nil, unreadCount: 3),
                                         MailLabel(id: 128, name: "Keep", color: nil, unreadCount: 1)],
                                totalUnread: 3)
        let unread = header(1, labels: [1, 128])
        var read = unread
        read.isRead = true
        let afterRead = labels.adjusting(from: unread, to: read)
        #expect(afterRead.totalUnread == 2)
        #expect(afterRead.label(1)?.unreadCount == 2)
        #expect(afterRead.label(128)?.unreadCount == 0)
        // And back.
        #expect(afterRead.adjusting(from: read, to: unread) == labels)
        // Relabelled while unread: moves the count.
        var moved = unread
        moved.labels = [1]
        #expect(labels.adjusting(from: unread, to: moved).label(128)?.unreadCount == 0)
        #expect(labels.adjusting(from: unread, to: moved).totalUnread == 3)
        // Deleted while unread; never below zero.
        #expect(labels.adjusting(from: unread, to: nil).totalUnread == 2)
        #expect(MailLabels(labels: [], totalUnread: 0).adjusting(from: unread, to: nil).totalUnread == 0)
    }

    @Test func mailboxMembership() {
        let toList = header(1, labels: [], to: [MailRecipient(id: 145_000_001, kind: .mailingList)])
        #expect(Mailbox.mailingList(145_000_001).contains(toList))
        #expect(!Mailbox.inbox.contains(toList))
        #expect(Mailbox.mailingList(145_000_001).source == .all)
        #expect(Mailbox.inbox.source == .label(1))
        #expect(MailHeaderSource.label(1).labelFilter == [1])
        #expect(MailHeaderSource.all.labelFilter == nil)
        #expect(header(2).nameableIDs.contains(me))
        #expect(!toList.nameableIDs.contains(145_000_001))
    }
}

@Suite struct HeaderListTests {
    @Test func firstPageAndCursor() {
        let full = MailHeaderList(firstPage: page(51...100))
        #expect(full.hasMore)
        #expect(full.nextCursor == 51)
        #expect(full.headers.first?.id == 100)
        let short = MailHeaderList(firstPage: page(1...10))
        #expect(!short.hasMore)
        #expect(short.nextCursor == nil)
    }

    @Test func appendingDedupesAndOrders() {
        let first = MailHeaderList(firstPage: page(51...100))
        // The list shifted by two between requests: 51 and 52 arrive again.
        let older = page(3...52)
        let merged = first.appending(olderPage: older)
        #expect(merged.headers.count == 98)
        #expect(merged.headers.map(\.id) == Array((3...100).reversed()))
        #expect(merged.hasMore)
        #expect(merged.nextCursor == 3)
        let last = merged.appending(olderPage: page(1...2))
        #expect(!last.hasMore)
        #expect(last.headers.count == 100)
    }

    @Test func refreshKeepsOlderPages() {
        // A full older page: there may be more still.
        let loaded = MailHeaderList(firstPage: page(51...100)).appending(olderPage: page(1...50))
        #expect(loaded.hasMore)
        // Two new mails; mail 60 deleted elsewhere.
        var fresh = page(53...102).filter { $0.id != 60 }
        fresh.append(header(52, date: now.addingTimeInterval(-948 * 60)))
        let refreshed = loaded.refreshed(withFirstPage: fresh)
        #expect(refreshed.headers.first?.id == 102)
        #expect(refreshed.header(60) == nil)
        #expect(refreshed.header(1) != nil)
        #expect(refreshed.headers.count == 101)
        #expect(refreshed.hasMore)
        #expect(refreshed.nextCursor == 1)
        // A short first page is the whole list.
        #expect(loaded.refreshed(withFirstPage: page(1...3)).headers.count == 3)
        // More than a page of new mail: the old pages would leave a gap, so they go.
        let jumped = loaded.refreshed(withFirstPage: page(201...250))
        #expect(jumped.headers.count == 50)
        #expect(jumped.nextCursor == 201)
    }

    @Test func updatingMembership() {
        let list = MailHeaderList(firstPage: page(51...100))
        var moved = list.header(70)!
        moved.labels = [128]
        #expect(list.updating(moved, belongs: false).header(70) == nil)
        // A mail newer than the oldest loaded joins; one older than the loaded range does not.
        let newer = header(80, labels: [1])
        #expect(list.removing(80).updating(newer, belongs: true).header(80) != nil)
        let older = header(10, date: now.addingTimeInterval(-10 * day))
        #expect(list.updating(older, belongs: true).header(10) == nil)
        #expect(MailHeaderList(firstPage: page(51...60)).updating(older, belongs: true).header(10) != nil)
    }
}

@Suite struct InboxTextTests {
    @Test func dayGroups() {
        #expect(MailDayGroup.of(now.addingTimeInterval(-11 * hour), now: now) == .today)
        #expect(MailDayGroup.of(now.addingTimeInterval(-13 * hour), now: now) == .thisWeek)
        #expect(MailDayGroup.of(now.addingTimeInterval(-3 * day), now: now) == .thisWeek)
        // 10.11 is six days before 10.17; 10.10 is not.
        #expect(MailDayGroup.of(now.addingTimeInterval(-6 * day), now: now) == .thisWeek)
        #expect(MailDayGroup.of(now.addingTimeInterval(-7 * day), now: now) == .earlier)
        #expect(MailDayGroup.of(now.addingTimeInterval(hour), now: now) == .today)
        let groups = MailDayGroup.grouped([header(3), header(2, date: now - 9 * day), header(1, date: now - day)], now: now)
        #expect(groups.map(\.group) == [.today, .thisWeek, .earlier])
    }

    @Test func dateText() {
        let morning = now.addingTimeInterval(-(12 * hour) + 11 * hour + 42 * 60) // 11:42
        #expect(MailDateText(morning, now: now).description == "11:42")
        #expect(MailDateText(now.addingTimeInterval(-day), now: now) == .yesterday)
        #expect(MailDateText(now.addingTimeInterval(-3 * day), now: now).description == "10.14")
        #expect(MailDateText(now.addingTimeInterval(-300 * day), now: now).description == "2025.12.21")
        #expect(EVETime.dateTimeText(now.addingTimeInterval(-14 * hour + 10 * 60)) == "2026.10.16 22:10")
    }

    @Test func recipientsLine() {
        #expect(MailRecipientsLine(header(1), characterID: me) == .you(others: 0))
        let many = header(2, to: [MailRecipient(id: 5, kind: .character), MailRecipient(id: me, kind: .character),
                                  MailRecipient(id: 6, kind: .corporation)])
        #expect(MailRecipientsLine(many, characterID: me) == .you(others: 2))
        let corp = MailRecipient(id: 98_000_001, kind: .corporation)
        let list = MailRecipient(id: 145_000_001, kind: .mailingList)
        let viaCorp = header(3, to: [list, corp])
        #expect(MailRecipientsLine(viaCorp, characterID: me, corporationID: 98_000_001) == .recipient(corp, others: 1))
        #expect(MailRecipientsLine(viaCorp, characterID: me) == .recipient(list, others: 1))
        #expect(MailRecipientsLine(header(4, to: []), characterID: me) == .nobody)
    }
}

@Suite struct MarkupTests {
    @Test func plainAndEntities() {
        let doc = MailMarkup.parse("Tom &amp; Jerry &lt;3 &#39;x&#x27; &unknown; a&b")
        #expect(doc.plainText == "Tom & Jerry <3 'x' &unknown; a&b")
        #expect(doc.runs.count == 1)
    }

    @Test func gameBody() {
        let body = "<font size=\"12\" color=\"#bfffffff\">Hello <b>pilot</b>,<br>see <i>this</i></font><br><br>"
        let doc = MailMarkup.parse(body)
        #expect(doc.plainText == "Hello pilot,\nsee this")
        // The trailing `<br><br>` is padding and goes.
        #expect(doc.runs.count == 4)
        #expect(doc.runs[0].style.size == 12)
        #expect(doc.runs[0].style.color == MailColor.eveDefault)
        #expect(doc.runs[0].style.color?.isNeutral == true)
        #expect(doc.runs[1].text == "pilot")
        #expect(doc.runs[1].style.isBold)
        #expect(doc.runs[1].style.size == 12)
        #expect(doc.runs[3].style.isItalic)
        #expect(!doc.runs[2].style.isItalic)
    }

    @Test func colours() {
        #expect(MailColor(hex: "#ffff6600") == MailColor(red: 255, green: 102, blue: 0))
        #expect(MailColor(hex: "0099ff") == MailColor(red: 0, green: 153, blue: 255))
        #expect(MailColor(hex: "#xyz") == nil)
        #expect(MailColor(hex: "#ffff6600")?.isNeutral == false)
    }

    @Test func showInfoLinks() {
        #expect(MailLink(href: "showinfo:1377//90000001") == .character(90_000_001))
        #expect(MailLink(href: "showinfo:34574//90000002") == .character(90_000_002))
        #expect(MailLink(href: "showinfo:2//98000001") == .corporation(98_000_001))
        #expect(MailLink(href: "showinfo:16159//99000001") == .alliance(99_000_001))
        #expect(MailLink(href: "showinfo:5//30002187") == .solarSystem(30_002_187))
        #expect(MailLink(href: "showinfo:3//10000002") == .region(10_000_002))
        #expect(MailLink(href: "showinfo:4//20000020") == .constellation(20_000_020))
        #expect(MailLink(href: "showinfo:626") == .type(626))
        #expect(MailLink(href: " showinfo:1529//60003760 ") == .info(typeID: 1529, itemID: 60_003_760))
        #expect(MailLink(href: "showinfo:abc") == nil)
        #expect(MailLink(href: "showinfo:626//x") == nil)
    }

    @Test func otherLinks() {
        #expect(MailLink(href: "fitting:626:2488;5:31370;1::") == .fitting(MailFitting(dna: "626:2488;5:31370;1::", shipTypeID: 626)))
        #expect(MailLink(href: "fitting:Vexor") == nil)
        #expect(MailLink(href: "killReport:123456:0a1b2c3d4e") == .killReport(id: 123_456, hash: "0a1b2c3d4e"))
        #expect(MailLink(href: "killReport:123456") == nil)
        #expect(MailLink(href: "https://www.eveonline.com/news") == .url(URL(string: "https://www.eveonline.com/news")!))
        #expect(MailLink(href: "joinChannel:-12345") == nil)
        #expect(MailLink(href: "showRouteTo:30000142") == nil)
        #expect(MailLink(href: "javascript:alert(1)") == nil)
    }

    @Test func anchors() {
        let body = """
        Fly <a href="showinfo:1377//90000003">Bram Ironvale</a>'s <a href="fitting:626:2488;5::">Vexor — drone ratting</a> \
        and <a href="joinChannel:-1">join us</a>; <a href='killReport:9:ab'>Kill report</a>
        """
        let doc = MailMarkup.parse(body)
        #expect(doc.plainText == "Fly Bram Ironvale's Vexor — drone ratting and join us; Kill report")
        #expect(doc.links == [.character(90_000_003), .fitting(MailFitting(dna: "626:2488;5::", shipTypeID: 626)), .killReport(id: 9, hash: "ab")])
        let join = doc.runs.first { $0.text.contains("join us") }
        #expect(join?.link == nil)
        #expect(doc.runs.first { $0.text == "Bram Ironvale" }?.link == .character(90_000_003))
    }

    @Test func nestedStylesInsideLink() {
        let doc = MailMarkup.parse("<a href=\"showinfo:626\"><u><b>Vexor</b></u></a> after")
        #expect(doc.runs[0].text == "Vexor")
        #expect(doc.runs[0].link == .type(626))
        #expect(doc.runs[0].style.isBold && doc.runs[0].style.isUnderlined)
        #expect(doc.runs[1].link == nil)
        #expect(doc.runs[1].style == .plain)
    }

    @Test func malformedStaysText() {
        #expect(MailMarkup.plainText("1 < 2 and 3 > 2") == "1 < 2 and 3 > 2")
        #expect(MailMarkup.plainText("I <3 you") == "I <3 you")
        #expect(MailMarkup.plainText("open <b without close") == "open <b without close")
        #expect(MailMarkup.plainText("<b>bold</i> still</b> done") == "bold still done")
        #expect(MailMarkup.plainText("<loc><script>x</script></loc>") == "x")
        // Unbalanced closers do not pop what was not opened.
        let doc = MailMarkup.parse("<b>a</u>b</b>c")
        #expect(doc.runs.map(\.text) == ["ab", "c"])
        // An apostrophe after a stray `<` is text, not the start of a quoted value.
        let stray = MailMarkup.parse("I <3 it, don't <b>you</b> think it's fine>")
        #expect(stray.plainText == "I <3 it, don't you think it's fine>")
        #expect(stray.runs.contains { $0.text == "you" && $0.style.isBold })
        // A quoted value may still hold `>`; `&#0;` stays as written.
        #expect(MailMarkup.parse("<a href=\"https://x.com/?a>b\">x</a>").runs.first?.link != nil)
        #expect(MailMarkup.plainText("a&#0;b") == "a&#0;b")
    }

    @Test func chatStyleURLAndParagraphs() {
        let doc = MailMarkup.parse("<url=showinfo:5//30000142>Jita</url><p>Two</p><p>Three</p>")
        #expect(doc.runs.first?.link == .solarSystem(30_000_142))
        #expect(doc.plainText == "Jita\nTwo\nThree")
    }

    @Test func newlinesAndTrimming() {
        #expect(MailMarkup.plainText("<br><br>Hi\r\nthere<br/>  <br />") == "Hi\nthere")
        #expect(MailMarkup.parse("<br><br>").isEmpty)
    }

    @Test func encodeForSending() {
        #expect(MailMarkup.encode(plainText: "a < b & c > d\nnext") == "a &lt; b &amp; c &gt; d<br>next")
        #expect(MailMarkup.plainText(MailMarkup.encode(plainText: "x <b>y</b>\r\nz")) == "x <b>y</b>\nz")
    }
}

@Suite struct ComposeTests {
    @Test func replySubjects() {
        #expect(MailSubject.reply(to: "Fleet roles") == "Re: Fleet roles")
        #expect(MailSubject.reply(to: "Re: Fleet roles") == "Re: Fleet roles")
        #expect(MailSubject.reply(to: "RE: re:Fleet roles") == "Re: Fleet roles")
        #expect(MailSubject.reply(to: "Re[2]: Fleet roles") == "Re: Fleet roles")
        #expect(MailSubject.forward("Re: Fleet roles") == "Fw: Re: Fleet roles")
        #expect(MailSubject.forward("Fwd: x") == "Fw: x")
        #expect(MailSubject.reply(to: "Ready: yes") == "Re: Ready: yes")
        #expect(MailSubject.reply(to: String(repeating: "x", count: 1000)).count == 1000)
    }

    @Test func replyDraft() {
        let message = MailMessage(header: MailHeader(id: 7, from: 91_000_001, subject: "Try this Vexor fit",
                                                     date: now.addingTimeInterval(-14 * hour + 10 * 60),
                                                     isRead: true, labels: [1],
                                                     recipients: [MailRecipient(id: me, kind: .character),
                                                                  MailRecipient(id: 5, kind: .character),
                                                                  MailRecipient(id: 145_000_001, kind: .mailingList)]),
                                  body: "Artem,<br>Here’s the <a href=\"fitting:626::\">fit</a>")
        let draft = MailDraft.reply(to: message, senderName: "Hedda Coldwater")
        #expect(draft.recipients == [MailRecipient(id: 91_000_001, kind: .character)])
        #expect(draft.subject == "Re: Try this Vexor fit")
        #expect(draft.quote == "\n\n--------------------------------\nOn 2026.10.16 22:10 Hedda Coldwater wrote:\nArtem,\nHere’s the fit")
        let all = MailDraft.replyAll(to: message, senderName: "Hedda Coldwater", characterID: me)
        #expect(all.recipients.count == 3)
        #expect(!all.recipients.contains(MailRecipient(id: me, kind: .character)))
        // Reply to all of the character's own mail: to its recipients, not back to itself.
        var sent = message
        sent.header.from = me
        let toOthers = MailDraft.replyAll(to: sent, senderName: "Artem Valiant", characterID: me)
        #expect(toOthers.recipients == [MailRecipient(id: 5, kind: .character),
                                        MailRecipient(id: 145_000_001, kind: .mailingList)])
        var typed = draft
        typed.body = "Thanks"
        #expect(typed.encodedBody.hasPrefix("Thanks<br><br>--------------------------------<br>On 2026.10.16"))
        #expect(MailDraft.forward(message, senderName: "Hedda Coldwater").recipients.isEmpty)
    }

    @Test func draftLimits() {
        var draft = MailDraft()
        #expect(draft.issues == [.noRecipients])
        for id in 1...60 { draft.add(MailRecipient(id: Int64(id), kind: .character)) }
        #expect(draft.recipients.count == 50)
        let addedAgain = draft.add(MailRecipient(id: 1, kind: .character))
        #expect(!addedAgain)
        draft.subject = String(repeating: "s", count: 1001)
        draft.body = String(repeating: "<", count: 2600) // 4 characters each once encoded
        #expect(draft.issues == [.subjectTooLong, .bodyTooLong])
        draft.subject = "ok"
        draft.body = String(repeating: "b", count: 9_990)
        draft.quote = "\n" + String(repeating: "&", count: 100)
        #expect(draft.canSend)
        let encoded = draft.encodedBody
        #expect(encoded.count <= MailLimits.bodyLength)
        #expect(encoded.hasPrefix(String(repeating: "b", count: 9_990) + "<br>"))
        #expect(!encoded.hasSuffix("&") && !encoded.hasSuffix("&am"))
    }

    @Test func cspaRefusals() {
        #expect(MailCSPA.charge(status: 520, message: "ContactCostNotApproved") == .required(cost: nil))
        #expect(MailCSPA.charge(status: 520, message: "Error 520: CSPA charge of 25,000 ISK not approved") == .required(cost: 25_000))
        #expect(MailCSPA.charge(status: 400, message: "approved_cost must be at least 25 000") == .required(cost: 25_000))
        #expect(MailCSPA.charge(status: 520, message: "Contact cost not approved: 1500.00") == .required(cost: 1_500))
        #expect(MailCSPA.charge(status: 520, message: "EVE backend error") == MailCSPA.Charge.none)
        #expect(MailCSPA.charge(status: 420, message: nil) == MailCSPA.Charge.none)
        #expect(MailCSPA.approvedCost(24_999.2) == 25_000)
        #expect(MailCSPA.approvedCost(0) == 0)
    }

    @Test func suggestions() {
        let ysolde = MailRecipient(id: 1, kind: .character)
        let marr = MailRecipient(id: 2, kind: .character)
        let yssen = MailRecipient(id: 3, kind: .corporation)
        let pact = MailRecipient(id: 4, kind: .alliance)
        let names: [Int64: String] = [1: "Ysolde Marrow", 2: "Ysolde Marr", 3: "Yssen Collective", 4: "Ysgarth Pact",
                                      5: "Bram Ysworth", 6: "Mys Trader"]
        let contacts = [MailContact(recipient: MailRecipient(id: 6, kind: .character), standing: 10),
                        MailContact(recipient: ysolde, standing: 5),
                        MailContact(recipient: MailRecipient(id: 5, kind: .character), standing: -10)]
        let result = MailSuggestions.make(query: "ys", contacts: contacts,
                                          mailingLists: [MailingList(id: 145_000_001, name: "Ys Traders"),
                                                         MailingList(id: 145_000_002, name: "Rens Traders")],
                                          searchResults: [pact, ysolde, marr, yssen, MailRecipient(id: 99, kind: .character)],
                                          names: names,
                                          excluding: [MailRecipient(id: 5, kind: .character)])
        #expect(result.map(\.name) == ["Ysolde Marrow", "Mys Trader", "Ys Traders", "Ysgarth Pact", "Ysolde Marr", "Yssen Collective"])
        #expect(result[0].source == .contact(standing: 5))
        #expect(result[2].source == .mailingList)
        #expect(result[3].source == .search)
        #expect(MailSuggestions.make(query: " ", contacts: contacts, mailingLists: [], searchResults: [], names: names).isEmpty)
    }
}
