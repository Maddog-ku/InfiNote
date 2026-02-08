//
//  PencilInkCanvasView.swift
//  InfiNote
//

import UIKit

final class PencilInkCanvasView: UIView, UIGestureRecognizerDelegate {
    var backgroundTemplate: CanvasBackgroundTemplate = .lines {
        didSet { setNeedsDisplay() }
    }

    private var camera = CanvasCamera()
    private var initializedCamera = false

    private var strokes: [CanvasStroke] = []
    private var textBoxes: [CanvasTextBox] = []
    private var pdfLayer: CanvasPDFPageLayer?
    private var cachedPDFDocumentURL: URL?
    private var cachedPDFDocument: CGPDFDocument?
    private weak var activePencilTouch: UITouch?
    private var activePoints: [CanvasStrokePoint] = []
    private var predictedPoints: [CanvasStrokePoint] = []
    private var activeEstimatedLookup: [NSNumber: Int] = [:]
    private var activeStrokeStartTimestamp: TimeInterval?
    private var eraserMode: EraserMode = .stroke
    private var eraserSize: CGFloat = 20
    private var eraserEnabled = false
    private var lassoEnabled = false
    private var textToolEnabled = false
    private var lassoPoints: [CanvasStrokePoint] = []
    private var activeSelection: SelectionGroup?
    private var selectedTextBoxID: UUID?
    private var draggingTextBoxID: UUID?
    private var textDragOffset: CGPoint = .zero
    private var activeTextStyle: CanvasTextStyle = .default
    private var activeTextContent: String = "Text"

    private let spatialCellSize: CGFloat = 256
    private var strokeBuckets: [SpatialKey: Set<UUID>] = [:]
    private var textBuckets: [SpatialKey: Set<UUID>] = [:]
    private var strokeIndexByID: [UUID: Int] = [:]
    private var textIndexByID: [UUID: Int] = [:]

    private var panGesture: UIPanGestureRecognizer!
    private var pinchGesture: UIPinchGestureRecognizer!
    private let autosaveStore = CanvasAutosaveStore.shared

    private var activeStyle = CanvasStrokeStyle(
        tool: .pen,
        color: .black,
        width: 2.2,
        opacity: 1
    )

    private struct SpatialKey: Hashable {
        var x: Int
        var y: Int
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        configureView()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureView()
    }

    override class var layerClass: AnyClass {
        CATiledLayer.self
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        if !initializedCamera, bounds.width > 0, bounds.height > 0 {
            if pdfLayer != nil {
                fitCameraToPDFIfNeeded()
            } else {
                camera.translation = CGPoint(x: bounds.midX, y: bounds.midY)
            }
            initializedCamera = true
        }
    }

    func clear() {
        strokes.removeAll(keepingCapacity: true)
        textBoxes.removeAll(keepingCapacity: true)
        activePoints.removeAll(keepingCapacity: true)
        predictedPoints.removeAll(keepingCapacity: true)
        activeEstimatedLookup.removeAll(keepingCapacity: true)
        activeStrokeStartTimestamp = nil
        activePencilTouch = nil
        lassoPoints.removeAll(keepingCapacity: true)
        activeSelection = nil
        selectedTextBoxID = nil
        draggingTextBoxID = nil
        rebuildSpatialIndex()
        setNeedsDisplay()
        scheduleAutosave()
    }

    func setPDFLayer(_ layer: CanvasPDFPageLayer?) {
        pdfLayer = layer
        fitCameraToPDFIfNeeded()
        setNeedsDisplay()
    }

    func setPageAnnotations(_ annotations: CanvasPageAnnotations) {
        strokes = annotations.strokes
        textBoxes = annotations.textBoxes
        activeSelection = nil
        selectedTextBoxID = nil
        draggingTextBoxID = nil
        activePoints.removeAll(keepingCapacity: true)
        predictedPoints.removeAll(keepingCapacity: true)
        lassoPoints.removeAll(keepingCapacity: true)
        rebuildSpatialIndex()
        setNeedsDisplay()
        scheduleAutosave()
    }

    func currentPageAnnotations() -> CanvasPageAnnotations {
        CanvasPageAnnotations(strokes: strokes, textBoxes: textBoxes)
    }

    func setActiveBrush(tool: InkTool, color: UIColor, width: CGFloat, opacity: CGFloat) {
        eraserEnabled = false
        lassoEnabled = false
        textToolEnabled = false
        activeStyle.tool = tool
        activeStyle.color = StrokeColor(color)
        activeStyle.width = Float(max(0.5, min(40, width)))
        activeStyle.opacity = Float(max(0.05, min(1, opacity)))
    }

    func setEraser(mode: EraserMode, size: CGFloat) {
        eraserEnabled = true
        lassoEnabled = false
        textToolEnabled = false
        eraserMode = mode
        eraserSize = max(4, min(80, size))
        predictedPoints.removeAll(keepingCapacity: true)
        activePoints.removeAll(keepingCapacity: true)
        lassoPoints.removeAll(keepingCapacity: true)
        activeSelection = nil
        activeEstimatedLookup.removeAll(keepingCapacity: true)
        activeStrokeStartTimestamp = nil
    }

    func setLassoEnabled(_ enabled: Bool) {
        lassoEnabled = enabled
        eraserEnabled = false
        textToolEnabled = false
        predictedPoints.removeAll(keepingCapacity: true)
        activePoints.removeAll(keepingCapacity: true)
        activeEstimatedLookup.removeAll(keepingCapacity: true)
        activeStrokeStartTimestamp = nil
        if !enabled {
            lassoPoints.removeAll(keepingCapacity: true)
            activeSelection = nil
        }
        setNeedsDisplay()
    }

    func setTextToolEnabled(_ enabled: Bool) {
        textToolEnabled = enabled
        eraserEnabled = false
        lassoEnabled = false
        activePoints.removeAll(keepingCapacity: true)
        predictedPoints.removeAll(keepingCapacity: true)
        activeEstimatedLookup.removeAll(keepingCapacity: true)
        activeStrokeStartTimestamp = nil
        if !enabled {
            draggingTextBoxID = nil
        }
        setNeedsDisplay()
    }

