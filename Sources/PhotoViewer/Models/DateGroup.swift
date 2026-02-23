import Foundation

struct DateGroup: Identifiable, Sendable {
    let id: DateComponents
    let date: Date
    let range: Range<Int>

    var displayLabel: String {
        date.formatted(.dateTime.weekday(.wide).month(.wide).day().year())
    }
}
