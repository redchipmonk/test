//
//  EmotionEffectModifier.swift
//  blubble
//
//  Created by Jeffrey Song on 2/14/26.
//

import SwiftUI

struct EmotionEffectModifier: ViewModifier {
    let emotion: Emotion
    @State private var animationTrigger = false

    func body(content: Content) -> some View {
        Group {
            switch emotion {
            case .anger:
                content
                    .keyframeAnimator(
                        initialValue: CGSize.zero,
                        trigger: animationTrigger
                    ) { view, offset in
                        view.offset(offset)
                    } keyframes: { _ in
                        KeyframeTrack(\.width) {
                            LinearKeyframe(22, duration: 0.056); LinearKeyframe(-24, duration: 0.070)
                            LinearKeyframe(15, duration: 0.044); LinearKeyframe(-18, duration: 0.062)
                            LinearKeyframe(8, duration: 0.052);  LinearKeyframe(0, duration: 0.090)
                        }
                        KeyframeTrack(\.height) {
                            LinearKeyframe(-14, duration: 0.042); LinearKeyframe(17, duration: 0.076)
                            LinearKeyframe(-11, duration: 0.054); LinearKeyframe(9, duration: 0.068)
                            LinearKeyframe(-4, duration: 0.040);  LinearKeyframe(0, duration: 0.100)
                        }
                    }
            case .joy:
                content
                // TODO: placholder
            case .sadness:
                content
                // TODO: placeholder
            default:
                content
            }
        }
        .onAppear {
            if emotion != .neutral {
                Task {
                    try? await Task.sleep(for: .seconds(0.8))
                    animationTrigger.toggle()
                }
            }
        }
    }
}

extension View {
    func emotionEffect(_ emotion: Emotion) -> some View {
        modifier(EmotionEffectModifier(emotion: emotion))
    }
}
