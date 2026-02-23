# macOS Photo Viewer App

## Context
Build a native macOS SwiftUI app that lets you select a folder, view all images in a fast grid, navigate with keyboard, and select photos (spacebar) for batch copying to another folder. Performance is the top priority — thumbnails must load instantly and navigation must feel snappy.

## Tech Stack
- **SwiftUI** (macOS 14+ with `@Observable`)
- **Swift Package Manager** — no Xcode project, build with `swift build` / `swift run`
- **No external dependencies** — uses system frameworks (AppKit, ImageIO, UniformTypeIdentifiers)

## File Structure
```
Package.swift
Sources/PhotoViewer/
  App/
    PhotoViewerApp.swift       -- @main, window, NSApp activation, Cmd+O menu
    AppState.swift             -- @Observable central state (images, focus, selection, view mode)
  Models/
    ImageItem.swift            -- Simple struct: id (UUID), url (URL), fileName
  Services/
    FolderScanner.swift        -- Async folder scan using FileManager + UTType filtering
    ThumbnailCache.swift       -- Actor with CGImageSource thumbnail gen (~16ms/image)
    ImageLoader.swift          -- Full-size async loader with NSCache (limit 5)
    FileCopyService.swift      -- Copy selected files to destination folder
  Views/
    ContentView.swift          -- Switches between grid and single-photo view
    GridView.swift             -- LazyVGrid + keyboard nav + ScrollViewReader
    GridItemView.swift         -- Thumbnail cell with .task loading, focus ring, checkmark badge
    SinglePhotoView.swift      -- Full-size view with arrow nav + prefetching adjacent images
    ToolbarView.swift          -- Open Folder button, Copy Selected button, status text
```

## Key Design Decisions

### Performance
| Concern | Approach |
|---|---|
| Thumbnail gen | `CGImageSourceCreateThumbnailAtIndex` — 20-40x faster than NSImage resize |
| Thumbnail cache | Actor-isolated `[URL: NSImage]` dict, deduplicates in-flight requests |
| Lazy loading | `LazyVGrid` + `.task(id:)` — only loads visible cells |
| Full-size images | `NSCache` (countLimit: 5), loaded on detached task |
| Prefetching | Adjacent 2 images prefetched in single-photo view |
| Folder scan | Async `FileManager.enumerator`, single-level, UTType filtering |

### Navigation & Selection
- **Grid**: Arrow keys move focus (blue ring), spacebar toggles selection (checkmark badge), Enter/double-click opens single view
- **Single photo**: Left/right arrows navigate, spacebar selects, Escape returns to grid
- **Column-aware**: Grid tracks column count via GeometryReader so up/down arrows jump correctly
- `focusedIndex` (Int?) is separate from `selectedIDs` (Set<UUID>) — focus is the cursor, selection is the spacebar toggle

### SPM App Workaround
`NSApp.setActivationPolicy(.regular)` in app init — required for SPM executables to get a menu bar and Dock icon.

### Copy Flow
Toolbar button (Cmd+E) opens destination folder picker, copies all selected files with collision-safe naming, then clears selection.

## Implementation Order
1. `Package.swift` + `PhotoViewerApp.swift` — get a window on screen
2. `AppState` + `ImageItem` + `FolderScanner` — open folder, populate images
3. `ThumbnailCache` — fast CGImageSource thumbnail generation
4. `GridView` + `GridItemView` — thumbnail grid with lazy loading
5. Keyboard navigation — arrow keys, focus highlight, spacebar selection, Enter
6. `SinglePhotoView` + `ImageLoader` — full-size view with prefetch
7. `FileCopyService` + `ToolbarView` — copy selected photos
8. Polish — error handling, edge cases, empty state

## Verification
1. `swift build` — must compile without errors
2. `swift run PhotoViewer` — window appears with empty state prompt
3. Cmd+O or toolbar button — open a folder with images, grid populates with thumbnails
4. Arrow keys navigate grid, spacebar selects (checkmark appears), Enter opens single view
5. Left/right arrows in single view, Escape returns to grid, selections persist
6. Select several photos, Cmd+E to copy to a destination folder, verify files copied
