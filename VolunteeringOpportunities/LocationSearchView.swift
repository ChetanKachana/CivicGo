import SwiftUI
import MapKit

struct LocationSearchView: View {
    @StateObject private var viewModel = LocationSearchViewModel()

    @Binding var selectedLocationString: String

    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            VStack {
                List(viewModel.searchResults, id: \.self) { completion in
                    VStack(alignment: .leading) {
                        Text(completion.title)
                            .font(.headline)
                        Text(completion.subtitle)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        let fullAddress = "\(completion.title), \(completion.subtitle)"
                        selectedLocationString = fullAddress
                        print("Location selected: \(fullAddress)")
                        dismiss()
                    }
                }
                .listStyle(.plain)
            }
            .navigationTitle("Search Location")
            .navigationBarTitleDisplayMode(.inline)
            
            .searchable(text: $viewModel.queryFragment,
                        placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Search for an address or place")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}
