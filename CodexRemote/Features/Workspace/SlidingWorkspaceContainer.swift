import SwiftUI
import UIKit

struct DeviceConcentricSurface: ViewModifier {
    let fallbackRadius: CGFloat
    let borderOpacity: Double

    @ViewBuilder
    func body(content: Content) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            let shape = ConcentricRectangle(
                corners: .concentric(minimum: .fixed(fallbackRadius)),
                isUniform: true
            )
            content
                .clipShape(shape)
                .overlay {
                    shape.stroke(Color.black.opacity(borderOpacity), lineWidth: 0.75)
                }
        } else {
            let shape = RoundedRectangle(cornerRadius: fallbackRadius, style: .continuous)
            content
                .clipShape(shape)
                .overlay {
                    shape.stroke(Color.black.opacity(borderOpacity), lineWidth: 0.75)
                }
        }
        #else
        let shape = RoundedRectangle(cornerRadius: fallbackRadius, style: .continuous)
        content
            .clipShape(shape)
            .overlay {
                shape.stroke(Color.black.opacity(borderOpacity), lineWidth: 0.75)
            }
        #endif
    }
}

struct SlidingWorkspaceContainer<ProjectManager: View, Workspace: View>: UIViewControllerRepresentable {
    @Binding var isProjectManagerVisible: Bool
    let projectManagerWidth: CGFloat
    let projectManager: ProjectManager
    let workspace: Workspace

    init(
        isProjectManagerVisible: Binding<Bool>,
        projectManagerWidth: CGFloat,
        @ViewBuilder projectManager: () -> ProjectManager,
        @ViewBuilder workspace: () -> Workspace
    ) {
        _isProjectManagerVisible = isProjectManagerVisible
        self.projectManagerWidth = projectManagerWidth
        self.projectManager = projectManager()
        self.workspace = workspace()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(isProjectManagerVisible: $isProjectManagerVisible)
    }

    func makeUIViewController(context: Context) -> SlidingWorkspaceViewController {
        let viewController = SlidingWorkspaceViewController()
        viewController.projectManagerHost.rootView = AnyView(projectManager)
        viewController.workspaceHost.rootView = AnyView(workspace)
        viewController.projectManagerWidth = projectManagerWidth
        viewController.isProjectManagerVisible = isProjectManagerVisible
        viewController.onVisibilityChanged = context.coordinator.projectManagerVisibilityDidChange
        context.coordinator.viewController = viewController
        return viewController
    }

    func updateUIViewController(_ viewController: SlidingWorkspaceViewController, context: Context) {
        let desiredProjectManagerVisibility = isProjectManagerVisible
        viewController.projectManagerHost.rootView = AnyView(projectManager)
        viewController.workspaceHost.rootView = AnyView(workspace)
        viewController.projectManagerWidth = projectManagerWidth
        viewController.onVisibilityChanged = context.coordinator.projectManagerVisibilityDidChange
        viewController.layoutPages(preservingCurrentOffset: viewController.hasLaidOutOnce)

        guard !viewController.isInteracting else { return }

        viewController.setProjectManagerVisible(
            desiredProjectManagerVisibility,
            animated: viewController.hasLaidOutOnce && viewController.view.window != nil,
            notifyBinding: false
        )
    }

    final class Coordinator: NSObject {
        @Binding private var isProjectManagerVisible: Bool
        weak var viewController: SlidingWorkspaceViewController?

        init(isProjectManagerVisible: Binding<Bool>) {
            _isProjectManagerVisible = isProjectManagerVisible
        }

        func projectManagerVisibilityDidChange(_ isVisible: Bool) {
            if isProjectManagerVisible != isVisible {
                isProjectManagerVisible = isVisible
            }
        }
    }
}

final class SlidingWorkspaceViewController: UIViewController {
    let projectManagerHost = UIHostingController(rootView: AnyView(EmptyView()))
    let workspaceHost = UIHostingController(rootView: AnyView(EmptyView()))
    var projectManagerWidth: CGFloat = 0
    var isProjectManagerVisible = false
    var onVisibilityChanged: ((Bool) -> Void)?
    private(set) var hasLaidOutOnce = false

    private let workspaceContainer = UIView()
    private var horizontalPanGesture: UIPanGestureRecognizer?
    private var workspaceTapGesture: UITapGestureRecognizer?
    private var panStartOffset: CGFloat = 0
    private(set) var isInteracting = false
    private let closedLeadingSwipeActivationWidth: CGFloat = 96
    private let openWorkspaceSwipeSlop: CGFloat = 12

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = UIColor(red: 0.975, green: 0.973, blue: 0.965, alpha: 1)

