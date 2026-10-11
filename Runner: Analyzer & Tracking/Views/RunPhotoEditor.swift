import PhotosUI
import RunCore
import SwiftUI

struct RunPhotoSession: Identifiable {
  let id = UUID()
  let run: RunData
  let units: UnitSystem
}

struct RunPhotoEditor: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.openURL) private var openURL
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  private let stats: RunPhotoStats
  private let route: RunPhotoRoute
  private let onExport: (RunPhotoExportResult) -> Void
  @State private var composition = RunPhotoComposition()
  @State private var pickerVisible = false
  @State private var pickerItem: PhotosPickerItem?
  @State private var loadTask: Task<Void, Never>?
  @State private var loadID = UUID()
  @State private var loading = false
  @State private var exporting = false
  @State private var started = false
  @State private var errorMessage: String?
  @State private var permissionDenied = false
  @State private var retryExport: Bool?
  @State private var discardPrompt = false
  @State private var hasUnexportedChanges = false
  @State private var shareURL: URL?
  @State private var shareVisible = false
  @State private var shareCompleted = false
  @State private var shareError: String?
  @State private var dragLayer: RunPhotoLayer?
  @State private var dragStart: RunPhotoTransform?
  @State private var pinchStart: CGFloat?
  @State private var cropStart: RunPhotoCrop?
  @State private var cropPinchStart: CGFloat?
  @State private var fixtureAttempts = 0

  init(run: RunData, units: UnitSystem, onExport: @escaping (RunPhotoExportResult) -> Void) {
    stats = RunPhotoStats(run: run, units: units)
    route = RunPhotoRoute(run: run)
    self.onExport = onExport
  }

  var body: some View {
    NavigationStack {
      GeometryReader { proxy in
        if proxy.size.width > proxy.size.height && proxy.size.width > 600 {
          HStack(spacing: 0) {
            preview
            controls.frame(width: min(360, proxy.size.width * 0.44)).clipped()
          }
        } else {
          VStack(spacing: 0) {
            preview
            controls.frame(height: min(340, max(240, proxy.size.height * 0.43))).clipped()
          }
        }
      }
      .background(Color(uiColor: .systemGroupedBackground))
      .navigationTitle("Run Photo").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Close") {
            if hasUnexportedChanges { discardPrompt = true } else { dismiss() }
          }.disabled(exporting).accessibilityIdentifier("photo.close")
        }
        ToolbarItem(placement: .primaryAction) {
          Button { export(share: true) } label: {
            Label("Share to apps", systemImage: "square.and.arrow.up")
          }.disabled(composition.image == nil || loading || exporting)
            .accessibilityHint("Choose an installed app or another sharing service")
            .accessibilityIdentifier("photo.share")
        }
      }
      .safeAreaInset(edge: .bottom) {
        VStack(spacing: 8) {
          HStack(spacing: 12) {
            Button { choosePhoto() } label: {
              Label(composition.image == nil ? "Choose Photo" : "Change Photo", systemImage: "photo")
                .padding(.vertical, 12).frame(maxWidth: .infinity, minHeight: 48)
                .foregroundStyle(.white).background(Color(white: 0.18), in: Capsule())
            }.buttonStyle(.plain)
              .accessibilityIdentifier("photo.choose")
            Button { export(share: false) } label: {
              Label("Save Photo", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity)
            }.buttonStyle(.borderedProminent).tint(.white).foregroundStyle(.black)
              .disabled(composition.image == nil || loading || exporting)
              .accessibilityIdentifier("photo.save")
          }.controlSize(.large).font(.subheadline.weight(.semibold))
            .disabled(exporting)
        }.padding(12).background(.bar)
      }
      .photosPicker(isPresented: $pickerVisible, selection: $pickerItem, matching: .images)
      .onChange(of: pickerItem) { _, item in if let item { loadPhoto(item) } }
      .sheet(isPresented: $shareVisible, onDismiss: shareDismissed) {
        if let shareURL {
          RunPhotoSharePresentation(url: shareURL) { completed, error in
            shareError = error?.localizedDescription
            shareCompleted = completed && error == nil
            shareVisible = false
          }
        }
      }
      .alert("Couldn’t finish", isPresented: Binding(
        get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
        if permissionDenied {
          Button("Share Instead") { export(share: true) }
          Button("Open Settings") {
            if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
          }
        } else if let share = retryExport {
          Button("Retry") { export(share: share) }
        } else if composition.image == nil || pickerItem != nil {
          Button("Retry") {
            if let item = pickerItem { loadPhoto(item) } else { choosePhoto() }
          }
        }
        Button("OK", role: .cancel) {}
      } message: { Text(errorMessage ?? "") }
      .confirmationDialog("Discard this photo edit?", isPresented: $discardPrompt,
        titleVisibility: .visible) {
        Button("Discard edits", role: .destructive) { dismiss() }
      }
      .interactiveDismissDisabled(hasUnexportedChanges || exporting)
      .task {
        guard !started else { return }
        started = true
        choosePhoto()
      }
      .onDisappear {
        loadTask?.cancel()
        loadID = UUID()
        if !shareVisible { cleanShareFile() }
      }
    }.preferredColorScheme(.dark)
  }

  private var preview: some View {
    GeometryReader { proxy in
      let canvas = composition.canvasSize
      let scale = min(max(1, proxy.size.width - 32) / canvas.width,
        max(1, proxy.size.height - 32) / canvas.height)
      ZStack {
        Color.black.opacity(0.35)
        if composition.image != nil {
          ZStack(alignment: .topLeading) {
            RunPhotoCompositionView(composition: composition, stats: stats, route: route)
              .scaleEffect(scale, anchor: .topLeading)
              .frame(width: canvas.width * scale, height: canvas.height * scale, alignment: .topLeading)
              .allowsHitTesting(false)
            if composition.selection == .photo {
              Rectangle().fill(.clear).contentShape(Rectangle())
                .frame(width: canvas.width * scale, height: canvas.height * scale)
                .accessibilityLabel("Photo crop").accessibilityIdentifier("photo.cropCanvas")
            } else {
              ForEach(composition.overlayLayers) { overlayHandle($0, displayScale: scale) }
            }
          }
          .frame(width: canvas.width * scale, height: canvas.height * scale, alignment: .topLeading)
          .coordinateSpace(name: "photo.canvas")
          .contentShape(Rectangle())
          .onTapGesture(coordinateSpace: .named("photo.canvas")) { point in
            guard composition.selection != .photo else { return }
            if let layer = layer(at: point, displayScale: scale) { composition.selection = layer }
          }
          .highPriorityGesture(canvasDrag(displayScale: scale))
          .simultaneousGesture(canvasMagnification)
          .clipped().allowsHitTesting(!loading && !exporting)
        } else {
          VStack(spacing: 12) {
            Image(systemName: "photo.badge.plus").font(.system(size: 36))
            Text("Your run. Your photo.").font(.title3.bold())
            Text("Choose a photo to add your stats and route.")
              .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
          }.padding(24)
        }
        if loading || exporting {
          ProgressView(loading ? "Loading photo…" : "Preparing image…")
            .padding(20).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
      }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
  }

  private var controls: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        HStack {
          Picker("Image format", selection: $composition.format) {
            ForEach(RunPhotoFormat.allCases) { format in Text(format.label).tag(format) }
          }.accessibilityIdentifier("photo.format")
          Spacer()
          Button("Reset") {
            composition.resetLayout()
            edited()
          }.accessibilityIdentifier("photo.reset")
        }
        Picker("Edit layer", selection: $composition.selection) {
          Text("Stats").tag(RunPhotoLayer.stats)
          if composition.showsRoute { Text("Route").tag(RunPhotoLayer.route) }
          if composition.showsIcon { Text("Icon").tag(RunPhotoLayer.icon) }
          Text("Crop").tag(RunPhotoLayer.photo)
        }.pickerStyle(.menu).accessibilityIdentifier("photo.layer")
        Text(composition.selection == .photo
          ? "Drag to reframe. Pinch to zoom the photo."
          : "Drag to move. Pinch to resize the selected overlay.")
          .font(.caption).foregroundStyle(.secondary)
        if composition.selection == .stats { textStyleControls }
        if composition.selection == .route { routeColorControls }
        VStack(alignment: .leading, spacing: 4) {
          Text(composition.selection == .photo ? "Zoom" : "Size").font(.subheadline.weight(.medium))
          Slider(value: sizeBinding, in: sizeRange)
            .accessibilityLabel(composition.selection == .photo ? "Photo zoom" : "Overlay size")
            .accessibilityIdentifier("photo.size")
        }
        VStack(alignment: .leading, spacing: 4) {
          Text("Position").font(.subheadline.weight(.medium))
          HStack(spacing: 8) {
            moveButton("Move left", symbol: "arrow.left", x: -1, y: 0)
            moveButton("Move up", symbol: "arrow.up", x: 0, y: -1)
            moveButton("Move down", symbol: "arrow.down", x: 0, y: 1)
            moveButton("Move right", symbol: "arrow.right", x: 1, y: 0)
          }
        }
        Toggle(isOn: $composition.showsRoute) {
          Label("Add route", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
        }.disabled(route.isEmpty).accessibilityIdentifier("photo.routeToggle")
        if route.isEmpty {
          Text("No drawable GPS route is available for this run. You can still share your stats.")
            .font(.caption).foregroundStyle(.secondary)
        }
        Toggle(isOn: $composition.showsIcon) {
          Label("Include app icon", systemImage: "app")
        }.accessibilityIdentifier("photo.iconToggle")
      }.padding(16)
    }
    .accessibilityIdentifier("photo.controls")
    .disabled(composition.image == nil || loading || exporting)
    .onChange(of: composition.format) { _, _ in
      composition.crop = RunPhotoCrop()
      composition.constrainOverlays()
      edited()
    }
    .onChange(of: composition.showsRoute) { _, visible in
      if visible { composition.selection = .route }
      else if composition.selection == .route { composition.selection = .stats }
      edited()
    }
    .onChange(of: composition.showsIcon) { _, visible in
      if visible { composition.selection = .icon }
      else if composition.selection == .icon { composition.selection = .stats }
      edited()
    }
    .onChange(of: composition.alignment) { _, _ in edited() }
    .onChange(of: composition.routeColor) { _, _ in edited() }
    .onChange(of: composition.fontStyle) { _, _ in
      composition.constrainOverlays()
      edited()
    }
  }

  private var textStyleControls: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Text alignment").font(.subheadline.weight(.medium))
      Picker("Text alignment", selection: $composition.alignment) {
        ForEach(RunPhotoAlignment.allCases) { Text($0.rawValue).tag($0) }
      }.pickerStyle(.segmented).frame(minHeight: 44)
        .accessibilityIdentifier("photo.alignment")
      Text("Font").font(.subheadline.weight(.medium))
      let columns = dynamicTypeSize.isAccessibilitySize ? 1 : 2
      Grid(horizontalSpacing: 8, verticalSpacing: 8) {
        ForEach(0..<((RunPhotoFontStyle.allCases.count + columns - 1) / columns), id: \.self) { row in
          GridRow {
            ForEach(0..<columns, id: \.self) { column in
              let index = row * columns + column
              if index < RunPhotoFontStyle.allCases.count {
                fontButton(RunPhotoFontStyle.allCases[index])
              }
            }
          }
        }
      }
    }
  }

  private func fontButton(_ style: RunPhotoFontStyle) -> some View {
    Button {
      composition.fontStyle = style
    } label: {
      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(style.rawValue).font(.caption.weight(.medium))
          Spacer(minLength: 2)
          if composition.fontStyle == style { Image(systemName: "checkmark").font(.caption.bold()) }
        }
        Text(stats.distance).font(Font(style.layout.valueFont.withSize(20)))
          .lineLimit(1).minimumScaleFactor(0.5)
      }.padding(10).frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
        .foregroundStyle(.white)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
          RoundedRectangle(cornerRadius: 10)
            .stroke(composition.fontStyle == style ? RunPhotoWordmark.yellow : .clear, lineWidth: 2)
        }
    }.buttonStyle(.plain)
      .accessibilityLabel("Font, \(style.rawValue)")
      .accessibilityValue(composition.fontStyle == style ? "Selected" : "")
      .accessibilityAddTraits(composition.fontStyle == style ? .isSelected : [])
      .accessibilityIdentifier("photo.font.\(style.rawValue.lowercased())")
  }

  private var routeColorControls: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Route color").font(.subheadline.weight(.medium))
      Text("Choose a color that stands out against your photo.")
        .font(.caption).foregroundStyle(.secondary)
      let columns = dynamicTypeSize.isAccessibilitySize ? 1 : 2
      Grid(horizontalSpacing: 8, verticalSpacing: 8) {
        ForEach(0..<((RunPhotoRouteColor.allCases.count + columns - 1) / columns), id: \.self) { row in
          GridRow {
            ForEach(0..<columns, id: \.self) { column in
              let index = row * columns + column
              if index < RunPhotoRouteColor.allCases.count {
                routeColorButton(RunPhotoRouteColor.allCases[index])
              }
            }
          }
        }
      }
    }
  }

  private func routeColorButton(_ color: RunPhotoRouteColor) -> some View {
    let selected = composition.routeColor == color
    return Button { composition.routeColor = color } label: {
      HStack(spacing: 8) {
        Circle().fill(Color(uiColor: color.uiColor)).frame(width: 20, height: 20)
          .overlay { Circle().stroke(.white.opacity(0.6), lineWidth: 1) }
          .accessibilityHidden(true)
        Text(color.label).font(.subheadline.weight(.medium))
        Spacer(minLength: 0)
        if selected { Image(systemName: "checkmark").font(.caption.bold()) }
      }.padding(10).frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .foregroundStyle(.white)
        .background(.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
          RoundedRectangle(cornerRadius: 10)
            .stroke(selected ? RunPhotoWordmark.yellow : .clear, lineWidth: 2)
        }
    }.buttonStyle(.plain)
      .accessibilityLabel("Route color, \(color.label)")
      .accessibilityValue(selected ? "Selected" : "")
      .accessibilityAddTraits(selected ? .isSelected : [])
      .accessibilityIdentifier("photo.routeColor.\(color.rawValue)")
  }

  private func transform(_ layer: RunPhotoLayer) -> RunPhotoTransform {
    composition.transform(layer)
  }
  private func contentSize(_ layer: RunPhotoLayer) -> CGSize {
    composition.contentSize(layer)
  }
  private func setTransform(_ value: RunPhotoTransform, layer: RunPhotoLayer) {
    composition.setTransform(value, layer: layer)
    edited()
  }
  private var sizeRange: ClosedRange<Double> {
    if composition.selection == .photo { return 1...4 }
    let maximum = RunPhotoTransform(center: .zero, scale: 100)
      .clamped(content: contentSize(composition.selection), canvas: composition.canvasSize).scale
    return Double(min(0.25, maximum))...Double(maximum)
  }
  private var sizeBinding: Binding<Double> {
    Binding(get: {
      Double(composition.selection == .photo ? composition.crop.zoom : transform(composition.selection).scale)
    }, set: { value in
      if composition.selection == .photo {
        composition.crop.zoom = value
        edited()
      } else {
        var next = transform(composition.selection)
        next.scale = value
        setTransform(next, layer: composition.selection)
      }
    })
  }

  private func moveButton(_ label: String, symbol: String, x: CGFloat, y: CGFloat) -> some View {
    Button {
      if composition.selection == .photo {
        composition.crop.offset.x = min(1, max(-1, composition.crop.offset.x + x * 0.1))
        composition.crop.offset.y = min(1, max(-1, composition.crop.offset.y + y * 0.1))
        edited()
      } else {
        var next = transform(composition.selection)
        next.center.x += x * 0.025
        next.center.y += y * 0.025
        setTransform(next, layer: composition.selection)
      }
    } label: {
      Image(systemName: symbol).frame(width: 44, height: 44)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }.buttonStyle(.plain)
      .accessibilityLabel(label).accessibilityIdentifier("photo.\(symbol)")
  }

  private func overlayHandle(_ layer: RunPhotoLayer, displayScale: CGFloat) -> some View {
    let value = transform(layer)
    let content = contentSize(layer)
    let canvas = composition.canvasSize
    return Rectangle().fill(.clear)
      .overlay {
        if composition.selection == layer {
          Rectangle().stroke(.white.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [4]))
        }
      }
      .frame(width: content.width * value.scale * displayScale,
        height: content.height * value.scale * displayScale)
      .contentShape(Rectangle())
      .position(x: value.center.x * canvas.width * displayScale,
        y: value.center.y * canvas.height * displayScale)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("\(layer.rawValue) overlay")
      .accessibilityValue(String(format: "x %.2f y %.2f scale %.2f", value.center.x, value.center.y, value.scale))
      .accessibilityAddTraits(.isButton)
      .accessibilityAction { composition.selection = layer }
      .accessibilityHint("Select to use the position and size controls below")
      .accessibilityIdentifier("photo.\(layer.rawValue.lowercased())Overlay")
  }

  private func layer(at point: CGPoint, displayScale: CGFloat) -> RunPhotoLayer? {
    composition.layer(at: CGPoint(x: point.x / displayScale, y: point.y / displayScale))
  }

  private func canvasDrag(displayScale: CGFloat) -> some Gesture {
    DragGesture(minimumDistance: 2, coordinateSpace: .named("photo.canvas"))
      .onChanged { event in
        let canvas = composition.canvasSize
        if composition.selection == .photo {
          if cropStart == nil { cropStart = composition.crop }
          guard let origin = cropStart else { return }
          let frame = composition.crop.imageFrame(image: composition.imageSize, canvas: canvas)
          let dx = (frame.width - canvas.width) / 2, dy = (frame.height - canvas.height) / 2
          composition.crop.offset = CGPoint(
            x: dx > 0.01 ? min(1, max(-1, origin.offset.x + event.translation.width / (dx * displayScale))) : 0,
            y: dy > 0.01 ? min(1, max(-1, origin.offset.y + event.translation.height / (dy * displayScale))) : 0)
          edited()
        } else {
          if dragStart == nil {
            dragLayer = layer(at: event.startLocation, displayScale: displayScale)
            if let dragLayer {
              composition.selection = dragLayer
              dragStart = transform(dragLayer)
            }
          }
          guard let dragLayer, let origin = dragStart else { return }
          var next = transform(dragLayer)
          next.center = CGPoint(x: origin.center.x + event.translation.width / (canvas.width * displayScale),
            y: origin.center.y + event.translation.height / (canvas.height * displayScale))
          setTransform(next, layer: dragLayer)
        }
      }.onEnded { _ in dragStart = nil; dragLayer = nil; cropStart = nil }
  }
  private var canvasMagnification: some Gesture {
    MagnifyGesture().onChanged { event in
      if composition.selection == .photo {
        if cropPinchStart == nil { cropPinchStart = composition.crop.zoom }
        composition.crop.zoom = min(4, max(1, (cropPinchStart ?? 1) * event.magnification))
        edited()
      } else {
        let selected = composition.selection
        if pinchStart == nil { pinchStart = transform(selected).scale }
        var next = transform(selected)
        next.scale = (pinchStart ?? next.scale) * event.magnification
        setTransform(next, layer: selected)
      }
    }.onEnded { _ in cropPinchStart = nil; pinchStart = nil }
  }

  private func edited() { hasUnexportedChanges = true }
  private func choosePhoto() {
    permissionDenied = false
    retryExport = nil
    #if DEBUG
      if AppRuntime.useFixturePhotos { loadFixture(); return }
    #endif
    // Clearing selection permits retrying the same asset after cancellation or failure.
    pickerItem = nil
    pickerVisible = true
  }
  private func loadPhoto(_ item: PhotosPickerItem) {
    loadTask?.cancel()
    let request = UUID()
    loadID = request
    loading = true
    permissionDenied = false
    retryExport = nil
    loadTask = Task {
      do {
        let image = try await RunPhotoIO.load(item)
        try Task.checkCancellation()
        guard loadID == request else { return }
        acceptImage(image)
        loading = false
      } catch {
        guard loadID == request, !Task.isCancelled else { return }
        loading = false
        errorMessage = error.localizedDescription
      }
    }
  }
  private func acceptImage(_ image: UIImage) {
    let first = composition.image == nil
    composition.image = image
    composition.crop = RunPhotoCrop()
    if first { composition.resetLayout() } else { composition.constrainOverlays() }
    edited()
  }
  private func export(share: Bool) {
    exporting = true
    retryExport = share
    permissionDenied = false
    Task { @MainActor in
      defer { exporting = false }
      do {
        // Let the busy state render before rasterizing the artwork.
        await Task.yield()
        let data = try RunPhotoIO.render(composition, stats: stats, route: route)
        #if DEBUG
          if AppRuntime.useFixturePhotos {
            if AppRuntime.scenario == "photo-save-denied" && !share { throw RunPhotoError.permissionDenied }
            if !share { finish(.saved(data)); return }
          }
        #endif
        if share {
          cleanShareFile()
          shareCompleted = false
          shareError = nil
          shareURL = try RunPhotoIO.shareFile(data)
          shareVisible = true
        } else {
          try await RunPhotoIO.save(data)
          finish(.saved(data))
        }
      } catch {
        retryExport = share
        permissionDenied = (error as? RunPhotoError) == .permissionDenied
        errorMessage = error.localizedDescription
      }
    }
  }
  private func finish(_ result: RunPhotoExportResult) {
    hasUnexportedChanges = false
    onExport(result)
    dismiss()
  }
  private func shareDismissed() {
    cleanShareFile()
    if shareCompleted { finish(.shared) }
    else if let shareError { errorMessage = shareError }
    shareCompleted = false
    shareError = nil
  }
  private func cleanShareFile() {
    if let shareURL { RunPhotoIO.removeShareFile(shareURL) }
    shareURL = nil
  }

  #if DEBUG
    private func loadFixture() {
      fixtureAttempts += 1
      if AppRuntime.scenario == "photo-load-failure" && fixtureAttempts == 1 {
        errorMessage = RunPhotoError.unreadable.localizedDescription
        return
      }
      let format = UIGraphicsImageRendererFormat()
      format.scale = 1
      let image = UIGraphicsImageRenderer(size: CGSize(width: 900, height: 1200), format: format).image { context in
        UIColor(red: 0.13, green: 0.24, blue: 0.30, alpha: 1).setFill()
        context.fill(CGRect(x: 0, y: 0, width: 900, height: 1200))
        UIColor(red: 0.28, green: 0.39, blue: 0.30, alpha: 1).setFill()
        context.fill(CGRect(x: 0, y: 650, width: 900, height: 550))
        UIColor(red: 0.6, green: 0.59, blue: 0.53, alpha: 1).setFill()
        let path = UIBezierPath()
        path.move(to: CGPoint(x: 420, y: 650)); path.addLine(to: CGPoint(x: 480, y: 650))
        path.addLine(to: CGPoint(x: 850, y: 1200)); path.addLine(to: CGPoint(x: 50, y: 1200))
        path.close(); path.fill()
      }
      acceptImage(image)
    }
  #endif
}

