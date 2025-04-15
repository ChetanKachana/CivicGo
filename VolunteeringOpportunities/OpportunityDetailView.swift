import SwiftUI
import MapKit       // For Map view
import CoreLocation // For CLGeocoder (address to coordinates)
import FirebaseFirestore // For Timestamp used in Preview mock data

// MARK: - Opportunity Detail View (Simplified)
// Displays the full details of a selected volunteering opportunity,
// including an embedded map. No user interaction features like RSVP.
struct OpportunityDetailView: View {
    // MARK: - Properties
    let opportunity: Opportunity // The specific opportunity data passed to this view

    // MARK: - Map State
    // State variables to manage the embedded map view's appearance and data
    @State private var coordinateRegion: MKCoordinateRegion? = nil // Holds the calculated map region
    @State private var mapMarkerCoordinate: CLLocationCoordinate2D? = nil // Holds the coordinate for the map marker
    @State private var geocodingErrorMessage: String? = nil // Stores errors during map location loading

    // MARK: - Formatters
    // Static formatters for consistent date/time display
    private static var headerDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .full // Example: "Tuesday, October 29, 2024"
        return formatter
    }()
    private static var timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short // Example: "9:00 AM"
        return formatter
    }()

    // MARK: - Body
    var body: some View {
        ScrollView { // Allow content to scroll if it exceeds the screen height
            VStack(alignment: .leading, spacing: 20) { // Main content stack with vertical spacing

                // --- Header: Opportunity Name ---
                Text(opportunity.name)
                    .font(.largeTitle) // Prominent title
                    .fontWeight(.bold)

                Divider() // Visual separator

                // --- When Section ---
                VStack(alignment: .leading, spacing: 8) { // Group date and time
                     // Display full date
                     Text(opportunity.eventDate, formatter: Self.headerDateFormatter)
                         .font(.title3)
                         .fontWeight(.semibold)
                     // Display time range with icon
                     HStack {
                         Image(systemName: "clock.fill")
                             .foregroundColor(.blue) // Themed icon color
                             .frame(width: 20, alignment: .center) // Consistent icon width for alignment
                         Text("\(opportunity.eventDate, formatter: Self.timeFormatter) to \(opportunity.endDate, formatter: Self.timeFormatter)")
                             .font(.body)
                     }
                }

                Divider() // Visual separator

                // --- Where Section ---
                HStack { // Icon + Location Text
                     Image(systemName: "mappin.and.ellipse")
                         .foregroundColor(.red) // Themed icon color
                         .frame(width: 20, alignment: .center) // Consistent icon width
                     Text(opportunity.location) // Display the location string
                         .font(.body)
                 }

                Divider() // Visual separator

                // --- Description Section ---
                VStack(alignment: .leading) {
                    Text("Description")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .padding(.bottom, 4) // Space below title
                    // Display the full, potentially multi-line description
                    Text(opportunity.description)
                        .font(.body)
                        .multilineTextAlignment(.leading) // Align text appropriately
                        .frame(maxWidth: .infinity, alignment: .leading) // Ensure text uses available width and wraps
                }

                // --- RSVP Section has been REMOVED ---

                // --- Location Map Section ---
                Divider() // Separate map section visually
                VStack(alignment: .leading) {
                    Text("Location Map")
                        .font(.title3)
                        .fontWeight(.semibold)
                        .padding(.bottom, 4)

                    // Conditionally display Map, Loading indicator, or Error message
                    if let region = coordinateRegion {
                        // If region data is available, display the map
                        Map(position: .constant(.region(region))) { // Use .constant binding for display only
                            // Add a marker at the calculated coordinate
                            if let coordinate = mapMarkerCoordinate {
                                Marker(opportunity.name, coordinate: coordinate) // Simple map marker with opportunity name
                            }
                        }
                        .frame(height: 250) // Set a fixed height for the map display
                        .clipShape(RoundedRectangle(cornerRadius: 10)) // Apply rounded corners for aesthetics
                        .overlay( // Add a subtle border around the map
                             RoundedRectangle(cornerRadius: 10)
                                 .stroke(Color.gray.opacity(0.5), lineWidth: 1)
                         )
                    } else if let mapError = geocodingErrorMessage {
                        // If geocoding failed, display the error message
                        HStack { // Center error content
                           Spacer()
                           Image(systemName: "exclamationmark.triangle")
                               .foregroundColor(.orange)
                           Text("Could not load map: \(mapError)")
                               .font(.caption)
                               .foregroundColor(.secondary)
                           Spacer()
                        }
                        .frame(height: 250, alignment: .center) // Maintain height for consistency
                    } else {
                        // If geocoding is in progress, show a loading indicator
                        HStack { // Center loading content
                           Spacer()
                           ProgressView() // Standard loading spinner
                           Text("Loading map location...")
                               .font(.caption)
                               .foregroundColor(.secondary)
                           Spacer()
                        }
                        .frame(height: 250, alignment: .center) // Maintain height
                    }
                } // End VStack (Map Section)
                // --- End Location Map Section ---

                Spacer() // Pushes content towards the top if scroll view has extra space
            } // End Main VStack Content
            .padding() // Add padding around the entire content stack
        } // End ScrollView
        .navigationTitle("Opportunity Details") // Set the title for this specific view
        .navigationBarTitleDisplayMode(.inline) // Use inline style for the title in the navigation bar
        .onAppear {
            // When the view appears, trigger the geocoding process to fetch map coordinates
            geocodeAddress()
        }
    } // End body

    // MARK: - Helper Functions

    // Function to convert the opportunity's address string into map coordinates using CLGeocoder
    private func geocodeAddress() {
        // Reset map state before attempting geocoding each time the view appears
        coordinateRegion = nil
        mapMarkerCoordinate = nil
        geocodingErrorMessage = nil

        // Ensure there's a non-empty location string to geocode
        guard !opportunity.location.isEmpty else {
            geocodingErrorMessage = "Address is empty."
            print("Geocoding skipped: Address is empty.")
            return
        }

        print("Starting geocoding for address: \(opportunity.location)")
        let geocoder = CLGeocoder()
        // Asynchronously geocode the address string
        geocoder.geocodeAddressString(opportunity.location) { (placemarks, error) in
            // --- Handle Geocoding Response ---
            // Check for geocoding errors (network, invalid address, etc.)
            if let error = error {
                self.geocodingErrorMessage = error.localizedDescription // Store user-friendly error
                print("Geocoding failed: \(error.localizedDescription)")
                return // Stop processing on error
            }

            // Ensure a placemark and coordinates were successfully found
            guard let placemark = placemarks?.first, let location = placemark.location else {
                self.geocodingErrorMessage = "Address not found."
                print("Geocoding failed: Address not found or no location coordinate.")
                return // Stop processing if no valid location found
            }

            // --- Geocoding Success: Update Map State ---
            let coordinate = location.coordinate
            self.mapMarkerCoordinate = coordinate // Set the coordinate for the map Marker
            // Create and set the map region to center on the coordinate with a specific zoom level
            self.coordinateRegion = MKCoordinateRegion(
                center: coordinate,
                latitudinalMeters: 1000, // Approx 1km vertical radius (adjust for desired zoom)
                longitudinalMeters: 1000 // Approx 1km horizontal radius (adjust for desired zoom)
            )
            print("Geocoding successful: \(coordinate.latitude), \(coordinate.longitude)")
            // The @State variables changing trigger SwiftUI to update the view and display the map/marker
        }
    } // End geocodeAddress

} // End struct OpportunityDetailView

