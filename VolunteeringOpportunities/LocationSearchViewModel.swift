import Foundation
import MapKit // Import MapKit
import Combine // Import Combine for ObservableObject

// Delegate class to handle search completions
class LocationSearchViewModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {

    // Published properties to update the UI
    @Published var queryFragment: String = "" // The text being searched
    @Published var searchResults: [MKLocalSearchCompletion] = [] // Array of results

    private var searchCompleter: MKLocalSearchCompleter // The MapKit object doing the work
    private var cancellable: AnyCancellable? // To manage the query updates

    override init() {
        searchCompleter = MKLocalSearchCompleter()
        super.init()
        searchCompleter.delegate = self // Set this class as the delegate
        print("--- LocationSearchViewModel Initialized ---") // <-- ADD INIT LOG

        // Use Combine to debounce search query updates
        cancellable = $queryFragment
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main) // Wait 300ms
            .removeDuplicates() // Don't search if text hasn't changed
            .sink { [weak self] newQuery in
                guard let self = self else { return }
                print("--- Query Fragment Sink Received: '\(newQuery)' ---") // <-- ADD SINK LOG
                if !newQuery.isEmpty {
                    print("--- Setting searchCompleter.queryFragment to: '\(newQuery)' ---") // <-- ADD SEARCH LOG
                    self.searchCompleter.queryFragment = newQuery
                } else {
                    print("--- Query Fragment Empty, Clearing Results ---") // <-- ADD CLEAR LOG
                    // Clear results if query is empty
                    self.searchResults = []
                }
            }
    }

    // MARK: - MKLocalSearchCompleterDelegate Methods

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        // Update the published results when the completer finds matches
        self.searchResults = completer.results
        // --- ADD RESULTS LOG ---
        print("--- completerDidUpdateResults --- Found \(searchResults.count) results.")
        // Optional: Log the actual results
        // searchResults.forEach { print("    - \($0.title), \($0.subtitle)") }
        // --- END LOG ---
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        // Handle search errors (e.g., network issues)
        // --- ADD ERROR LOG ---
        print("--- completer didFailWithError --- Error: \(error.localizedDescription)")
        // --- END LOG ---
        self.searchResults = [] // Clear results on error
    }
}
