import SwiftUI

// MARK: - Animated Mesh Gradient Background View (Color Animation)

struct AnimatedMeshBackgroundView: View {
    let initialColors: [Color]
    let colorAnimationDuration: Double = 3
    let randomUpdateInterval: Double = 3

    // MARK: - State Variables
    @State private var animatedColors: [Color]
    @State private var timer: Timer? = nil

    // MARK: - Static Properties
    private static let staticPoints: [SIMD2<Float>] = [
        .init(x: 0.0, y: 0.0), .init(x: 0.5, y: 0.0), .init(x: 1.0, y: 0.0),
        .init(x: 0.0, y: 0.5), .init(x: 0.5, y: 0.5), .init(x: 1.0, y: 0.5),
        .init(x: 0.0, y: 1.0), .init(x: 0.5, y: 1.0), .init(x: 1.0, y: 1.0)
    ]

    // MARK: - Initializer
    init(colors: [Color]) {
        self.initialColors = colors
        _animatedColors = State(initialValue: Self.mapColorsToGrid(baseColors: colors))
    }

    // MARK: - Body
    var body: some View {
        MeshGradient(
            width: 3,
            height: 3,
            points: Self.staticPoints,
            colors: animatedColors
        )
        .opacity(0.3)
        .onAppear(perform: startAnimation)
        .onDisappear(perform: stopAnimation)
    }

    // MARK: - Animation Control Methods
    private func startAnimation() {
        print("Starting Mesh Color Animation")
        timer?.invalidate()
        randomizeColorsWithAnimation()
        timer = Timer.scheduledTimer(withTimeInterval: randomUpdateInterval, repeats: true) { _ in
            self.randomizeColorsWithAnimation()
        }
    }

    private func stopAnimation() {
        print("Stopping Mesh Color Animation")
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Color Randomization
    private func randomizeColorsWithAnimation() {
        let newTargetColors = generateRandomShiftedColors()
        withAnimation(.easeInOut(duration: colorAnimationDuration)) {
            animatedColors = newTargetColors
        }
    }

    private func generateRandomShiftedColors() -> [Color] {
        var shuffledBase = initialColors.shuffled()

        while shuffledBase.count < 9 {
            shuffledBase.append(contentsOf: initialColors.shuffled())
        }
        return Array(shuffledBase.prefix(9))
    }

    // MARK: - Static Helper
     static func mapColorsToGrid(baseColors: [Color]) -> [Color] {
         guard !baseColors.isEmpty else { return Array(repeating: .gray, count: 9) }
         return (0..<9).map { baseColors[$0 % baseColors.count] }
     }
}


