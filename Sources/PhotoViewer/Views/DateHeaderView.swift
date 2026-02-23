import SwiftUI

struct DateHeaderView: View {
    let group: DateGroup
    let groupIndex: Int
    let photoCount: Int
    let allSelected: Bool
    let onToggle: () -> Void

    var body: some View {
        HStack {
            Button(action: onToggle) {
                Image(systemName: allSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(allSelected ? .blue : .secondary)
                    .font(.title3)
            }
            .buttonStyle(.plain)

            Text(group.displayLabel)
                .font(.headline)

            Text("\(photoCount) photos")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(.bar)
        .onTapGesture {
            onToggle()
        }
    }
}
