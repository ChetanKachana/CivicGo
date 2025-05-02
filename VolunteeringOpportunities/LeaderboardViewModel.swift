import Foundation
import Combine
import FirebaseFirestore
import FirebaseAuth // To potentially ignore current user if needed, or get user ID

// MARK: - Leaderboard View Model
// Fetches data and calculates user rankings based on attended volunteer hours.
class LeaderboardViewModel: ObservableObject {

    // MARK: - Published Properties
    @Published var rankedUsers: [RankedUser] = [] // Sorted list of users with ranks and hours
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil
    @Published var selectedTimeFilter: TimeFilter = .total // Default filter
    @Published var lastUpdatedAt: Date? = nil          // To show data freshness

    // MARK: - Time Filter Enum
    enum TimeFilter: String, CaseIterable, Identifiable {
        case monthly = "This Month"
        case annually = "This Year"
        case total = "All Time"
        var id: String { self.rawValue }
    }

    // MARK: - Ranked User Struct
    // Represents a user's entry on the leaderboard
    struct RankedUser: Identifiable, Equatable, Hashable {
        let id: String // User ID
        var rank: Int? = nil // Calculated rank (optional for sorting before ranking)
        var username: String
        var totalHours: Double = 0.0
    }

    // MARK: - Private Properties
    private let db = Firestore.firestore()
    private var opportunitiesListener: ListenerRegistration? // Optional: Listen for opportunity changes?
    private var usersListener: ListenerRegistration?       // Optional: Listen for user name changes?
    // Cache for fetched usernames to avoid redundant fetches if listening isn't used
    private var usernameCache: [String: String] = [:]
    private var allOpportunities: [Opportunity] = [] // Store fetched opportunities


    // MARK: - Initialization
    init() {
        print("LeaderboardViewModel Initialized")
        // Initial fetch or fetch when view appears? Fetch on appear is often better.
        // fetchLeaderboardData()
    }

    // MARK: - Deinitialization
    deinit {
        print("LeaderboardViewModel Deinitialized")
        // Remove listeners if they were implemented
        // opportunitiesListener?.remove()
        // usersListener?.remove()
    }

    // MARK: - Data Fetching and Calculation

