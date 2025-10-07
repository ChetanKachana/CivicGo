import SwiftUI

// MARK: - Animated Mesh Gradient Background View (Color Animation)
// Creates a background with a morphing mesh gradient effect by animating the colors
// assigned to the grid points, rather than the points themselves.
struct AnimatedMeshBackgroundView: View {
    // Input: Base colors to use and cycle through in the gradient mesh.
    let initialColors: [Color]
    // Animation parameters
    let colorAnimationDuration: Double = 3 // Duration for colors to transition (seconds)
    let randomUpdateInterval: Double = 3 // How often to pick new target colors (seconds)

    // MARK: - State Variables
    // State holds the CURRENT colors assigned to each of the 9 grid points.
    @State private var animatedColors: [Color]
    // Timer to trigger periodic randomization of target colors.
    @State private var timer: Timer? = nil

    // MARK: - Static Properties
    // The 3x3 grid points remain fixed. Defined as a flat array of SIMD2<Float>.
    private static let staticPoints: [SIMD2<Float>] = [
        .init(x: 0.0, y: 0.0), .init(x: 0.5, y: 0.0), .init(x: 1.0, y: 0.0), // Top row (TL, TM, TR)
        .init(x: 0.0, y: 0.5), .init(x: 0.5, y: 0.5), .init(x: 1.0, y: 0.5), // Middle row (ML, C, MR)
        .init(x: 0.0, y: 1.0), .init(x: 0.5, y: 1.0), .init(x: 1.0, y: 1.0)  // Bottom row (BL, BM, BR)
    ]

    // MARK: - Initializer
    // Sets up the initial state of animatedColors based on the input colors.
    init(colors: [Color]) {
        // Store the base colors provided
        self.initialColors = colors
        // Initialize the @State variable by mapping the base colors to the 9 grid points.
        // _variableName is the syntax to access the underlying State<Value> struct.
        _animatedColors = State(initialValue: Self.mapColorsToGrid(baseColors: colors))
    }

    // MARK: - Body
    var body: some View {
        MeshGradient(
            width: 3, // Grid width (number of points)
            height: 3, // Grid height (number of points)
            points: Self.staticPoints, // Use the fixed grid points
            colors: animatedColors     // Use the @State variable for colors
        )
        .opacity(0.3) // Apply an overall opacity. Adjust as needed (0.0 to 1.0).
        .onAppear(perform: startAnimation) // Start the animation when the view appears
        .onDisappear(perform: stopAnimation) // Stop the animation when the view disappears
    }

    // MARK: - Animation Control Methods
    /// Starts the timer and the initial animation transition.
    private func startAnimation() {
        print("Starting Mesh Color Animation")
        // Ensure no duplicate timers if onAppear is called multiple times
        timer?.invalidate()
        // Set the initial random target colors and start animating towards them
        randomizeColorsWithAnimation()
        // Schedule a repeating timer to change the target colors periodically
        timer = Timer.scheduledTimer(withTimeInterval: randomUpdateInterval, repeats: true) { _ in
            // This closure is executed by the timer
            self.randomizeColorsWithAnimation()
        }
    }

    /// Stops the timer when the view disappears.
    private func stopAnimation() {
        print("Stopping Mesh Color Animation")
        timer?.invalidate()
        timer = nil
    }

    // MARK: - Color Randomization
    /// Generates a new set of target colors and triggers the animation.
    private func randomizeColorsWithAnimation() {
        let newTargetColors = generateRandomShiftedColors()
        // Animate the change from the current `animatedColors` to `newTargetColors`
        withAnimation(.easeInOut(duration: colorAnimationDuration)) {
            animatedColors = newTargetColors // Update the state variable
        }
    }

    /// Creates a new array of 9 colors, typically by shuffling or modifying the initial colors.
    private func generateRandomShiftedColors() -> [Color] {
        // --- Simple Shuffle Approach ---
        var shuffledBase = initialColors.shuffled() // Shuffle the input colors

        // Ensure we always have exactly 9 colors for the grid.
        // If fewer than 9 initial colors were provided, repeat them.
        while shuffledBase.count < 9 {
            shuffledBase.append(contentsOf: initialColors.shuffled()) // Append more shuffled colors
        }
        // Return the first 9 colors from the shuffled (and potentially extended) array.
        return Array(shuffledBase.prefix(9))

        // --- Alternative: Hue Shift Approach (requires Color extension below) ---
        // return animatedColors.map { $0.offsetHue(by: CGFloat.random(in: -0.1...0.1)) }
    }

    // MARK: - Static Helper
    /// Maps the initial base colors to the 9 grid points for the first display.
     static func mapColorsToGrid(baseColors: [Color]) -> [Color] {
         // Handle empty input defensively
         guard !baseColors.isEmpty else { return Array(repeating: .gray, count: 9) }
         // Cycle through the base colors to fill the 9 grid points
         return (0..<9).map { baseColors[$0 % baseColors.count] }
     }
}

// MARK: - SwiftUI Preview

// Optional: Extension to slightly shift Hue for alternative animation style
/*
extension Color {
    /// Creates a new color by shifting the hue of the original color.
    /// - Parameter amount: The amount to shift the hue (e.g., 0.1 for 10%). Wraps around 1.0.
    /// - Returns: A new Color with the adjusted hue.
    func offsetHue(by amount: CGFloat) -> Color {
        var h: CGFloat = 0 // Hue
        var s: CGFloat = 0 // Saturation
        var b: CGFloat = 0 // Brightness
        var a: CGFloat = 0 // Alpha

        // Use UIColor/NSColor to extract HSB components
        #if canImport(UIKit)
        UIColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        #elseif canImport(AppKit)
        NSColor(self).getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        #else
        // Fallback if no UIKit/AppKit (e.g., watchOS without compatibility)
        return self // Return original color if conversion fails
        #endif

        // Calculate new hue, wrapping around using truncatingRemainder
        var newHue = (h + amount).truncatingRemainder(dividingBy: 1.0)
        // Ensure hue stays positive (e.g., if amount was negative)
        if newHue < 0 { newHue += 1.0 }

        return Color(hue: newHue, saturation: s, brightness: b, opacity: a)
    }
}
*/
