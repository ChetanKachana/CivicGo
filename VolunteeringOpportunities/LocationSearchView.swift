import SwiftUI
import MapKit // Import MapKit

struct LocationSearchView: View {
    // Use StateObject for the ViewModel handling search logic
    @StateObject private var viewModel = LocationSearchViewModel()

    // Binding to update the location string in the parent view (CreateOpportunityView)
    @Binding var selectedLocationString: String

    // Environment variable to dismiss the sheet
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView { // Embed in NavigationView for title and potentially cancel button
            VStack {
                // List to display search results
                List(viewModel.searchResults, id: \.self) { completion in
                    VStack(alignment: .leading) {
                        Text(completion.title)
                            .font(.headline)
                        Text(completion.subtitle)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .contentShape(Rectangle()) // Make the whole area tappable
                    .onTapGesture {
                        // Construct the full address string (often title + subtitle)
                        let fullAddress = "\(completion.title), \(completion.subtitle)"
                        selectedLocationString = fullAddress // Update the binding
                        print("Location selected: \(fullAddress)")
                        dismiss() // Dismiss the sheet
                    }
                }
                .listStyle(.plain) // Use plain style for search results
            }
            .navigationTitle("Search Location")
            .navigationBarTitleDisplayMode(.inline)
            // --- Search Bar ---
            // Use the .searchable modifier attached to the List or VStack
            .searchable(text: $viewModel.queryFragment,
                        placement: .navigationBarDrawer(displayMode: .always), // Always show search bar
                        prompt: "Search for an address or place")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss() // Just dismiss without selecting
                    }
                }
            }
        }
    }
}