    func setActiveTextStyle(fontPostScriptName: String, fontSize: CGFloat, color: UIColor) {
        activeTextStyle.fontPostScriptName = fontPostScriptName
        activeTextStyle.fontSize = Float(max(8, min(180, fontSize)))
        activeTextStyle.color = StrokeColor(color)
        guard let selectedID = selectedTextBoxID,
              let index = textIndexByID[selectedID] else {
            return
        }
        textBoxes[index].style = activeTextStyle
        textBoxes[index].updatedAtMillis = nowMillis()
        rebuildSpatialIndex()
        setNeedsDisplay()
        scheduleAutosave()
    }

    func setActiveTextContent(_ text: String) {
        activeTextContent = text.isEmpty ? "Text" : text
        guard let selectedID = selectedTextBoxID,
              let index = textIndexByID[selectedID] else {
            return
        }
        textBoxes[index].text = activeTextContent
        textBoxes[index].updatedAtMillis = nowMillis()
        setNeedsDisplay()
    }

    func insertTextBoxAtViewportCenter() {
        let world = camera.viewToWorld(CGPoint(x: bounds.midX, y: bounds.midY))
        createTextBox(at: world)
    }

    func exportVisibleContentPDF() throws -> CanvasPDFExportResult {
        let contentRect = contentBounds().insetBy(dx: -32, dy: -32)
        return try CanvasPDFExporter().export(
            strokes: strokes.filter { !$0.isDeleted },
            textBoxes: textBoxes,
            worldRect: contentRect.isNull ? CGRect(x: 0, y: 0, width: 1024, height: 768) : contentRect
        )
    }

    func setTextBoxes(_ boxes: [CanvasTextBox]) {
        textBoxes = boxes
        if let selectedTextBoxID, !boxes.contains(where: { $0.id == selectedTextBoxID }) {
            self.selectedTextBoxID = nil
        }
        rebuildSpatialIndex()
        setNeedsDisplay()
        scheduleAutosave()
    }

    func moveSelection(byViewTranslation delta: CGSize) {
        guard var selection = activeSelection else { return }
        let worldDelta = CGSize(width: delta.width / max(0.01, camera.scale), height: delta.height / max(0.01, camera.scale))
        let dx = Float(worldDelta.width)
        let dy = Float(worldDelta.height)

        for strokeID in selection.strokeIDs {
            guard let index = strokeIndexByID[strokeID] else { continue }
            for pIndex in strokes[index].points.indices {
                strokes[index].points[pIndex].x += dx
                strokes[index].points[pIndex].y += dy
            }
            strokes[index].bounds = boundsFor(points: strokes[index].points)
            strokes[index].updatedAtMillis = nowMillis()
            strokes[index].revision += 1
        }

        for textID in selection.textBoxIDs {
            guard let index = textIndexByID[textID] else { continue }
            textBoxes[index].frame.minX += dx
            textBoxes[index].frame.maxX += dx
            textBoxes[index].frame.minY += dy
            textBoxes[index].frame.maxY += dy
            textBoxes[index].updatedAtMillis = nowMillis()
        }

        for pIndex in selection.lasso.points.indices {
            selection.lasso.points[pIndex].x += dx
            selection.lasso.points[pIndex].y += dy
        }
        selection.bounds = selectionBounds(from: selection)
        activeSelection = selection
        rebuildSpatialIndex()
        setNeedsDisplay()
        scheduleAutosave()
    }

    func scaleSelection(aroundViewPoint anchor: CGPoint, scale: CGFloat) {
        guard var selection = activeSelection else { return }
        let clampedScale = max(0.3, min(3, scale))
        let anchorWorld = camera.viewToWorld(anchor)

        for strokeID in selection.strokeIDs {
            guard let index = strokeIndexByID[strokeID] else { continue }
            for pIndex in strokes[index].points.indices {
                let original = strokes[index].points[pIndex]
                strokes[index].points[pIndex].x = Float(anchorWorld.x) + (original.x - Float(anchorWorld.x)) * Float(clampedScale)
                strokes[index].points[pIndex].y = Float(anchorWorld.y) + (original.y - Float(anchorWorld.y)) * Float(clampedScale)
            }
            strokes[index].bounds = boundsFor(points: strokes[index].points)
            strokes[index].updatedAtMillis = nowMillis()
            strokes[index].revision += 1
        }

        for textID in selection.textBoxIDs {
            guard let index = textIndexByID[textID] else { continue }
            let original = textBoxes[index].frame
            textBoxes[index].frame = StrokeBounds(
                minX: Float(anchorWorld.x) + (original.minX - Float(anchorWorld.x)) * Float(clampedScale),
                minY: Float(anchorWorld.y) + (original.minY - Float(anchorWorld.y)) * Float(clampedScale),
                maxX: Float(anchorWorld.x) + (original.maxX - Float(anchorWorld.x)) * Float(clampedScale),
                maxY: Float(anchorWorld.y) + (original.maxY - Float(anchorWorld.y)) * Float(clampedScale)
            )
            textBoxes[index].updatedAtMillis = nowMillis()
        }

        for pIndex in selection.lasso.points.indices {
            let original = selection.lasso.points[pIndex]
            selection.lasso.points[pIndex].x = Float(anchorWorld.x) + (original.x - Float(anchorWorld.x)) * Float(clampedScale)
            selection.lasso.points[pIndex].y = Float(anchorWorld.y) + (original.y - Float(anchorWorld.y)) * Float(clampedScale)
        }
        selection.bounds = selectionBounds(from: selection)
        activeSelection = selection
        rebuildSpatialIndex()
        setNeedsDisplay()
        scheduleAutosave()
    }

    func deleteSelection() {
        guard activeSelection != nil else { return }
        if let selection = activeSelection {
            let deleteIDs = selection.strokeIDs
            strokes.removeAll { deleteIDs.contains($0.id) }
            let deleteTextIDs = selection.textBoxIDs
            textBoxes.removeAll { deleteTextIDs.contains($0.id) }
            if let selected = selectedTextBoxID, deleteTextIDs.contains(selected) {
                selectedTextBoxID = nil
            }
        }
        activeSelection = nil
        lassoPoints.removeAll(keepingCapacity: true)
        rebuildSpatialIndex()
        setNeedsDisplay()
        scheduleAutosave()
    }

