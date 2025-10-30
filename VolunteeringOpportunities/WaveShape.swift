import SwiftUI

struct WaveShape: Shape {
    var frequency: Double
    var amplitude: Double
    var phase: Double
    var progress: Double 

    
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

          
            let startMidlineFactor: Double = 0.75
            let endMidlineFactor: Double = 0.25
            let currentMidlineFactor = startMidlineFactor + (endMidlineFactor - startMidlineFactor) * progress
            let midHeight = height * currentMidlineFactor


            
            path.move(to: CGPoint(x: 0, y: rect.height))
            path.addLine(to: CGPoint(x: 0, y: midHeight))

            let waveLength = width / frequency
            let wavePhase = phase * .pi * 2.0

            for x in stride(from: 0.0, through: width, by: 5.0) {
                let relativeX = x / waveLength
                let angle = relativeX * .pi * 2.0 + wavePhase
                let sineValue = sin(angle)
                let y = midHeight + sineValue * amplitude

                path.addLine(to: CGPoint(x: CGFloat(x), y: CGFloat(y)))
            }
           
            path.addLine(to: CGPoint(x: rect.width, y: rect.height))
            path.closeSubpath()
        }
    }
}
