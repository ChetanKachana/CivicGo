import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth

// MARK: - Leaderboard View Model
class LeaderboardViewModel: ObservableObject {

    // MARK: - Published Properties
    @Published var rankedUsers: [RankedUser] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var selectedTimeFilter: TimeFilter = .total
    @Published var lastUpdatedAt: Date? = nil

    // MARK: - Time Filter Enum
    enum TimeFilter: String, CaseIterable, Identifiable {
        case monthly = "This Month"
        case annually = "This Year"
        case total = "All Time"
        var id: String { self.rawValue }
    }

    // MARK: - Ranked User Struct
    struct RankedUser: Identifiable, Equatable, Hashable {
        let id: String
        var rank: Int? = nil
        var username: String
        var totalHours: Double = 0.0
    }

    // MARK: - Private Properties
    private let db = Firestore.firestore()
    private var opportunitiesListener: ListenerRegistration?
    private var usersListener: ListenerRegistration?
    private var usernameCache: [String: String] = [:]
    private var allOpportunities: [Opportunity] = []


    // MARK: - Initialization
    init() {
        print("LeaderboardViewModel Initialized")
    }

    // MARK: - Deinitialization
    deinit {
        print("LeaderboardViewModel Deinitialized")
    }

    // MARK: - Data Fetching and Calculation

    @MainActor
    func fetchLeaderboardData() async {
        guard !isLoading else {
            print("Leaderboard fetch skipped: Already loading.")
            return
        }

        print("Starting leaderboard data fetch for filter: \(selectedTimeFilter.rawValue)...")
        isLoading = true
        errorMessage = nil

        do {
            let opportunitySnapshots = try await db.collection("volunteeringOpportunities").getDocuments()
            self.allOpportunities = opportunitySnapshots.documents.compactMap { Opportunity(snapshot: $0) }
            print("Fetched \(self.allOpportunities.count) total opportunities.")

            let userSnapshots = try await db.collection("users").getDocuments()
            let allUsers = userSnapshots.documents

            print("Fetched \(allUsers.count) total users.")

            var userHours: [String: Double] = [:]
            let calendar = Calendar.current
            let now = Date()

            let dateRange: ClosedRange<Date>?
            switch selectedTimeFilter {
            case .monthly:
                if let monthInterval = calendar.dateInterval(of: .month, for: now) {
                    dateRange = monthInterval.start ... monthInterval.end
                } else { dateRange = nil }
            case .annually:
                 if let yearInterval = calendar.dateInterval(of: .year, for: now) {
                    dateRange = yearInterval.start ... yearInterval.end
                } else { dateRange = nil }
            case .total:
                dateRange = nil
            }
             print("Date range for filter '\(selectedTimeFilter.rawValue)': \(dateRange?.description ?? "All Time")")


            for opportunity in self.allOpportunities {
                if let range = dateRange, !range.contains(opportunity.eventDate) {
                    continue
                }

                guard let attendance = opportunity.attendanceRecords, !attendance.isEmpty else { continue }

                for (attendeeId, status) in attendance {
                    if status.lowercased() == "present" {
                        let duration = opportunity.durationHours ?? 0.0
                        userHours[attendeeId, default: 0.0] += duration
                    }
                }
            }
            print("Calculated hours for \(userHours.count) users.")


            var usersToRank: [RankedUser] = []
            for (userId, hours) in userHours where hours > 0 {
                var username = self.usernameCache[userId]
                if username == nil {
                     let userDoc = allUsers.first(where: { $0.documentID == userId })
                    username = userDoc?.data()["username"] as? String
                     if let nameToCache = username?.nilIfEmpty {
                         self.usernameCache[userId] = nameToCache
                     }
                }
                let displayName = username?.nilIfEmpty ?? "User \(userId.prefix(4))..."

                usersToRank.append(RankedUser(id: userId, username: displayName, totalHours: hours))
            }


            usersToRank.sort { $0.totalHours > $1.totalHours }

            var finalRankedList: [RankedUser] = []
            var currentRank = 0
            var previousHours = -1.0
            for var user in usersToRank {
                if user.totalHours != previousHours {
                    currentRank += 1
                }
                user.rank = currentRank
                finalRankedList.append(user)
                previousHours = user.totalHours
            }

            self.rankedUsers = finalRankedList
            self.lastUpdatedAt = Date()
            self.isLoading = false
            print("Leaderboard updated. Filter: \(selectedTimeFilter.rawValue), Ranks: \(finalRankedList.count)")

        } catch {
            print("!!! Error fetching leaderboard data: \(error.localizedDescription)")
            self.errorMessage = "Failed to load leaderboard: \(error.localizedDescription)"
            self.isLoading = false
            self.rankedUsers = []
        }
    }

    // MARK: - Filter Change Action
    func filterChanged() {
        Task {
             await fetchLeaderboardData()
        }
    }

}