    func mergeSelection() {
        guard let selection = activeSelection else { return }
        let selected = strokes.filter { selection.strokeIDs.contains($0.id) && !$0.isDeleted }
            .sorted { $0.createdAtMillis < $1.createdAtMillis }
        guard selected.count >= 2 else { return }

        var mergedPoints: [CanvasStrokePoint] = []
        mergedPoints.reserveCapacity(selected.reduce(0) { $0 + $1.points.count + 1 })
        for (idx, stroke) in selected.enumerated() {
            if idx > 0, let last = mergedPoints.last {
                mergedPoints.append(CanvasStrokePoint(
                    x: last.x,
                    y: last.y,
                    time: last.time,
                    pressure: last.pressure,
                    azimuth: last.azimuth,
                    altitude: last.altitude
                ))
            }
            mergedPoints.append(contentsOf: stroke.points)
        }
        guard mergedPoints.count >= 2 else { return }

        let mergedStroke = CanvasStroke(
            id: UUID(),
            style: selected[0].style,
            points: mergedPoints,
            bounds: boundsFor(points: mergedPoints),
            isDeleted: false,
            erasedSpans: [],
            createdAtMillis: nowMillis(),
            updatedAtMillis: nowMillis(),
            revision: 1
        )
        let mergedIDs = Set(selected.map(\.id))
        strokes.removeAll { mergedIDs.contains($0.id) }
        strokes.append(mergedStroke)

        activeSelection = SelectionGroup(
            id: UUID(),
            strokeIDs: Set([mergedStroke.id]),
            textBoxIDs: selection.textBoxIDs,
            lasso: LassoPolygon(points: lassoPoints),
            bounds: selectionBounds(strokeIDs: Set([mergedStroke.id]), textBoxIDs: selection.textBoxIDs)
        )
        rebuildSpatialIndex()
        setNeedsDisplay()
        scheduleAutosave()
    }

