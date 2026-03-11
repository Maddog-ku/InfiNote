import SwiftUI
import UIKit

struct CanvasContainerView: UIViewControllerRepresentable {
    let pageID: UUID

    func makeUIViewController(context: Context) -> CanvasViewController {
        CanvasViewController(pageID: pageID)
    }

    func updateUIViewController(_ uiViewController: CanvasViewController, context: Context) {}
}

final class CanvasViewController: UIViewController {
    private let pageID: UUID
    private let inputViewLayer = StylusInputView()
    private let renderer = CanvasRendererView()

    init(pageID: UUID) {
        self.pageID = pageID
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        renderer.frame = view.bounds
        renderer.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        inputViewLayer.frame = view.bounds
        inputViewLayer.autoresizingMask = [.flexibleWidth, .flexibleHeight]

        view.addSubview(renderer)
        view.addSubview(inputViewLayer)

        inputViewLayer.onSample = { [weak self] sample in
            self?.renderer.consume(sample: sample)
        }
    }
}

final class CanvasRendererView: UIView {
    private(set) var samples: [InputSample] = []

    func consume(sample: InputSample) {
        samples.append(sample)
        setNeedsDisplay()
    }

    override func draw(_ rect: CGRect) {
        UIColor.systemBackground.setFill()
        UIRectFill(rect)

        guard let cg = UIGraphicsGetCurrentContext() else { return }
        cg.setStrokeColor(UIColor.label.cgColor)
        cg.setLineWidth(2)

        var previous: CGPoint?
        for sample in samples.suffix(1200) {
            if let p = previous {
                cg.move(to: p)
                cg.addLine(to: sample.location)
                cg.strokePath()
            }
            previous = sample.location
        }
    }
}
