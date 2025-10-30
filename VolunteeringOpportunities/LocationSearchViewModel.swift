import Foundation
import MapKit
import Combine 

class LocationSearchViewModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {

    @Published var queryFragment: String = ""
    @Published var searchResults: [MKLocalSearchCompletion] = []

    private var searchCompleter: MKLocalSearchCompleter
    private var cancellable: AnyCancellable?

    override init() {
        searchCompleter = MKLocalSearchCompleter()
        super.init()
        searchCompleter.delegate = self
        print("--- LocationSearchViewModel Initialized ---")

        cancellable = $queryFragment
            .debounce(for: .milliseconds(300), scheduler: RunLoop.main)
            .removeDuplicates()
            .sink { [weak self] newQuery in
                guard let self = self else { return }
                print("--- Query Fragment Sink Received: '\(newQuery)' ---")
                if !newQuery.isEmpty {
                    print("--- Setting searchCompleter.queryFragment to: '\(newQuery)' ---")
                    self.searchCompleter.queryFragment = newQuery
                } else {
                    print("--- Query Fragment Empty, Clearing Results ---")
                    self.searchResults = []
                }
            }
    }

    // MARK: - MKLocalSearchCompleterDelegate Methods

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        self.searchResults = completer.results
        print("--- completerDidUpdateResults --- Found \(searchResults.count) results.")
    
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
   
        print("--- completer didFailWithError --- Error: \(error.localizedDescription)")
        self.searchResults = []
    }
}
