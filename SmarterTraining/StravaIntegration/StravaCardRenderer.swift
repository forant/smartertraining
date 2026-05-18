import SwiftUI

@MainActor
struct StravaCardRenderer {

    static func render(workout: CompletedWorkout) -> UIImage? {
        let view = StravaWorkoutCardView(workout: workout)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 3
        return renderer.uiImage
    }
}
