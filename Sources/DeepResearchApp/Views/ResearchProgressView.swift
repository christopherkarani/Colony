import SwiftUI

struct ResearchProgressView: View {
    let phase: ResearchPhase
    let isProcessing: Bool

    @State private var progressWidth: CGFloat = 0

    var body: some View {
        if isProcessing && phase != .idle && phase != .done {
            VStack(spacing: 12) {
                // Phase steps
                HStack(spacing: 0) {
                    ForEach(activePhases, id: \.self) { step in
                        PhaseStepIndicator(
                            phase: step,
                            isActive: step == phase,
                            isCompleted: isPhaseCompleted(step)
                        )

                        if step != activePhases.last {
                            Rectangle()
                                .fill(isPhaseCompleted(step) ? Color.dsIndigo : Color.dsBorder)
                                .frame(height: 2)
                        }
                    }
                }

                // Animated progress bar
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.dsSurface)
                            .frame(height: 4)

                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.dsIndigo)
                            .frame(width: progressWidth, height: 4)
                    }
                    .onAppear {
                        withAnimation(DSAnimation.smooth) {
                            progressWidth = geometry.size.width * progressFraction
                        }
                    }
                    .onChange(of: phase) {
                        withAnimation(DSAnimation.smooth) {
                            progressWidth = geometry.size.width * progressFraction
                        }
                    }
                }
                .frame(height: 4)

                // Phase label with shimmer
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.dsIndigo)

                    Text(phase.rawValue)
                        .font(.dsSubheadline)
                        .foregroundStyle(.dsNavy)
                        .dsTextShimmer(isActive: isProcessing)
                }
            }
            .padding(18)
            .background(Color.dsCardBackground)
            .clipShape(.rect(cornerRadius: 16))
            .modifier(ApplyShadows(shadows: DSShadow.level2))
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var activePhases: [ResearchPhase] {
        [.clarifying, .planning, .searching, .reading, .synthesizing]
    }

    private var progressFraction: CGFloat {
        switch phase {
        case .idle: 0.0
        case .clarifying: 0.15
        case .planning: 0.3
        case .searching: 0.5
        case .reading: 0.7
        case .synthesizing: 0.9
        case .done: 1.0
        }
    }

    private func isPhaseCompleted(_ step: ResearchPhase) -> Bool {
        let order: [ResearchPhase] = [.clarifying, .planning, .searching, .reading, .synthesizing]
        guard let stepIndex = order.firstIndex(of: step),
              let currentIndex = order.firstIndex(of: phase) else { return false }
        return stepIndex < currentIndex
    }
}

// MARK: - Phase Step Indicator

struct PhaseStepIndicator: View {
    let phase: ResearchPhase
    let isActive: Bool
    let isCompleted: Bool

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(isCompleted ? Color.dsIndigo : (isActive ? Color.dsIndigo.opacity(0.15) : Color.dsSurface))
                    .frame(width: 32, height: 32)

                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.dsCaption2)
                        .foregroundStyle(.dsNavy)
                } else {
                    Image(systemName: phaseIcon)
                        .font(.dsCaption2)
                        .foregroundStyle(isActive ? .dsIndigo : .dsSlate)
                }
            }

            Text(phaseLabel)
                .font(.dsCaption2)
                .foregroundStyle(isActive ? .dsNavy : .dsSlate)
        }
        .frame(minWidth: 60)
    }

    private var phaseIcon: String {
        switch phase {
        case .clarifying: "questionmark"
        case .planning: "list.bullet"
        case .searching: "magnifyingglass"
        case .reading: "doc.text"
        case .synthesizing: "text.justify.left"
        default: "circle"
        }
    }

    private var phaseLabel: String {
        switch phase {
        case .clarifying: "Clarify"
        case .planning: "Plan"
        case .searching: "Search"
        case .reading: "Read"
        case .synthesizing: "Synthesize"
        default: ""
        }
    }
}
