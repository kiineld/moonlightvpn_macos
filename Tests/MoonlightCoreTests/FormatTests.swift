import Foundation
import MoonlightCore

/// The formatters are pinned against the strings the design itself shows,
/// because that is the specification — `24,8 из 100 ГБ`, not whatever
/// `ByteCountFormatter` happens to produce.
func formatTests() {
    Check.suite("Format") {
        Check.equal(Format.bytes(26_629_345_280, locale: .ru), "24,8\u{00A0}ГБ",
                    "Russian uses a decimal comma and binary units")
        Check.equal(Format.bytes(26_629_345_280, locale: .en), "24.8\u{00A0}GB",
                    "English uses a decimal point")

        // Bytes and kilobytes have no meaningful fraction.
        Check.equal(Format.bytes(512, locale: .ru), "512\u{00A0}Б", "bytes carry no fraction")
        Check.equal(Format.bytes(2048, locale: .ru), "2\u{00A0}КБ", "kilobytes carry no fraction")
        Check.equal(Format.bytes(118_111_600_640, locale: .en), "110\u{00A0}GB",
                    "three digits drop the fraction")

        // A missing value must not read as "0 B", which the user would act on.
        Check.equal(Format.bytes(nil, locale: .ru), "—", "unknown bytes are a dash, not zero")

        Check.equal(Format.duration(767), "00:12:47", "duration")
        Check.equal(Format.duration(173_527), "48:12:07", "hours do not wrap at a day")
        Check.equal(Format.duration(-5), "00:00:00", "negative uptime floors at zero")

        Check.equal(Format.days(1, locale: .ru), "1 день", "ru singular")
        Check.equal(Format.days(3, locale: .ru), "3 дня", "ru paucal")
        Check.equal(Format.days(12, locale: .ru), "12 дней", "ru plural")
        // 11–14 take the genitive plural despite ending in 1–4.
        Check.equal(Format.days(11, locale: .ru), "11 дней", "ru teens are plural")
        Check.equal(Format.days(21, locale: .ru), "21 день", "ru 21 is singular")
        Check.equal(Format.days(22, locale: .ru), "22 дня", "ru 22 is paucal")
        Check.equal(Format.days(112, locale: .ru), "112 дней", "ru 112 is plural")
        Check.equal(Format.days(1, locale: .en), "1 day", "en singular")
        Check.equal(Format.days(12, locale: .en), "12 days", "en plural")
        Check.equal(Format.days(nil, locale: .ru), "без срока", "no expiry is named")
        Check.equal(Format.days(nil, locale: .en), "no expiry", "no expiry is named (en)")

        // The design's own string.
        Check.equal(Format.quota(used: 26_629_345_280, total: 107_374_182_400, locale: .ru),
                    "24,8 из 100\u{00A0}ГБ", "quota renders both halves in one unit")
        Check.equal(Format.quota(used: 26_629_345_280, total: 107_374_182_400, locale: .en),
                    "24.8 of 100\u{00A0}GB", "quota (en)")
        Check.equal(Format.quota(used: 1_073_741_824, total: nil, locale: .ru),
                    "1,0\u{00A0}ГБ · без лимита", "unlimited says so rather than showing a denominator")
        Check.equal(Format.quota(used: 1_073_741_824, total: 0, locale: .en),
                    "1.0\u{00A0}GB · unlimited", "a zero total is unlimited")

        // n/a rather than a dash: a dash reads as "not measured yet", and the
        // two are worth telling apart when one means the node is down.
        Check.equal(Format.latency(nil), "n/a", "an unanswered node reads n/a, not 0 ms")
        Check.equal(Format.latency(24), "24 ms", "latency")
    }
}