        let horizontalPanGesture = UIPanGestureRecognizer(target: self, action: #selector(handleWorkspacePan(_:)))
        horizontalPanGesture.delegate = self
        horizontalPanGesture.cancelsTouchesInView = false
        view.addGestureRecognizer(horizontalPanGesture)
        self.horizontalPanGesture = horizontalPanGesture

        let workspaceTapGesture = UITapGestureRecognizer(target: self, action: #selector(handleWorkspaceTap(_:)))
        workspaceTapGesture.delegate = self
        workspaceTapGesture.cancelsTouchesInView = false
        workspaceTapGesture.numberOfTapsRequired = 1
        workspaceContainer.addGestureRecognizer(workspaceTapGesture)
        self.workspaceTapGesture = workspaceTapGesture

        addChild(projectManagerHost)
        view.addSubview(projectManagerHost.view)
        projectManagerHost.didMove(toParent: self)

        view.addSubview(workspaceContainer)
        addChild(workspaceHost)
        workspaceContainer.addSubview(workspaceHost.view)
        workspaceHost.didMove(toParent: self)

        projectManagerHost.view.backgroundColor = .clear
        workspaceHost.view.backgroundColor = .clear
        workspaceContainer.backgroundColor = UIColor(red: 0.975, green: 0.973, blue: 0.965, alpha: 1)
        workspaceContainer.clipsToBounds = false
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutPages()
        if !hasLaidOutOnce {
            setProjectManagerVisible(isProjectManagerVisible, animated: false, notifyBinding: false)
            hasLaidOutOnce = true
        }
    }

    @objc private func handleWorkspaceTap(_ recognizer: UITapGestureRecognizer) {
        guard recognizer.state == .ended, isProjectManagerVisible else { return }
        setProjectManagerVisible(false, animated: true)
    }

    @objc private func handleWorkspacePan(_ recognizer: UIPanGestureRecognizer) {
        guard projectManagerWidth > 0 else { return }

        let translation = recognizer.translation(in: view).x
        let velocity = recognizer.velocity(in: view).x

        switch recognizer.state {
        case .began:
            isInteracting = true
            panStartOffset = workspaceContainer.frame.minX
        case .changed:
            let nextOffset = min(max(panStartOffset + translation, 0), projectManagerWidth)
            setWorkspaceOffset(nextOffset)
        case .ended, .cancelled, .failed:
            let shouldShowProjectManager: Bool
            if velocity > 250 {
                shouldShowProjectManager = true
            } else if velocity < -250 {
                shouldShowProjectManager = false
            } else {
                shouldShowProjectManager = workspaceContainer.frame.minX > projectManagerWidth * 0.5
            }
            isInteracting = false
            setProjectManagerVisible(shouldShowProjectManager, animated: true)
        default:
            break
        }
    }

    func layoutPages(preservingCurrentOffset: Bool = false) {
        let bounds = view.bounds
        let currentOffset: CGFloat
        if isInteracting || preservingCurrentOffset {
            currentOffset = min(max(workspaceContainer.frame.minX, 0), projectManagerWidth)
        } else {
            currentOffset = isProjectManagerVisible ? projectManagerWidth : 0
        }
        projectManagerHost.view.frame = CGRect(x: 0, y: 0, width: projectManagerWidth, height: bounds.height)
        workspaceContainer.frame = CGRect(x: currentOffset, y: 0, width: bounds.width, height: bounds.height)
        workspaceHost.view.frame = workspaceContainer.bounds
    }

    func setProjectManagerVisible(_ visible: Bool, animated: Bool, notifyBinding: Bool = true) {
        isProjectManagerVisible = visible
        if notifyBinding {
            onVisibilityChanged?(visible)
        }
        updateAccessibilityVisibility()
        let targetOffset = visible ? projectManagerWidth : 0
        guard workspaceContainer.frame.minX != targetOffset else { return }

        if animated {
            UIView.animate(
                withDuration: 0.32,
                delay: 0,
                usingSpringWithDamping: 0.9,
                initialSpringVelocity: 0.15,
                options: [.allowUserInteraction, .beginFromCurrentState]
            ) {
                self.setWorkspaceOffset(targetOffset)
            } completion: { _ in
                self.setWorkspaceOffset(targetOffset)
            }
        } else {
            setWorkspaceOffset(targetOffset)
        }
    }

    func updateAccessibilityVisibility() {
        projectManagerHost.view.accessibilityElementsHidden = !isProjectManagerVisible
    }

    private func setWorkspaceOffset(_ offset: CGFloat) {
        var frame = workspaceContainer.frame
        frame.origin.x = offset
        workspaceContainer.frame = frame
    }
}

extension SlidingWorkspaceViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        if let horizontalPanGesture, gestureRecognizer === horizontalPanGesture {
            let location = touch.location(in: view)
            if isProjectManagerVisible {
                return location.x >= projectManagerWidth - openWorkspaceSwipeSlop
            }
            return location.x <= closedLeadingSwipeActivationWidth
        }

        if let workspaceTapGesture, gestureRecognizer === workspaceTapGesture {
            return isProjectManagerVisible
        }

        return true
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if let workspaceTapGesture, gestureRecognizer === workspaceTapGesture {
            return isProjectManagerVisible
        }

        guard let horizontalPanGesture, gestureRecognizer === horizontalPanGesture else { return true }

        let location = horizontalPanGesture.location(in: view)
        let velocity = horizontalPanGesture.velocity(in: view)
        guard abs(velocity.x) > abs(velocity.y) else { return false }

        if isProjectManagerVisible {
            return location.x >= projectManagerWidth - openWorkspaceSwipeSlop
        } else {
            return location.x <= closedLeadingSwipeActivationWidth && velocity.x > 0
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }
}
