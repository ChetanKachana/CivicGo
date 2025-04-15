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

        // Use Combine to debounce search query updates
        cancellable = $queryFragment
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main) // Wait 300ms after user stops typing
            .removeDuplicates() // Don't search if the text hasn't changed
            .sink { [weak self] newQuery in
                guard let self = self else { return }
                if !newQuery.isEmpty {
                    print("Searching for: \(newQuery)")
                    self.searchCompleter.queryFragment = newQuery
                } else {
                    // Clear results if query is empty
                    self.searchResults = []
                }
            }
    }

    // MARK: - MKLocalSearchCompleterDelegate Methods

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        // Update the published results when the completer finds matches
        // Filter out results without subtitles if desired (often more specific)
        // self.searchResults = completer.results.filter { !$0.subtitle.isEmpty }
        self.searchResults = completer.results
        print("Found \(searchResults.count) results.")
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        // Handle search errors (e.g., network issues)
        print("Location search failed with error: \(error.localizedDescription)")
        self.searchResults = [] // Clear results on error
    }
}