struct RunPhotoSharePresentation: View {
  let url: URL
  let completion: @MainActor (Bool, Error?) -> Void
  var body: some View {
    #if DEBUG
      if AppRuntime.useFixturePhotos {
        NavigationStack {
          VStack(spacing: 24) {
            Text("Fixture share destination").font(.headline)
            Button("Complete sharing") { completion(true, nil) }
              .accessibilityIdentifier("photo.fixtureShare.complete")
            Button("Cancel", role: .cancel) { completion(false, nil) }
              .accessibilityIdentifier("photo.fixtureShare.cancel")
            Button("Fail sharing") { completion(false, RunPhotoError.sharingFailed) }
              .accessibilityIdentifier("photo.fixtureShare.fail")
          }.navigationTitle("Share Image")
        }
      } else { RunPhotoShareSheet(url: url, completion: completion) }
    #else
      RunPhotoShareSheet(url: url, completion: completion)
    #endif
  }
}

/// Receipts belong to the presenting screen so they appear after the editor closes.
struct RunPhotoExportFeedback: ViewModifier {
  @Binding var result: RunPhotoExportResult?
  @State private var shareURL: URL?
  @State private var shareVisible = false
  @State private var pendingResult: RunPhotoExportResult?

  func body(content: Content) -> some View {
    content
      .alert(result?.title ?? "", isPresented: Binding(
        get: { result != nil }, set: { if !$0 { result = nil } })) {
        if case .saved(let data) = result {
          Button("Share Image") { share(data) }
        }
        Button("OK", role: .cancel) { result = nil }
      } message: { Text(result?.message ?? "") }
      .sheet(isPresented: $shareVisible, onDismiss: shareDismissed) {
        if let shareURL {
          RunPhotoSharePresentation(url: shareURL) { completed, error in
            if let error { pendingResult = .failed(error.localizedDescription) }
            else if completed { pendingResult = .shared }
            shareVisible = false
          }
        }
      }
      .onDisappear { if !shareVisible { cleanShareFile() } }
  }

  private func share(_ data: Data) {
    result = nil
    pendingResult = nil
    do {
      shareURL = try RunPhotoIO.shareFile(data)
      shareVisible = true
    } catch { result = .failed(error.localizedDescription) }
  }
  private func shareDismissed() {
    cleanShareFile()
    result = pendingResult
    pendingResult = nil
  }
  private func cleanShareFile() {
    if let shareURL { RunPhotoIO.removeShareFile(shareURL) }
    shareURL = nil
  }
}