    private func configureView() {
        isMultipleTouchEnabled = true
        backgroundColor = .systemBackground
        contentScaleFactor = traitCollection.displayScale

        if let tiledLayer = layer as? CATiledLayer {
            tiledLayer.levelsOfDetail = 4
            tiledLayer.levelsOfDetailBias = 4
            tiledLayer.tileSize = CGSize(width: 512, height: 512)
        }

        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.maximumNumberOfTouches = 2
        panGesture.delegate = self
        addGestureRecognizer(panGesture)

        pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinchGesture.delegate = self
        addGestureRecognizer(pinchGesture)

        Task { [weak self] in
            guard let self else { return }
            guard self.strokes.isEmpty, self.textBoxes.isEmpty else { return }
            if let restored = await self.autosaveStore.loadLatest(),
               (!restored.strokes.isEmpty || !restored.textBoxes.isEmpty) {
                self.strokes = restored.strokes
                self.textBoxes = restored.textBoxes
                self.rebuildSpatialIndex()
                self.setNeedsDisplay()
            }
        }
    }

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        let delta = recognizer.translation(in: self)
        camera.translation = CGPoint(x: camera.translation.x + delta.x, y: camera.translation.y + delta.y)
        recognizer.setTranslation(.zero, in: self)
        setNeedsDisplay()
    }

    @objc private func handlePinch(_ recognizer: UIPinchGestureRecognizer) {
        let anchorViewPoint = recognizer.location(in: self)
        let anchorWorldPoint = camera.viewToWorld(anchorViewPoint)

        camera.updateScale(multiplier: recognizer.scale)
        recognizer.scale = 1

        camera.translation = CGPoint(
            x: anchorViewPoint.x - anchorWorldPoint.x * camera.scale,
            y: anchorViewPoint.y - anchorWorldPoint.y * camera.scale
        )

        setNeedsDisplay()
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        touch.type != .pencil
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activePencilTouch == nil,
              let touch = touches.first(where: { $0.type == .pencil }),
              let event else {
            return
        }

        activePencilTouch = touch
        if textToolEnabled {
            handleTextTouchBegan(touch)
        } else if lassoEnabled {
            lassoPoints.removeAll(keepingCapacity: true)
            activeSelection = nil
            appendLassoPoints(from: event.coalescedTouches(for: touch) ?? [touch])
        } else if eraserEnabled {
            applyEraser(for: event.coalescedTouches(for: touch) ?? [touch])
        } else {
            activePoints.removeAll(keepingCapacity: true)
            predictedPoints.removeAll(keepingCapacity: true)
            activeEstimatedLookup.removeAll(keepingCapacity: true)
            activeStrokeStartTimestamp = touch.timestamp

            appendCommittedPoints(from: event.coalescedTouches(for: touch) ?? [touch])
            rebuildPredictedPoints(from: touch, event: event)
        }
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let activeTouch = activePencilTouch,
              touches.contains(activeTouch),
              let event else {
            return
        }

        if textToolEnabled {
            handleTextTouchMoved(activeTouch)
        } else if lassoEnabled {
            appendLassoPoints(from: event.coalescedTouches(for: activeTouch) ?? [activeTouch])
        } else if eraserEnabled {
            applyEraser(for: event.coalescedTouches(for: activeTouch) ?? [activeTouch])
        } else {
            appendCommittedPoints(from: event.coalescedTouches(for: activeTouch) ?? [activeTouch])
            rebuildPredictedPoints(from: activeTouch, event: event)
        }
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let activeTouch = activePencilTouch,
              touches.contains(activeTouch) else {
            return
        }

        if let event {
            if textToolEnabled {
                handleTextTouchMoved(activeTouch)
            } else if lassoEnabled {
                appendLassoPoints(from: event.coalescedTouches(for: activeTouch) ?? [activeTouch])
            } else if eraserEnabled {
                applyEraser(for: event.coalescedTouches(for: activeTouch) ?? [activeTouch])
            } else {
                appendCommittedPoints(from: event.coalescedTouches(for: activeTouch) ?? [activeTouch])
            }
        }

        if textToolEnabled {
            draggingTextBoxID = nil
        } else if lassoEnabled {
            commitLassoSelection()
        } else if !eraserEnabled {
            commitActiveStroke()
        }
        predictedPoints.removeAll(keepingCapacity: true)
        activePencilTouch = nil
        activeStrokeStartTimestamp = nil
        setNeedsDisplay()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let activeTouch = activePencilTouch,
              touches.contains(activeTouch) else {
            return
        }

        activePoints.removeAll(keepingCapacity: true)
        predictedPoints.removeAll(keepingCapacity: true)
        activeEstimatedLookup.removeAll(keepingCapacity: true)
        lassoPoints.removeAll(keepingCapacity: true)
        draggingTextBoxID = nil
        activePencilTouch = nil
        activeStrokeStartTimestamp = nil
        setNeedsDisplay()
    }

    override func touchesEstimatedPropertiesUpdated(_ touches: Set<UITouch>) {
        guard !eraserEnabled, !lassoEnabled, !textToolEnabled, activePencilTouch != nil else { return }

        for touch in touches where touch.type == .pencil {
            guard let indexNumber = touch.estimationUpdateIndex,
                  let sampleIndex = activeEstimatedLookup[indexNumber],
                  activePoints.indices.contains(sampleIndex) else {
                continue
            }
            activePoints[sampleIndex] = makePoint(from: touch)
        }

        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }

        context.setFillColor(UIColor.systemBackground.cgColor)
        context.fill(bounds)

        let visibleWorldRect = worldVisibleRect()
        drawBackground(in: context, visibleWorldRect: visibleWorldRect)
        drawPDFLayer(in: context, visibleWorldRect: visibleWorldRect)
        drawCommittedStrokes(in: context, visibleWorldRect: visibleWorldRect)
        drawTextBoxes(in: context, visibleWorldRect: visibleWorldRect)
        drawActiveStroke(in: context)
        drawLassoOverlay(in: context)
        drawSelectionOverlay(in: context)
    }

    private func worldVisibleRect() -> CGRect {
        let topLeft = camera.viewToWorld(bounds.origin)
        let bottomRight = camera.viewToWorld(CGPoint(x: bounds.maxX, y: bounds.maxY))
        return CGRect(
            x: min(topLeft.x, bottomRight.x),
            y: min(topLeft.y, bottomRight.y),
            width: abs(bottomRight.x - topLeft.x),
            height: abs(bottomRight.y - topLeft.y)
        )
    }

    private func drawBackground(in context: CGContext, visibleWorldRect: CGRect) {
        let baseStep: CGFloat = 32
        let step = adaptiveStep(baseWorldStep: baseStep)
        let minX = floor(visibleWorldRect.minX / step) * step
        let maxX = ceil(visibleWorldRect.maxX / step) * step
        let minY = floor(visibleWorldRect.minY / step) * step
        let maxY = ceil(visibleWorldRect.maxY / step) * step

        context.saveGState()
        context.setLineWidth(1)

        switch backgroundTemplate {
        case .lines:
            context.setStrokeColor(UIColor.systemGray5.cgColor)
            var y = minY
            while y <= maxY {
                let from = camera.worldToView(CGPoint(x: minX, y: y))
                let to = camera.worldToView(CGPoint(x: maxX, y: y))
                context.move(to: from)
                context.addLine(to: to)
                y += step
            }
            context.strokePath()

        case .grid:
            context.setStrokeColor(UIColor.systemGray5.cgColor)
            var x = minX
            while x <= maxX {
                let from = camera.worldToView(CGPoint(x: x, y: minY))
                let to = camera.worldToView(CGPoint(x: x, y: maxY))
                context.move(to: from)
                context.addLine(to: to)
                x += step
            }

            var y = minY
            while y <= maxY {
                let from = camera.worldToView(CGPoint(x: minX, y: y))
                let to = camera.worldToView(CGPoint(x: maxX, y: y))
                context.move(to: from)
                context.addLine(to: to)
                y += step
            }
            context.strokePath()

        case .dots:
            context.setFillColor(UIColor.systemGray4.cgColor)
            let radius: CGFloat = 1.2

            var x = minX
            while x <= maxX {
                var y = minY
                while y <= maxY {
                    let p = camera.worldToView(CGPoint(x: x, y: y))
                    context.fillEllipse(in: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2))
                    y += step
                }
                x += step
            }
        }

        context.restoreGState()
    }

    private func drawPDFLayer(in context: CGContext, visibleWorldRect: CGRect) {
        guard let layer = pdfLayer else { return }
        let worldRect = layer.worldRect
        guard worldRect.intersects(visibleWorldRect) else { return }
        guard let document = pdfDocument(for: layer.sourceFileURL),
              let page = document.page(at: layer.pageIndex + 1) else {
            return
        }

        let topLeft = camera.worldToView(worldRect.origin)
        let bottomRight = camera.worldToView(CGPoint(x: worldRect.maxX, y: worldRect.maxY))
        let viewRect = CGRect(
            x: min(topLeft.x, bottomRight.x),
            y: min(topLeft.y, bottomRight.y),
            width: abs(bottomRight.x - topLeft.x),
            height: abs(bottomRight.y - topLeft.y)
        )
        guard viewRect.width > 0.5, viewRect.height > 0.5 else { return }

        context.saveGState()
        context.interpolationQuality = .high
        context.setFillColor(UIColor.white.cgColor)
        context.fill(viewRect)
        context.translateBy(x: viewRect.minX, y: viewRect.minY)
        context.scaleBy(x: viewRect.width / layer.pageWidth, y: viewRect.height / layer.pageHeight)
        // CGPDFPage draws in bottom-left coordinate space.
        context.translateBy(x: 0, y: layer.pageHeight)
        context.scaleBy(x: 1, y: -1)
        context.drawPDFPage(page)
        context.restoreGState()
    }

    private func adaptiveStep(baseWorldStep: CGFloat) -> CGFloat {
        var step = baseWorldStep
        var screenStep = step * camera.scale

        while screenStep < 18 {
            step *= 2
            screenStep = step * camera.scale
        }

        while screenStep > 120 {
            step *= 0.5
            screenStep = step * camera.scale
        }

        return step
    }

    private func drawCommittedStrokes(in context: CGContext, visibleWorldRect: CGRect) {
        let paddedVisibleRect = visibleWorldRect.insetBy(dx: -40 / camera.scale, dy: -40 / camera.scale)

        for stroke in strokes where !stroke.isDeleted && stroke.bounds.cgRect.intersects(paddedVisibleRect) {
            draw(stroke: stroke, in: context, predicted: false)
        }
    }

    private func drawTextBoxes(in context: CGContext, visibleWorldRect: CGRect) {
        let paddedVisibleRect = visibleWorldRect.insetBy(dx: -20 / camera.scale, dy: -20 / camera.scale)
        context.saveGState()
        for box in textBoxes.sorted(by: { $0.zIndex < $1.zIndex }) where box.frame.cgRect.intersects(paddedVisibleRect) {
            let rect = box.frame.cgRect
            let topLeft = camera.worldToView(rect.origin)
            let bottomRight = camera.worldToView(CGPoint(x: rect.maxX, y: rect.maxY))
            let viewRect = CGRect(
                x: min(topLeft.x, bottomRight.x),
                y: min(topLeft.y, bottomRight.y),
                width: abs(bottomRight.x - topLeft.x),
                height: abs(bottomRight.y - topLeft.y)
            )
            let isSelected = box.id == selectedTextBoxID
            context.setStrokeColor((isSelected ? UIColor.systemBlue : UIColor.systemGray3).cgColor)
            context.setLineWidth(isSelected ? 1.8 : 1)
            if isSelected {
                context.setLineDash(phase: 0, lengths: [6, 4])
            } else {
                context.setLineDash(phase: 0, lengths: [])
            }
            context.stroke(viewRect)

            let baseFont = FontRegistry.shared.uiFont(
                postScriptName: box.style.fontPostScriptName,
                size: CGFloat(box.style.fontSize)
            ) ?? UIFont.systemFont(ofSize: CGFloat(box.style.fontSize))
            let attrs: [NSAttributedString.Key: Any] = [
                .font: baseFont,
                .foregroundColor: box.style.color.uiColor
            ]
            (box.text as NSString).draw(in: viewRect.insetBy(dx: 6, dy: 4), withAttributes: attrs)
        }
        context.restoreGState()
    }

    private func drawActiveStroke(in context: CGContext) {
        guard !eraserEnabled, !textToolEnabled else { return }
        guard !activePoints.isEmpty else { return }

        let activeStroke = CanvasStroke(
            id: UUID(),
            style: activeStyle,
            points: activePoints,
            bounds: boundsFor(points: activePoints),
            isDeleted: false,
            erasedSpans: [],
            createdAtMillis: nowMillis(),
            updatedAtMillis: nowMillis(),
            revision: 1
        )
        draw(stroke: activeStroke, in: context, predicted: false)

        guard !predictedPoints.isEmpty else { return }
        let predictedStroke = CanvasStroke(
            id: UUID(),
            style: activeStyle,
            points: [activePoints.last!] + predictedPoints,
            bounds: boundsFor(points: [activePoints.last!] + predictedPoints),
            isDeleted: false,
            erasedSpans: [],
            createdAtMillis: nowMillis(),
            updatedAtMillis: nowMillis(),
            revision: 1
        )
        draw(stroke: predictedStroke, in: context, predicted: true)
    }

    private func draw(stroke: CanvasStroke, in context: CGContext, predicted: Bool) {
        BrushRenderer.drawStroke(
            stroke,
            in: context,
            toView: { camera.worldToView($0) },
            predicted: predicted,
            cameraScale: camera.scale
        )
    }

    private func drawLassoOverlay(in context: CGContext) {
        guard lassoEnabled, lassoPoints.count >= 2 else { return }
        context.saveGState()
        context.setLineWidth(1.5)
        context.setStrokeColor(UIColor.systemBlue.withAlphaComponent(0.9).cgColor)
        context.setLineDash(phase: 0, lengths: [6, 4])

        let first = camera.worldToView(lassoPoints[0].cgPoint)
        context.move(to: first)
        for point in lassoPoints.dropFirst() {
            context.addLine(to: camera.worldToView(point.cgPoint))
        }
        context.strokePath()
        context.restoreGState()
    }

    private func drawSelectionOverlay(in context: CGContext) {
        guard let selection = activeSelection, !selection.isEmpty else { return }
        let rect = selection.bounds.cgRect
        guard rect.width > 0, rect.height > 0 else { return }
        let topLeft = camera.worldToView(rect.origin)
        let bottomRight = camera.worldToView(CGPoint(x: rect.maxX, y: rect.maxY))
        let viewRect = CGRect(
            x: min(topLeft.x, bottomRight.x),
            y: min(topLeft.y, bottomRight.y),
            width: abs(bottomRight.x - topLeft.x),
            height: abs(bottomRight.y - topLeft.y)
        )

        context.saveGState()
        context.setStrokeColor(UIColor.systemBlue.cgColor)
        context.setLineWidth(1.5)
        context.setLineDash(phase: 0, lengths: [8, 4])
        context.stroke(viewRect)
        context.restoreGState()
    }

    private func appendCommittedPoints(from touches: [UITouch]) {
        for touch in touches {
            let point = makePoint(from: touch)
            activePoints.append(point)

            if let estimationIndex = touch.estimationUpdateIndex {
                activeEstimatedLookup[estimationIndex] = activePoints.count - 1
            }
        }
    }

    private func rebuildPredictedPoints(from touch: UITouch, event: UIEvent) {
        predictedPoints = (event.predictedTouches(for: touch) ?? []).map { makePoint(from: $0) }
    }

    private func makePoint(from touch: UITouch) -> CanvasStrokePoint {
        let world = camera.viewToWorld(touch.location(in: self))
        let normalizedPressure = normalizedPressure(for: touch)
        let strokeStart = activeStrokeStartTimestamp ?? touch.timestamp
        let relativeTime = max(0, touch.timestamp - strokeStart)

        return CanvasStrokePoint(
            x: Float(world.x),
            y: Float(world.y),
            time: Float(relativeTime),
            pressure: Float(normalizedPressure),
            azimuth: Float(touch.azimuthAngle(in: self)),
            altitude: Float(touch.altitudeAngle)
        )
    }

    private func normalizedPressure(for touch: UITouch) -> CGFloat {
        guard touch.maximumPossibleForce > 0 else { return 0 }
        return max(0, min(1, touch.force / touch.maximumPossibleForce))
    }

    private func applyEraser(for touches: [UITouch]) {
        for touch in touches {
            erase(atWorldPoint: camera.viewToWorld(touch.location(in: self)))
        }
    }

    private func erase(atWorldPoint point: CGPoint) {
        let worldRadius = eraserSize / max(0.01, camera.scale)
        switch eraserMode {
        case .stroke:
            eraseByStroke(center: point, radius: worldRadius)
        case .segment:
            eraseBySegment(center: point, radius: worldRadius)
        }
    }

    private func eraseByStroke(center: CGPoint, radius: CGFloat) {
        let hitRect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        let now = nowMillis()
        var changed = false
        for index in strokes.indices {
            guard !strokes[index].isDeleted else { continue }
            guard strokes[index].bounds.cgRect.intersects(hitRect) else { continue }
            if strokeIntersectsCircle(strokes[index], center: center, radius: radius) {
                strokes[index].isDeleted = true
                strokes[index].updatedAtMillis = now
                strokes[index].revision += 1
                changed = true
            }
        }
        if changed {
            rebuildSpatialIndex()
            scheduleAutosave()
        }
    }

    private func eraseBySegment(center: CGPoint, radius: CGFloat) {
        var rebuilt: [CanvasStroke] = []
        rebuilt.reserveCapacity(strokes.count)

        for stroke in strokes where !stroke.isDeleted {
            let strokeRect = stroke.bounds.cgRect.insetBy(dx: -radius, dy: -radius)
            guard strokeRect.contains(center) || strokeRect.intersects(CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)) else {
                rebuilt.append(stroke)
                continue
            }

            let fragments = splitStrokeByCircle(stroke, center: center, radius: radius)
            rebuilt.append(contentsOf: fragments)
        }

        strokes = rebuilt
        rebuildSpatialIndex()
        scheduleAutosave()
    }

    private func splitStrokeByCircle(_ stroke: CanvasStroke, center: CGPoint, radius: CGFloat) -> [CanvasStroke] {
        let points = stroke.points
        guard points.count >= 2 else { return [] }

        var remove = Array(repeating: false, count: points.count)
        var hit = false

        for index in points.indices {
            if distance(points[index].cgPoint, center) <= radius {
                remove[index] = true
                hit = true
            }
        }

        if points.count > 1 {
            for index in 1..<points.count {
                let a = points[index - 1].cgPoint
                let b = points[index].cgPoint
                if segmentDistanceSquared(point: center, a: a, b: b) <= radius * radius {
                    remove[index - 1] = true
                    remove[index] = true
                    hit = true
                }
            }
        }

        guard hit else { return [stroke] }

        var ranges: [Range<Int>] = []
        var start: Int?
        for index in points.indices {
            if !remove[index] {
                start = start ?? index
            } else if let s = start {
                ranges.append(s..<index)
                start = nil
            }
        }
        if let s = start {
            ranges.append(s..<points.count)
        }

        let now = nowMillis()
        if ranges.isEmpty {
            return []
        }

        if ranges.count == 1, let range = ranges.first, range.count >= 2 {
            var updated = stroke
            updated.points = Array(points[range])
            updated.bounds = boundsFor(points: updated.points)
            updated.updatedAtMillis = now
            updated.revision += 1
            return [updated]
        }

        var fragments: [CanvasStroke] = []
        for (index, range) in ranges.enumerated() where range.count >= 2 {
            let fragmentPoints = Array(points[range])
            let fragment = CanvasStroke(
                id: index == 0 ? stroke.id : UUID(),
                style: stroke.style,
                points: fragmentPoints,
                bounds: boundsFor(points: fragmentPoints),
                isDeleted: false,
                erasedSpans: [],
                createdAtMillis: stroke.createdAtMillis,
                updatedAtMillis: now,
                revision: stroke.revision + 1
            )
            fragments.append(fragment)
        }

        return fragments
    }

    private func strokeIntersectsCircle(_ stroke: CanvasStroke, center: CGPoint, radius: CGFloat) -> Bool {
        let points = stroke.points
        guard let first = points.first else { return false }
        if distance(first.cgPoint, center) <= radius { return true }

        if points.count > 1 {
            for index in 1..<points.count {
                let a = points[index - 1].cgPoint
                let b = points[index].cgPoint
                if segmentDistanceSquared(point: center, a: a, b: b) <= radius * radius {
                    return true
                }
            }
        }
        return false
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = a.x - b.x
        let dy = a.y - b.y
        return sqrt(dx * dx + dy * dy)
    }

    private func segmentDistanceSquared(point p: CGPoint, a: CGPoint, b: CGPoint) -> CGFloat {
        let abx = b.x - a.x
        let aby = b.y - a.y
        let apx = p.x - a.x
        let apy = p.y - a.y
        let abLen2 = abx * abx + aby * aby

        guard abLen2 > 0 else {
            return apx * apx + apy * apy
        }

        let t = max(0, min(1, (apx * abx + apy * aby) / abLen2))
        let projX = a.x + abx * t
        let projY = a.y + aby * t
        let dx = p.x - projX
        let dy = p.y - projY
        return dx * dx + dy * dy
    }

    private func appendLassoPoints(from touches: [UITouch]) {
        for touch in touches {
            let point = makePoint(from: touch)
            if let last = lassoPoints.last {
                let dx = CGFloat(point.x - last.x)
                let dy = CGFloat(point.y - last.y)
                if dx * dx + dy * dy < 4 {
                    continue
                }
            }
            lassoPoints.append(point)
        }
    }

    private func commitLassoSelection() {
        guard lassoPoints.count >= 3 else {
            lassoPoints.removeAll(keepingCapacity: true)
            activeSelection = nil
            return
        }
        if let first = lassoPoints.first {
            lassoPoints.append(first)
        }

        let polygon = LassoPolygon(points: lassoPoints)
        let polygonBounds = polygon.bounds.cgRect
        let polygonPoints = polygon.points.map(\.cgPoint)

        let strokeCandidateIDs = queryIDs(in: polygonBounds, from: strokeBuckets)
        var selectedStrokeIDs: Set<UUID> = []
        for strokeID in strokeCandidateIDs {
            guard let index = strokeIndexByID[strokeID] else { continue }
            let stroke = strokes[index]
            guard !stroke.isDeleted else { continue }
            guard stroke.bounds.cgRect.intersects(polygonBounds) else { continue }
            if strokeHitByPolygon(stroke, polygon: polygonPoints, polygonBounds: polygonBounds) {
                selectedStrokeIDs.insert(stroke.id)
            }
        }

        let textCandidateIDs = queryIDs(in: polygonBounds, from: textBuckets)
        var selectedTextIDs: Set<UUID> = []
        for textID in textCandidateIDs {
            guard let index = textIndexByID[textID] else { continue }
            let box = textBoxes[index]
            let rect = box.frame.cgRect
            guard rect.intersects(polygonBounds) else { continue }
            if rectIntersectsPolygon(rect, polygon: polygonPoints) {
                selectedTextIDs.insert(textID)
            }
        }

        if selectedStrokeIDs.isEmpty && selectedTextIDs.isEmpty {
            activeSelection = nil
            return
        }

        activeSelection = SelectionGroup(
            id: UUID(),
            strokeIDs: selectedStrokeIDs,
            textBoxIDs: selectedTextIDs,
            lasso: polygon,
            bounds: selectionBounds(strokeIDs: selectedStrokeIDs, textBoxIDs: selectedTextIDs)
        )
    }

    private func strokeHitByPolygon(_ stroke: CanvasStroke, polygon: [CGPoint], polygonBounds: CGRect) -> Bool {
        let points = stroke.points
        guard points.count >= 2 else { return false }
        if points.contains(where: { pointInPolygon($0.cgPoint, polygon: polygon) }) {
            return true
        }

        for edgeIndex in 1..<polygon.count {
            let p0 = polygon[edgeIndex - 1]
            let p1 = polygon[edgeIndex]
            for segIndex in 1..<points.count {
                let s0 = points[segIndex - 1].cgPoint
                let s1 = points[segIndex].cgPoint
                if segmentsIntersect(a1: p0, a2: p1, b1: s0, b2: s1) {
                    return true
                }
            }
        }

        let center = CGPoint(x: stroke.bounds.cgRect.midX, y: stroke.bounds.cgRect.midY)
        return polygonBounds.contains(center) && pointInPolygon(center, polygon: polygon)
    }

    private func rectIntersectsPolygon(_ rect: CGRect, polygon: [CGPoint]) -> Bool {
        let corners = [
            rect.origin,
            CGPoint(x: rect.maxX, y: rect.minY),
            CGPoint(x: rect.maxX, y: rect.maxY),
            CGPoint(x: rect.minX, y: rect.maxY)
        ]
        if corners.contains(where: { pointInPolygon($0, polygon: polygon) }) {
            return true
        }
        if polygon.contains(where: { rect.contains($0) }) {
            return true
        }

        let rectEdges = [
            (corners[0], corners[1]),
            (corners[1], corners[2]),
            (corners[2], corners[3]),
            (corners[3], corners[0])
        ]
        for edgeIndex in 1..<polygon.count {
            let p0 = polygon[edgeIndex - 1]
            let p1 = polygon[edgeIndex]
            for edge in rectEdges where segmentsIntersect(a1: p0, a2: p1, b1: edge.0, b2: edge.1) {
                return true
            }
        }
        return false
    }

    private func pointInPolygon(_ point: CGPoint, polygon: [CGPoint]) -> Bool {
        guard polygon.count >= 3 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let pi = polygon[i]
            let pj = polygon[j]
            let intersect = ((pi.y > point.y) != (pj.y > point.y))
                && (point.x < (pj.x - pi.x) * (point.y - pi.y) / max(0.000001, pj.y - pi.y) + pi.x)
            if intersect {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    private func segmentsIntersect(a1: CGPoint, a2: CGPoint, b1: CGPoint, b2: CGPoint) -> Bool {
        let d1 = direction(a1, a2, b1)
        let d2 = direction(a1, a2, b2)
        let d3 = direction(b1, b2, a1)
        let d4 = direction(b1, b2, a2)

        if ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0)) {
            return true
        }
        if d1 == 0 && onSegment(a1, a2, b1) { return true }
        if d2 == 0 && onSegment(a1, a2, b2) { return true }
        if d3 == 0 && onSegment(b1, b2, a1) { return true }
        if d4 == 0 && onSegment(b1, b2, a2) { return true }
        return false
    }

    private func direction(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> CGFloat {
        (c.x - a.x) * (b.y - a.y) - (b.x - a.x) * (c.y - a.y)
    }

    private func onSegment(_ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Bool {
        min(a.x, b.x) <= c.x && c.x <= max(a.x, b.x)
            && min(a.y, b.y) <= c.y && c.y <= max(a.y, b.y)
    }

    private func selectionBounds(from selection: SelectionGroup) -> StrokeBounds {
        selectionBounds(strokeIDs: selection.strokeIDs, textBoxIDs: selection.textBoxIDs)
    }

    private func selectionBounds(strokeIDs: Set<UUID>, textBoxIDs: Set<UUID>) -> StrokeBounds {
        var rect: CGRect?
        for strokeID in strokeIDs {
            guard let index = strokeIndexByID[strokeID] else { continue }
            rect = rect?.union(strokes[index].bounds.cgRect) ?? strokes[index].bounds.cgRect
        }
        for textID in textBoxIDs {
            guard let index = textIndexByID[textID] else { continue }
            rect = rect?.union(textBoxes[index].frame.cgRect) ?? textBoxes[index].frame.cgRect
        }
        guard let finalRect = rect else { return .zero }
        return StrokeBounds(
            minX: Float(finalRect.minX),
            minY: Float(finalRect.minY),
            maxX: Float(finalRect.maxX),
            maxY: Float(finalRect.maxY)
        )
    }

    private func rebuildSpatialIndex() {
        strokeBuckets.removeAll(keepingCapacity: true)
        textBuckets.removeAll(keepingCapacity: true)
        strokeIndexByID.removeAll(keepingCapacity: true)
        textIndexByID.removeAll(keepingCapacity: true)

        for (index, stroke) in strokes.enumerated() where !stroke.isDeleted {
            strokeIndexByID[stroke.id] = index
            for key in spatialKeys(in: stroke.bounds.cgRect) {
                strokeBuckets[key, default: []].insert(stroke.id)
            }
        }

        for (index, textBox) in textBoxes.enumerated() {
            textIndexByID[textBox.id] = index
            for key in spatialKeys(in: textBox.frame.cgRect) {
                textBuckets[key, default: []].insert(textBox.id)
            }
        }
    }

    private func spatialKeys(in rect: CGRect) -> [SpatialKey] {
        guard !rect.isNull,
              rect.minX.isFinite,
              rect.minY.isFinite,
              rect.maxX.isFinite,
              rect.maxY.isFinite else {
            return []
        }
        let minX = Int(floor(rect.minX / spatialCellSize))
        let maxX = Int(floor(rect.maxX / spatialCellSize))
        let minY = Int(floor(rect.minY / spatialCellSize))
        let maxY = Int(floor(rect.maxY / spatialCellSize))
        guard minX <= maxX, minY <= maxY else { return [] }

        var keys: [SpatialKey] = []
        keys.reserveCapacity((maxX - minX + 1) * (maxY - minY + 1))
        for x in minX...maxX {
            for y in minY...maxY {
                keys.append(SpatialKey(x: x, y: y))
            }
        }
        return keys
    }

    private func queryIDs(in rect: CGRect, from buckets: [SpatialKey: Set<UUID>]) -> Set<UUID> {
        var result: Set<UUID> = []
        for key in spatialKeys(in: rect) {
            if let ids = buckets[key] {
                result.formUnion(ids)
            }
        }
        return result
    }

    private func pdfDocument(for url: URL) -> CGPDFDocument? {
        if cachedPDFDocumentURL == url, let cachedPDFDocument {
            return cachedPDFDocument
        }
        let document = CGPDFDocument(url as CFURL)
        cachedPDFDocumentURL = url
        cachedPDFDocument = document
        return document
    }

    private func fitCameraToPDFIfNeeded() {
        guard let layer = pdfLayer, bounds.width > 0, bounds.height > 0 else { return }
        let margin: CGFloat = 24
        let availableWidth = max(1, bounds.width - margin * 2)
        let availableHeight = max(1, bounds.height - margin * 2)
        let fittedScale = min(availableWidth / layer.pageWidth, availableHeight / layer.pageHeight)
        camera.scale = max(camera.minScale, min(camera.maxScale, fittedScale))
        camera.translation = CGPoint(
            x: bounds.midX - layer.worldRect.midX * camera.scale,
            y: bounds.midY - layer.worldRect.midY * camera.scale
        )
    }

    private func handleTextTouchBegan(_ touch: UITouch) {
        let worldPoint = camera.viewToWorld(touch.location(in: self))
        if let hitID = textBoxID(at: worldPoint), let index = textIndexByID[hitID] {
            selectedTextBoxID = hitID
            draggingTextBoxID = hitID
            let frame = textBoxes[index].frame.cgRect
            textDragOffset = CGPoint(x: worldPoint.x - frame.minX, y: worldPoint.y - frame.minY)
        } else {
            createTextBox(at: worldPoint)
        }
        setNeedsDisplay()
    }

    private func handleTextTouchMoved(_ touch: UITouch) {
        guard let draggingID = draggingTextBoxID,
              let index = textIndexByID[draggingID] else { return }
        let worldPoint = camera.viewToWorld(touch.location(in: self))
        let frame = textBoxes[index].frame.cgRect
        let newMinX = worldPoint.x - textDragOffset.x
        let newMinY = worldPoint.y - textDragOffset.y
        textBoxes[index].frame = StrokeBounds(
            minX: Float(newMinX),
            minY: Float(newMinY),
            maxX: Float(newMinX + frame.width),
            maxY: Float(newMinY + frame.height)
        )
        textBoxes[index].updatedAtMillis = nowMillis()
        rebuildSpatialIndex()
        setNeedsDisplay()
    }

    private func createTextBox(at worldPoint: CGPoint) {
        let now = nowMillis()
        let fontSize = CGFloat(activeTextStyle.fontSize)
        let width = max(140, min(520, CGFloat(activeTextContent.count) * fontSize * 0.6 + 20))
        let height = max(44, fontSize * CGFloat(activeTextStyle.lineHeightMultiple) + 20)
        let minX = worldPoint.x - width * 0.5
        let minY = worldPoint.y - height * 0.5
        let newBox = CanvasTextBox(
            id: UUID(),
            text: activeTextContent,
            frame: StrokeBounds(
                minX: Float(minX),
                minY: Float(minY),
                maxX: Float(minX + width),
                maxY: Float(minY + height)
            ),
            rotation: 0,
            style: activeTextStyle,
            zIndex: (textBoxes.map(\.zIndex).max() ?? 0) + 1,
            isLocked: false,
            createdAtMillis: now,
            updatedAtMillis: now
        )
        textBoxes.append(newBox)
        selectedTextBoxID = newBox.id
        draggingTextBoxID = newBox.id
        textDragOffset = CGPoint(x: width * 0.5, y: height * 0.5)
        rebuildSpatialIndex()
        scheduleAutosave()
    }

    private func textBoxID(at worldPoint: CGPoint) -> UUID? {
        let sampleRect = CGRect(x: worldPoint.x - 1, y: worldPoint.y - 1, width: 2, height: 2)
        let candidates = queryIDs(in: sampleRect, from: textBuckets)
        let ordered = textBoxes
            .filter { candidates.contains($0.id) && !$0.isLocked }
            .sorted { $0.zIndex > $1.zIndex }
        return ordered.first(where: { $0.frame.cgRect.contains(worldPoint) })?.id
    }

    private func contentBounds() -> CGRect {
        var rect: CGRect?
        for stroke in strokes where !stroke.isDeleted {
            rect = rect?.union(stroke.bounds.cgRect) ?? stroke.bounds.cgRect
        }
        for box in textBoxes {
            rect = rect?.union(box.frame.cgRect) ?? box.frame.cgRect
        }
        return rect ?? .null
    }

    private func commitActiveStroke() {
        guard activePoints.count >= 2 else {
            activePoints.removeAll(keepingCapacity: true)
            activeEstimatedLookup.removeAll(keepingCapacity: true)
            return
        }

        strokes.append(
            CanvasStroke(
                id: UUID(),
                style: activeStyle,
                points: activePoints,
                bounds: boundsFor(points: activePoints),
                isDeleted: false,
                erasedSpans: [],
                createdAtMillis: nowMillis(),
                updatedAtMillis: nowMillis(),
                revision: 1
            )
        )

        activePoints.removeAll(keepingCapacity: true)
        activeEstimatedLookup.removeAll(keepingCapacity: true)
        rebuildSpatialIndex()
        scheduleAutosave()
    }

    private func boundsFor(points: [CanvasStrokePoint]) -> StrokeBounds {
        StrokeBounds(points: points)
    }

    private func nowMillis() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }

    private func scheduleAutosave() {
        let annotations = CanvasPageAnnotations(strokes: strokes, textBoxes: textBoxes)
        Task { [annotations] in
            await autosaveStore.scheduleSave(annotations: annotations)
        }
    }

}
