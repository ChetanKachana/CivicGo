import SwiftUI
import FirebaseFirestore

struct CreateOpportunityView: View {
    // MARK: - Environment & State (Keep all existing ones)
    @EnvironmentObject var viewModel: OpportunityViewModel
    @Environment(\.dismiss) var dismiss

    @State private var name: String = ""
    @State private var location: String = ""
    @State private var description: String = ""
    @State private var eventDate: Date = Date()
    @State private var endDate: Date = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
    @State private var showingLocationSearchSheet = false
    @State private var saveAttempted: Bool = false
    @FocusState private var isDescriptionEditorFocused: Bool // Ensure this is kept

    // MARK: - Computed Validation Properties (Keep existing ones)
    private var isEndTimeValid: Bool { endDate > eventDate }
    private var canSubmit: Bool {
        !viewModel.isLoading && !name.isEmpty && !location.isEmpty && isEndTimeValid
    }

    // MARK: - Body (Refactored)
    var body: some View {
        NavigationView {
            Form {
                // --- Use Extracted Views ---
                detailsSection
                dateTimeSection
                // --- End Extracted Views ---

                // --- Keep Conditional Sections Inline (often less complex) ---
                // Error Display Section
                if let errorMessage = viewModel.errorMessage, saveAttempted && !viewModel.isLoading {
                    Section {
                        HStack {
                           Image(systemName: "exclamationmark.circle.fill")
                               .foregroundColor(.red)
                           Text("Error: \(errorMessage)")
                               .foregroundColor(.red)
                        }
                    }
                }

                // Create Button Section
                Section {
                    Button("Create Opportunity") {
                        saveOpportunity()
                    }
                    .disabled(!canSubmit)
                }

                // Loading Indicator Section
                if viewModel.isLoading {
                    Section {
                        HStack {
                            Spacer()
                            ProgressView("Saving...")
                            Spacer()
                        }
                    }
                }
                // --- End Conditional Sections ---

            } // End Form
            .navigationTitle("New Opportunity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { // Keep Toolbar
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        viewModel.errorMessage = nil
                        saveAttempted = false
                        dismiss()
                    }
                }
            } // End Toolbar
            // --- Keep All Modifiers ---
            .onChange(of: viewModel.isLoading) { oldIsLoading, newIsLoading in
                 // Dismissal logic...
                if saveAttempted && oldIsLoading == true && newIsLoading == false {
                    if viewModel.errorMessage == nil { print("Save successful, dismissing sheet."); dismiss() }
                    else { print("Save failed, keeping sheet open.") }
                }
            }
            .onChange(of: eventDate) { oldDate, newDate in
                 // Auto-adjust end time...
                 if endDate <= newDate {
                     endDate = Calendar.current.date(byAdding: .hour, value: 1, to: newDate) ?? newDate
                 }
             }
            .sheet(isPresented: $showingLocationSearchSheet) { // Keep Sheet
                LocationSearchView(selectedLocationString: $location)
            }
            .onDisappear { // Keep onDisappear
                 if !viewModel.isLoading {
                     saveAttempted = false
                     viewModel.errorMessage = nil
                     print("Sheet disappeared, resetting saveAttempted and error.")
                 }
            }
            // --- End Modifiers ---
        } // End NavigationView
    } // End body

    // MARK: - Extracted Subview Properties

    // --- Extracted: Opportunity Details Section ---
    private var detailsSection: some View {
        Section(header: Text("Opportunity Details")) {
            TextField("Opportunity name", text: $name)

            // Location Selection Row
            HStack {
                VStack(alignment: .leading) {
                    Text("Location").font(.caption).foregroundStyle(.secondary)
                    Text(location.isEmpty ? "Select Location" : location)
                        .lineLimit(2)
                        .foregroundColor(location.isEmpty ? .secondary : .primary)
                }
                Spacer()
                Button {
                    showingLocationSearchSheet = true
                } label: {
                    HStack{
                        Text("Add Location")
                        Image(systemName: "magnifyingglass")
                    }
                    
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.placeholder)
                
            }

            // Description TextEditor with Placeholder
            TextField("Add a description", text: $description, axis: .vertical)
                .lineLimit(5, reservesSpace: true)
        }
    }

    // --- Extracted: Date and Time Section ---
    private var dateTimeSection: some View {
        Section(header: Text("Date and Time")) {
            DatePicker("Starts", selection: $eventDate)
            DatePicker("Ends", selection: $endDate)

            // Validation Feedback
            if !isEndTimeValid {
                Text("End time must be after start time.")
                    .font(.caption)
                    .foregroundColor(.red)
            }
        }
    }

    // MARK: - Actions (Keep existing saveOpportunity function)
    func saveOpportunity() {
        isDescriptionEditorFocused = false // Dismiss keyboard
        viewModel.errorMessage = nil
        saveAttempted = true
        print("Save button tapped, setting saveAttempted = true")
        viewModel.addOpportunity(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            location: location,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            eventDate: eventDate,
            endDate: endDate
        )
    }

} // End struct