    /// Fetches all necessary data (users, opportunities) and calculates rankings.
    @MainActor // Ensure UI updates happen on main thread
    func fetchLeaderboardData() async {
        // Avoid concurrent fetches
        guard !isLoading else {
            print("Leaderboard fetch skipped: Already loading.")
            return
        }

        print("Starting leaderboard data fetch for filter: \(selectedTimeFilter.rawValue)...")
        isLoading = true
        errorMessage = nil
        // Clear previous rankings before recalculating
        // rankedUsers = [] // Clear immediately or only on success? Clear on success is safer.

        do {
            // 1. Fetch ALL Opportunities (Consider adding date filters for efficiency later)
            // Using async/await for cleaner fetch logic
            let opportunitySnapshots = try await db.collection("volunteeringOpportunities").getDocuments()
            // Map snapshots to Opportunity objects, filter out invalid ones
            self.allOpportunities = opportunitySnapshots.documents.compactMap { Opportunity(snapshot: $0) }
            print("Fetched \(self.allOpportunities.count) total opportunities.")

            // 2. Fetch ALL Users (Needed for usernames and iterating)
            // WARNING: Fetching all users is inefficient and potentially costly at scale!
            // Consider fetching only users present in attendance records if possible,
            // or using a Cloud Function to maintain aggregate data.
            let userSnapshots = try await db.collection("users").getDocuments()
            let allUsers = userSnapshots.documents // Keep as snapshots for now

            print("Fetched \(allUsers.count) total users.")

            // 3. Calculate Hours per User based on Filter
            var userHours: [String: Double] = [:] // [UserID: Hours]
            let calendar = Calendar.current
            let now = Date()

            // Define date range based on filter
            let dateRange: ClosedRange<Date>?
            switch selectedTimeFilter {
            case .monthly:
                if let monthInterval = calendar.dateInterval(of: .month, for: now) {
                    dateRange = monthInterval.start ... monthInterval.end // Start of month to end of month
                } else { dateRange = nil }
            case .annually:
                 if let yearInterval = calendar.dateInterval(of: .year, for: now) {
                    dateRange = yearInterval.start ... yearInterval.end // Start of year to end of year
                } else { dateRange = nil }
            case .total:
                dateRange = nil // No date range filtering needed
            }
             print("Date range for filter '\(selectedTimeFilter.rawValue)': \(dateRange?.description ?? "All Time")")


            // Iterate through opportunities to aggregate hours
            for opportunity in self.allOpportunities {
                // Skip if opportunity doesn't fall within the date range (if applicable)
                if let range = dateRange, !range.contains(opportunity.eventDate) {
                    continue // Skip this opportunity if it's outside the filter range
                }

                // Iterate through recorded attendees for this opportunity
                guard let attendance = opportunity.attendanceRecords, !attendance.isEmpty else { continue }

                for (attendeeId, status) in attendance {
                    // Only count hours if marked "present"
                    if status.lowercased() == "present" {
                        let duration = opportunity.durationHours ?? 0.0 // Get duration, default 0
                        userHours[attendeeId, default: 0.0] += duration // Add to user's total
                    }
                }
            }
            print("Calculated hours for \(userHours.count) users.")


            // 4. Create RankedUser objects (fetch usernames)
            var usersToRank: [RankedUser] = []
            // Use a TaskGroup for potentially faster username fetching if needed,
            // but simple loop is fine for moderate numbers. Fetching missing names now.
            for (userId, hours) in userHours where hours > 0 { // Only rank users with > 0 hours
                // Try cache first
                var username = self.usernameCache[userId]
                // If not cached, fetch it
                if username == nil {
                     let userDoc = allUsers.first(where: { $0.documentID == userId })
                    username = userDoc?.data()["username"] as? String
                     // Update cache
                     if let nameToCache = username?.nilIfEmpty {
                         self.usernameCache[userId] = nameToCache
                     }
                }
                // Use fetched/cached username or a default/fallback
                let displayName = username?.nilIfEmpty ?? "User \(userId.prefix(4))..."

                usersToRank.append(RankedUser(id: userId, username: displayName, totalHours: hours))
            }


            // 5. Sort by Hours (Descending) and Assign Ranks
            usersToRank.sort { $0.totalHours > $1.totalHours } // Highest hours first

            var finalRankedList: [RankedUser] = []
            var currentRank = 0
            var previousHours = -1.0 // Ensure first user gets rank 1
            for var user in usersToRank {
                // Increment rank only if hours are different from previous user
                if user.totalHours != previousHours {
                    currentRank += 1
                }
                user.rank = currentRank // Assign the rank
                finalRankedList.append(user)
                previousHours = user.totalHours // Update previous hours for next iteration
            }

            // 6. Update Published Properties
            self.rankedUsers = finalRankedList
            self.lastUpdatedAt = Date() // Record refresh time
            self.isLoading = false
            print("Leaderboard updated. Filter: \(selectedTimeFilter.rawValue), Ranks: \(finalRankedList.count)")

        } catch {
            // Handle errors from fetching opportunities or users
            print("!!! Error fetching leaderboard data: \(error.localizedDescription)")
            self.errorMessage = "Failed to load leaderboard: \(error.localizedDescription)"
            self.isLoading = false
            self.rankedUsers = [] // Clear ranks on error
        }
    }

    // MARK: - Filter Change Action
    /// Called when the filter selection changes in the UI. Triggers a data refetch.
    func filterChanged() {
        // Don't clear existing data immediately, let fetch replace it
        // rankedUsers = []
        Task {
             await fetchLeaderboardData()
        }
    }

} // End Class LeaderboardViewModel


// Helper extension (ensure defined only once in your project)
