import SwiftUI
import FirebaseFirestore

// MARK: - Leaderboard View
struct LeaderboardView: View {
    // MARK: - State and Environment
    @StateObject private var viewModel = LeaderboardViewModel()
    @Environment(\.dismiss) var dismiss

    @Namespace private var filterAnimation

    // MARK: - Body
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if !(viewModel.isLoading && viewModel.rankedUsers.isEmpty) {
                    filterBar
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                }

                Divider()

                Group {
                    if viewModel.isLoading {
                        ProgressView("Loading Leaderboard...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let error = viewModel.errorMessage {
                        ErrorStateView(message: error)
                            .frame(maxHeight: .infinity)
                    } else if viewModel.rankedUsers.isEmpty {
                        EmptyStateView(message: "No attendance data found for '\(viewModel.selectedTimeFilter.rawValue)'.")
                            .frame(maxHeight: .infinity)
                    } else {
                        leaderboardList
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            }
            .navigationTitle("Leaderboard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { dismiss() } label: {
                         Image(systemName: "xmark.circle.fill")
                             .imageScale(.large)
                             .foregroundStyle(.gray)
                    }
                }
            }
            .task {
                if viewModel.rankedUsers.isEmpty {
                     await viewModel.fetchLeaderboardData()
                }
            }
            .refreshable {
                 await viewModel.fetchLeaderboardData()
            }
            .overlay(alignment: .bottom) {
                errorOverlay
            }
            .animation(.default, value: viewModel.errorMessage != nil)

        }
    }

    // MARK: - Extracted View Builders

    private var filterBar: some View {
        HStack(spacing: 0) {
            ForEach(LeaderboardViewModel.TimeFilter.allCases) { filter in
                filterButton(for: filter)
                    .padding(.horizontal, 8)
            }
        }
        .frame(height: 36)
        .padding(.vertical, 4)
        .background( Capsule().fill(Color(.systemGray5)) )
        .animation(.default, value: viewModel.selectedTimeFilter)
    }

    private func filterButton(for filter: LeaderboardViewModel.TimeFilter) -> some View {
        Button {
            withAnimation(.interactiveSpring(response: 0.1, dampingFraction: 0.7, blendDuration: 0.1)) {
                viewModel.selectedTimeFilter = filter
            }
            viewModel.filterChanged()
            print("Leaderboard Filter selected: \(filter.rawValue)")
        } label: {
            Text(filter.rawValue)
                .font(.system(size: 13, weight: .medium))
                .padding(.vertical, 6)
                .padding(.horizontal, 14)
                .background {
                    if viewModel.selectedTimeFilter == filter {
                        Capsule()
                            .fill(Color(.systemBackground))
                            .shadow(color: .black.opacity(0.1), radius: 2, x: 0, y: 1)
                            .matchedGeometryEffect(id: "leaderboardFilterHighlight", in: filterAnimation)
                    }
                }
                .foregroundColor(viewModel.selectedTimeFilter == filter ? Color(.label) : Color(.secondaryLabel))
        }
        .buttonStyle(.plain)
    }

    private var leaderboardList: some View {
        List {
            HStack {
                Text("#").font(.caption).fontWeight(.semibold).frame(width: 35, alignment: .leading)
                Text("User").font(.caption).fontWeight(.semibold)
                Spacer()
                Text("Hours").font(.caption).fontWeight(.semibold).frame(width: 60, alignment: .trailing)
            }
            .foregroundStyle(.secondary)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 5, leading: 16, bottom: 5, trailing: 16))

            ForEach(viewModel.rankedUsers) { user in
                HStack {
                    Text("\(user.rank ?? 0)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(width: 35, alignment: .leading)

                    Text(user.username)
                        .font(.subheadline)
                        .lineLimit(1)

                    Spacer()

                    Text(formatHours(user.totalHours))
                        .font(.subheadline.monospacedDigit())
                        .fontWeight(.medium)
                        .frame(width: 60, alignment: .trailing)
                }
                .listRowBackground(rankBackgroundColor(for: user.rank))
                .listRowSeparator(.hidden)
                .padding(.vertical, 6)
            }
        }
        .listStyle(.plain)
        .contentMargins(.horizontal, 0, for: .scrollContent)
    }

    @ViewBuilder
    private var errorOverlay: some View {
        if let error = viewModel.errorMessage {
             Text(error)
                 .font(.caption).foregroundColor(.white).padding(10)
                 .background(Color.black.opacity(0.75), in: Capsule())
                 .padding(.bottom)
                 .transition(.opacity.combined(with: .move(edge: .bottom)))
                 .id("ErrorOverlay_\(error)")
         }
     }


    // MARK: - Helper Functions

    private func formatHours(_ hours: Double) -> String {
        return String(format: "%.1f", hours).replacingOccurrences(of: ".0", with: "")
    }

    private func rankBackgroundColor(for rank: Int?) -> Color? {
        guard let rank = rank else { return nil }
        switch rank {
        case 1: return Color.red.opacity(0.15)
        case 2: return Color.orange.opacity(0.15)
        case 3: return Color.green.opacity(0.15)
        default: return nil
        }
    }

    // MARK: - Helper Empty/Error Views (Defined inline for completeness)
    struct EmptyStateView: View {
        let message: String
        var body: some View {
             VStack { Spacer(); Image(systemName: "chart.bar.xaxis").font(.system(size: 50)).foregroundColor(.secondary); Text(message).foregroundColor(.secondary).multilineTextAlignment(.center).padding(); Spacer() }
        }
    }
     struct ErrorStateView: View {
        let message: String
        var body: some View {
             VStack { Spacer(); Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red).font(.largeTitle); Text(message).foregroundColor(.red).multilineTextAlignment(.center).padding(.top, 4); Spacer() }.padding()
        }
    }

}
