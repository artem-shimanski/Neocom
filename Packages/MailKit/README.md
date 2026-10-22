# MailKit

A character's EVE mail as plain data and the logic around it: header lists and their paging,
labels and unread counts, the markup of mail bodies, drafts, replies, the CSPA fee, recipient
suggestions and the new-mail check for background notifications.

MailKit deliberately has no ESI client and no UI. `MailSheet` (`Neocom/Neocom/Model/`) owns
`/characters/{id}/mail` (GET and POST), `/mail/{mail_id}`, `/mail/labels` and `/mail/lists`;
it maps the generated records into these types and caches them. The screens (`UI/Mail/`) read
them; `ZKillboardSheet` uses `MailRecipientKind` to pick entity searches, and
`NotificationBackgroundCheck` calls `MailWatch`. Names (`/universe/names`) are passed in by
the caller.

## Requirements

* Swift tools 6.4, iOS 26.0+ / macOS 26.0+
* No dependencies

## Types

Model (`Mail.swift`), all `Codable`: `MailHeader`, `MailMessage` (header plus markup body),
`MailRecipient`/`MailRecipientKind`, `MailLabel`, `MailLabels`, `MailLabelID`,
`MailLabelColor`, `MailingList`, `MailContact`, and `Mailbox`/`MailHeaderSource`, which
say what a header list shows and which `GET /mail` stream it is read from.

Header list (`MailInbox.swift`): `MailHeaderList` (pages, refresh, local updates),
`MailDayGroup`, `MailDateText`, `MailRecipientsLine` (`TO YOU + 11`), `MailUnreadSummary`,
`EVETime`.

Body (`MailMarkup.swift`): `MailMarkup.parse` turns EVE rich text into a `MailDocument` of
`MailRun`s with a `MailTextStyle`, a `MailColor` and an optional `MailLink` (character,
corporation, alliance, system, constellation, region, type, generic info, fitting, kill
report, URL). `MailMarkup.encode(plainText:)` goes the other way.

Writing (`MailCompose.swift`): `MailDraft`, `MailSubject`, `MailQuote`, `MailLimits`,
`MailSendOutcome`, `MailCSPA`, `MailSuggestions`/`MailSuggestion`.

Watching (`MailWatch.swift`): `MailWatch.check`.

## Rules the code encodes

* ESI pages are 50 headers, newest first; the next page is asked with the oldest loaded id.
  A page shorter than 50 is the last. A fresh first page replaces what it covers and keeps
  older pages; a full page that does not reach the loaded range starts over, so no gap is left.
* `GET /mail` filters by label only: a mailing list is read from the unfiltered list and
  keeps the mail addressed to it. Mailing lists are named only by `/mail/lists`, so
  `nameableIDs` leaves them out.
* A mail with several labels counts once in the unread total and once per label;
  `adjusting(from:to:)` keeps counts at zero or above. The four well-known labels
  (inbox 1, sent 2, corp 4, alliance 8) are always listed, with default names if ESI omitted them.
* Dates are UTC. Today is the same EVE day, "this week" the six days before; a date after
  now counts as today.
* The parser never fails and drops nothing: unknown tags and links it cannot open
  (`joinChannel:`, `showRouteTo:`, `contract:`, malformed `showinfo:`) become plain text.
  Colours are `#AARRGGBB` or `#RRGGBB`; the game's default body colour is `#bfffffff`.
* Limits: 1 to 50 recipients, subject 1000, body 10,000 characters counted on the encoded
  markup. On a reply the quote is cut to fit (never leaving half an entity or `<br>`); the
  pilot's own text never is. `Re:`/`Fw:` prefixes do not stack.
* CSPA: ESI documents no error for it, so a refusal is recognised by its text and the fee is
  the largest amount in it, ignoring the echoed HTTP status; `nil` when there is none.
* `MailWatch.check` reports unread mail from others with an id above the baseline; with no
  baseline the first check only records the newest id.

## Usage

```swift
import MailKit

let me: Int64 = 90_000_001
let header = MailHeader(id: 500, from: 91_000_001, subject: "Hello", date: .now, isRead: false,
                        labels: [MailLabelID.inbox],
                        recipients: [MailRecipient(id: me, kind: .character)])
let list = MailHeaderList(firstPage: [header])
let groups = MailDayGroup.grouped(list.headers, now: .now)

let message = MailMessage(header: header, body: "<font size=\"12\">Fly <b>safe</b></font>")
let document = MailMarkup.parse(message.body)
print(document.plainText)                              // "Fly safe"

var draft = MailDraft.reply(to: message, senderName: "Pilot")
draft.body = "Thanks"
if draft.canSend { print(draft.encodedBody) }

let check = MailWatch.check(list.headers, characterID: me, baseline: nil)
```

## Tests

```
cd MailKit && swift test
```

Swift Testing, no resources.
