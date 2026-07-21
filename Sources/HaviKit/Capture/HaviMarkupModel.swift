#if canImport(UIKit)
import CoreGraphics
import Foundation
import Observation

/// The multi-mark markup editor state (bead havi-6953), owned by the capture sheet
/// and observed by `HaviMarkupCanvas`. Holds the current tool + color, the array
/// of committed vector marks (normalized image space), the in-progress stroke, the
/// selection, and object-level **undo AND redo** stacks. Every drawing/selection
/// gesture funnels through the `begin/extend/end` methods so the canvas view stays
/// thin — it only converts display points to normalized (0…1) coordinates.
@MainActor
@Observable
final class HaviMarkupModel {
    var tool: HaviMarkTool = .pen
    var color: HaviMarkColor = .red
    private(set) var marks: [HaviMark] = []
    private(set) var inProgress: HaviMark?
    var selectedMarkID: UUID?

    /// Undo/redo hold whole-array snapshots, so an add, a move, and a delete are
    /// each one reversible step (design: object-level undo AND redo).
    private var undoStack: [[HaviMark]] = []
    private var redoStack: [[HaviMark]] = []

    private var anchor: CGPoint?
    private var moveSnapshot: [HaviMark]?
    private var moveLast: CGPoint?

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }

    var selectedMark: HaviMark? {
        guard let id = selectedMarkID else { return nil }
        return marks.first { $0.id == id }
    }

    func selectTool(_ newTool: HaviMarkTool) {
        tool = newTool
        if newTool != .select { selectedMarkID = nil }
    }

    // MARK: - Gestures (points are already normalized 0…1 by the canvas)

    func begin(at point: CGPoint) {
        switch tool {
        case .pen:
            inProgress = HaviMark(shape: .pen(points: [point]), color: color)
        case .highlighter:
            inProgress = HaviMark(shape: .highlighter(points: [point]), color: color)
        case .arrow:
            inProgress = HaviMark(shape: .arrow(from: point, to: point), color: color)
        case .rectangle:
            anchor = point
            inProgress = HaviMark(shape: .rectangle(CGRect(origin: point, size: .zero)), color: color)
        case .blur:
            anchor = point
            inProgress = HaviMark(shape: .blur(CGRect(origin: point, size: .zero)), color: color)
        case .select:
            beginSelectOrMove(at: point)
        }
    }

    func extend(to point: CGPoint) {
        guard tool.isDrawing else {
            updateMove(to: point)
            return
        }
        guard var mark = inProgress else { return }
        switch mark.shape {
        case .pen(var points):
            points.append(point)
            mark.shape = .pen(points: points)
        case .highlighter(var points):
            points.append(point)
            mark.shape = .highlighter(points: points)
        case .arrow(let from, _):
            mark.shape = .arrow(from: from, to: point)
        case .rectangle:
            mark.shape = .rectangle(HaviMarkupModel.rect(from: anchor ?? point, to: point))
        case .blur:
            mark.shape = .blur(HaviMarkupModel.rect(from: anchor ?? point, to: point))
        }
        inProgress = mark
    }

    func end() {
        guard tool.isDrawing else {
            endMove()
            return
        }
        defer { inProgress = nil; anchor = nil }
        guard let mark = inProgress, HaviMarkupModel.isMeaningful(mark) else { return }
        commit(marks + [mark])
        selectedMarkID = nil
    }

    func deleteSelected() {
        guard let id = selectedMarkID else { return }
        commit(marks.filter { $0.id != id })
        selectedMarkID = nil
    }

    func undo() {
        guard let previous = undoStack.popLast() else { return }
        redoStack.append(marks)
        marks = previous
        selectedMarkID = nil
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(marks)
        marks = next
        selectedMarkID = nil
    }

    // MARK: - Select / move

    private func beginSelectOrMove(at point: CGPoint) {
        if let hit = marks.last(where: { $0.hitTest(point, tolerance: 0.03) }) {
            selectedMarkID = hit.id
            moveSnapshot = marks
            moveLast = point
        } else {
            selectedMarkID = nil
            moveSnapshot = nil
            moveLast = nil
        }
    }

    private func updateMove(to point: CGPoint) {
        guard let id = selectedMarkID, let last = moveLast,
              let index = marks.firstIndex(where: { $0.id == id }) else { return }
        marks[index].translate(by: CGVector(dx: point.x - last.x, dy: point.y - last.y))
        moveLast = point
    }

    private func endMove() {
        defer { moveSnapshot = nil; moveLast = nil }
        guard let snapshot = moveSnapshot, snapshot != marks else { return }
        undoStack.append(snapshot)
        redoStack.removeAll()
    }

    // MARK: - Helpers

    private func commit(_ newMarks: [HaviMark]) {
        undoStack.append(marks)
        marks = newMarks
        redoStack.removeAll()
    }

    static func rect(from a: CGPoint, to b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    /// An accidental tap (near-zero drag) is not a mark. Freehand needs at least
    /// two points; the geometric tools need a non-trivial extent.
    static func isMeaningful(_ mark: HaviMark) -> Bool {
        switch mark.shape {
        case .pen(let points), .highlighter(let points):
            return points.count >= 2 && span(points) >= HaviCaptureGeometry.minMarkupFraction
        case .arrow(let from, let to):
            return hypot(to.x - from.x, to.y - from.y) >= HaviCaptureGeometry.minMarkupFraction
        case .rectangle(let rect), .blur(let rect):
            return HaviCaptureGeometry.isMeaningful(fraction: rect.standardized)
        }
    }

    private static func span(_ points: [CGPoint]) -> CGFloat {
        let bounds = HaviMark.bounds(of: points)
        return max(bounds.width, bounds.height)
    }
}
#endif
