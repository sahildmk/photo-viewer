import SwiftUI

struct GridItemView: View, Equatable {
    let item: ImageItem
    let isFocused: Bool
    let isSelected: Bool

    @State private var thumbnail: NSImage?

    private let size: CGFloat = 160

    static func == (lhs: GridItemView, rhs: GridItemView) -> Bool {
        lhs.item.id == rhs.item.id
            && lhs.isFocused == rhs.isFocused
            && lhs.isSelected == rhs.isSelected
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            thumbnailContent
                .frame(width: size, height: size)
                .clipped()
                .clipShape(.rect(cornerRadius: 4))

            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.white, .blue)
                    .shadow(radius: 2)
                    .padding(6)
            }
        }
        .overlay {
            if isFocused {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.accentColor, lineWidth: 3)
            }
        }
        .task(id: item.url) {
            // Cache hit — instant, no async hop needed
            if let cached = await ThumbnailCache.shared.get(item.url) {
                thumbnail = cached
                return
            }
            // Generate — this task is cancelled when the cell scrolls off screen,
            // which releases the semaphore slot so visible cells get priority
            let image = await ThumbnailGenerator.loadThumbnail(for: item.url)
            if !Task.isCancelled {
                thumbnail = image
            }
        }
    }

    @ViewBuilder
    private var thumbnailContent: some View {
        if let thumbnail {
            Image(nsImage: thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fill)
        } else {
            Color(.windowBackgroundColor)
        }
    }
}
