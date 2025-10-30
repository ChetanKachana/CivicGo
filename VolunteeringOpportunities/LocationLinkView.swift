import SwiftUI

// MARK: - Location Link View

struct LocationLinkView: View {
    // MARK: - Properties
    let location: String

    // MARK: - Private Helper
    private func mapsURL(for address: String) -> URL? {
        guard let encodedAddress = address.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            print("Warning: Could not URL-encode address: \(address)")
            return nil
        }
        return URL(string: "http://maps.apple.com/?q=\(encodedAddress)")
    }

    // MARK: - Body
    var body: some View {
        if let url = mapsURL(for: location), !location.isEmpty {
           
            Link(destination: url) {
                HStack(spacing: 4) {
                     Image(systemName: "mappin.and.ellipse")
                         .font(.subheadline)
                         .foregroundColor(.secondary)
                     Text(location)
                         .font(.subheadline)
                         .foregroundColor(.accentColor)
                         .lineLimit(1)
                }
            }
            .buttonStyle(.plain)

        } else if !location.isEmpty {
          
            HStack(spacing: 4) {
               Image(systemName: "mappin.and.ellipse")
                   .font(.subheadline)
                   .foregroundColor(.secondary)
               Text(location)
                   .font(.subheadline)
                   .foregroundColor(.gray)
                   .lineLimit(1)
           }
        }
    }
}

