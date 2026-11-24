import Foundation
/// One formatter composition boundary shared by both UI adapters.
public enum ExplorerExportFormatting {
    public static func localized()->ConfiguredReport.Formatting {
#if os(Windows)
        let owner=WindowsFormatterOwner();let number=NumberFormatter()
        return .init(decimalSeparator:number.decimalSeparator?.first ?? ".",time:{value,_,part,now in
            guard let value else {return "*VOID*"};return owner.string(value,part:part,now:now)
        })
#else
        return MacExportFormatting.localized()
#endif
    }
}
#if os(Windows)
/// Foundation Windows lacks RelativeDateTimeFormatter. Age uses explicit whole
/// seconds; localized short dates, medium times and decimal separator use ICU.
private final class WindowsFormatterOwner:@unchecked Sendable {
    let lock=NSLock();let date=DateFormatter();let time=DateFormatter()
    init(){date.dateStyle = .short;date.timeStyle = .none;time.dateStyle = .none;time.timeStyle = .medium}
    func string(_ value:Date,part:ConfiguredReport.TimePart,now:Date)->String {
        lock.lock();defer{lock.unlock()}
        switch part {case .date:return date.string(from:value);case .time:return time.string(from:value);case .age:return String(Int64(now.timeIntervalSince(value)))+"s"}
    }
}
#else
/// Explicit Mac presentation boundary: Foundation's localized short date,
/// medium time and numeric relative age, not a Windows formatter emulation.
public enum MacExportFormatting {
    public static func localized(locale: Locale = .current, timeZone: TimeZone = .current) -> ConfiguredReport.Formatting {
        let owner = FormatterOwner(locale: locale, timeZone: timeZone)
        let number = NumberFormatter(); number.locale = locale
        return ConfiguredReport.Formatting(decimalSeparator: number.decimalSeparator?.first ?? ".", time: { date, _, part, now in
            guard let date else { return "*VOID*" }
            return owner.string(date, part: part, now: now)
        })
    }
    private final class FormatterOwner: @unchecked Sendable {
        let lock = NSLock(), date = DateFormatter(), time = DateFormatter(), age = RelativeDateTimeFormatter()
        init(locale: Locale, timeZone: TimeZone) {
            date.locale = locale; date.timeZone = timeZone; date.dateStyle = .short; date.timeStyle = .none
            time.locale = locale; time.timeZone = timeZone; time.dateStyle = .none; time.timeStyle = .medium
            age.locale = locale; age.dateTimeStyle = .numeric
        }
        func string(_ value: Date, part: ConfiguredReport.TimePart, now: Date) -> String {
            lock.lock(); defer { lock.unlock() }
            switch part { case .date: return date.string(from: value); case .time: return time.string(from: value); case .age: return age.localizedString(for: value, relativeTo: now) }
        }
    }
}


#endif
