import SwiftUI

// MARK: - Location Link View
// A reusable view that displays a location string. If the location is valid
// and can be formed into an Apple Maps URL, it renders as a tappable link
// that opens the Maps app. Otherwise, it displays as non-tappable text.
struct LocationLinkView: View {
    // MARK: - Properties
    let location: String // The address or location name string to display/link.

    // MARK: - Private Helper
    // Creates a URL for Apple Maps search, properly encoding the address string.
    private func mapsURL(for address: String) -> URL? {
        // Ensure the address string can be percent-encoded for use in a URL query.
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            print("Warning: Could not URL-encode address: \(address)")
            return nil // Return nil if encoding fails.
        }
        // Construct the URL using the standard scheme that iOS intercepts for Apple Maps search.
        return URL(string: "http://maps.apple.com/?q=\(encodedAddress)")
    }

    // MARK: - Body
    var body: some View {
        // Attempt to create the Maps URL from the location string.
        if let url = mapsURL(for: location), !location.isEmpty {
            // --- Tappable Link ---
            // If the URL is valid and the location string is not empty, render a Link.
            Link(destination: url) { // Destination is the generated Maps URL.
                HStack(spacing: 4) { // Group icon and text horizontally.
                     Image(systemName: "mappin.and.ellipse") // Standard map pin icon.
                         .font(.subheadline) // Match the text font size.
                         .foregroundColor(.secondary) // Use a standard, less prominent color.
                     Text(location) // The location string serves as the link text.
                         .font(.subheadline) // Match icon size.
                         .foregroundColor(.accentColor) // Use the app's accent color to indicate it's tappable.
                         .lineLimit(1) // Prevent the location from wrapping onto multiple lines in list rows.
                }
            }
            // Apply plain button style so the link interaction doesn't add extra visual chrome.
            .buttonStyle(.plain)

        } else if !location.isEmpty {
            // --- Non-Tappable Text Fallback ---
            // If the URL couldn't be created (e.g., encoding failed) but the location string
            // is not empty, display it as regular text.
            HStack(spacing: 4) { // Icon + Text layout.
               Image(systemName: "mappin.and.ellipse") // Still show the icon for context.
                   .font(.subheadline)
                   .foregroundColor(.secondary)
               Text(location) // Display the location string.
                   .font(.subheadline)
                   .foregroundColor(.gray) // Use gray to indicate it's not interactive.
                   .lineLimit(1)
           }
        }
        // Implicit else: If the location string *is* empty, render nothing.
    }
}

