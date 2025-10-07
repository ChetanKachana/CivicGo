import SwiftUI

struct WaveShape: Shape {
    var frequency: Double
    var amplitude: Double
    var phase: Double
    var progress: Double // New property: 0.0 (start) to 1.0 (end)

    // Make BOTH phase and progress animatable
    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(phase, progress) }
        set {
            phase = newValue.first
            progress = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        Path { path in
            let width = Double(rect.width)
            let height = Double(rect.height)

            // --- Calculate midHeight dynamically based on progress ---
            // Starts lower (e.g., 75% down) and moves towards higher (e.g., 25% down)
            let startMidlineFactor: Double = 0.75 // Lower = higher water level start
            let endMidlineFactor: Double = 0.25   // Higher = lower water level end
            // Interpolate the midline factor based on progress
            let currentMidlineFactor = startMidlineFactor + (endMidlineFactor - startMidlineFactor) * progress
            let midHeight = height * currentMidlineFactor
            // --- End dynamic midHeight calculation ---


            // Start path at the bottom-left corner
            path.move(to: CGPoint(x: 0, y: rect.height))
            // Move to the top-left (start of the wave line)
            path.addLine(to: CGPoint(x: 0, y: midHeight)) // Use dynamic midHeight

            // --- Draw the sine wave across the width (relative to dynamic midHeight) ---
            let waveLength = width / frequency
            let wavePhase = phase * .pi * 2.0

            for x in stride(from: 0.0, through: width, by: 5.0) {
                let relativeX = x / waveLength
                let angle = relativeX * .pi * 2.0 + wavePhase
                let sineValue = sin(angle)
                // Calculate y relative to the *current* dynamic midHeight
                let y = midHeight + sineValue * amplitude

                path.addLine(to: CGPoint(x: CGFloat(x), y: CGFloat(y)))
            }
            // --- End Sine Wave ---

            // Complete the shape
            path.addLine(to: CGPoint(x: rect.width, y: rect.height))
            path.closeSubpath()
        }
    }
}
