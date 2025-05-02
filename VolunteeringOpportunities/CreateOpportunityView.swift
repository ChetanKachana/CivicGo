import SwiftUI
import FirebaseFirestore // Needed for Timestamp if used in previews
// Removed MapKit import as it's not directly used in this view after removing the test

// MARK: - Create/Edit Opportunity View (Single Day Event)
// A modal view presented for either creating a new opportunity or editing an existing one.
// Uses separate Date and Time pickers for start/end, ensuring event is on a single day.
// Includes fields for setting an attendee limit.
struct CreateOpportunityView: View {
    // MARK: - Environment Objects and State
    @EnvironmentObject var viewModel: OpportunityViewModel        // Access add/update actions and state
    @EnvironmentObject var authViewModel: AuthenticationViewModel // Access auth state (implicitly manager-only view)
    @Environment(\.dismiss) var dismiss                          // Action to close the sheet

    // --- Mode Determination ---
    let opportunityToEdit: Opportunity? // If non-nil, we are in "Edit" mode

    // --- Form Input State Variables ---
    @State private var name: String = ""
    @State private var location: String = "" // Updated via LocationSearchView binding
    @State private var description: String = ""
    @State private var eventDate: Date = Date()    // Stores the selected DATE and START TIME
    @State private var endTime: Date = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date() // Stores ONLY the END TIME component

    // State for Attendee Limit
    @State private var maxAttendeesString: String = "" // Use String for TextField input
    @State private var hasUnlimitedSpots: Bool = true  // Toggle for unlimited spots

    // --- UI Control State ---
    @State private var showingLocationSearchSheet = false // Controls location search modal
    @State private var saveAttempted: Bool = false      // Tracks if save/update was initiated
    @FocusState private var isDescriptionEditorFocused: Bool // To dismiss keyboard for description
    @FocusState private var isMaxAttendeesFocused: Bool    // To dismiss keyboard for number input
    // Removed temporary MKLocalSearch test state variables

    // MARK: - Computed Properties
    private var isEditing: Bool { opportunityToEdit != nil }
    private var navigationTitle: String { isEditing ? "Edit Opportunity" : "New Opportunity" }
    private var saveButtonText: String { isEditing ? "Update Opportunity" : "Create Opportunity" }

    // Validation: Check if selected end time is actually after the start time on the chosen date
    private var isEndTimeValid: Bool {
        guard let combinedEndDate = viewModel.combine(date: eventDate, time: endTime) else { return false }
        return combinedEndDate > eventDate
    }
    // Validation for Max Attendees TextField
    private var isMaxAttendeesValid: Bool {
        if hasUnlimitedSpots { return true }
        guard let maxInt = Int(maxAttendeesString.trimmingCharacters(in: .whitespaces)), maxInt >= 1 else { return false }
        return true
    }
    // Get Int? value for saving attendee limit
     private var maxAttendeesIntValue: Int? {
         if hasUnlimitedSpots { return nil }
         guard let maxInt = Int(maxAttendeesString.trimmingCharacters(in: .whitespaces)), maxInt >= 1 else { return nil }
         return maxInt
     }
    // Validation for enabling the save/update button
    private var canSubmit: Bool {
        !viewModel.isLoading &&
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !location.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        isEndTimeValid &&
        isMaxAttendeesValid
    }


    // MARK: - Body
    var body: some View {
        NavigationView {
            Form {
                detailsSection      // Name, Location, Description
                dateTimeSection     // Start/End Date & Time
                attendeeLimitSection // Attendee Limit configuration

                // Temporary MKLocalSearch Test Section REMOVED

                // Error Display Section for main save/update
                if let errorMessage = viewModel.errorMessage, !viewModel.isLoading {
                    Section { ErrorDisplay(message: errorMessage) }
                }

                // Create/Update Button Section for main save/update
                Section {
                    Button(saveButtonText) { saveOpportunity() }
                        .disabled(!canSubmit)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                // Loading Indicator Section for main save/update
                if viewModel.isLoading {
                    Section { LoadingIndicator(text: isEditing ? "Updating..." : "Saving...") }
                }

            } // End Form
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CancelButton(action: dismissSheet) } // Add Cancel button
            .onAppear(perform: populateFieldsForEditing) // Populate fields if editing
            // Dismiss sheet logic based on main save/update operation
            .onChange(of: viewModel.isLoading) { oldVal, newVal in
                 if saveAttempted && oldVal == true && newVal == false {
                     if viewModel.errorMessage == nil { dismissSheet() }
                     else { print("Save/Update failed, keeping sheet open.") }
                 }
             }
            // Auto-adjust end time if start/end times become invalid
            .onChange(of: eventDate) { adjustEndTimeIfInvalid() }
            .onChange(of: endTime) { adjustEndTimeIfInvalid() }
            // Clear number field when toggling to unlimited
            .onChange(of: hasUnlimitedSpots) { clearMaxAttendeesIfUnlimited($0) }
            // Present location search sheet
            .sheet(isPresented: $showingLocationSearchSheet) { LocationSearchView(selectedLocationString: $location) }
            // Reset state on manual dismiss
            .onDisappear(perform: resetStateOnDisappear)

        } // End NavigationView
    } // End body

    // MARK: - Extracted Subview Properties

    /// Section for Name, Location, and Description inputs.
    private var detailsSection: some View {
        Section {
            VStack(alignment: .leading,) {
                TextField("Opportunity name", text: $name)
                Divider()
                LocationSearchRow(location: $location, showingSheet: $showingLocationSearchSheet)
                Divider()
                DescriptionEditor(description: $description, isFocused: $isDescriptionEditorFocused)
            }
        } header: { Text("Opportunity Details") }
    }

    /// Section for Date and Time Pickers (Modified for Single Day)
    private var dateTimeSection: some View {
        Section(header: Text("Date and Time")) {
            DatePicker("Date", selection: $eventDate, displayedComponents: [.date])
            DatePicker("Starts At", selection: $eventDate, displayedComponents: [.hourAndMinute])
            DatePicker("Ends At", selection: $endTime, displayedComponents: [.hourAndMinute])
            if !isEndTimeValid { DateTimeValidationError() }
        }
    }

    /// Section for setting the attendee limit.
    private var attendeeLimitSection: some View {
        Section("Attendee Limit") {
            Toggle("Unlimited Spots", isOn: $hasUnlimitedSpots).tint(.accentColor)
            if !hasUnlimitedSpots {
                MaxAttendeesInput(maxAttendeesString: $maxAttendeesString, isValid: isMaxAttendeesValid, isFocused: $isMaxAttendeesFocused)
            }
        }
    }

    // MARK: - Helper Views (Included within the file)
    struct ErrorDisplay: View {
        let message: String
        var body: some View { HStack { Image(systemName: "exclamationmark.circle.fill").foregroundColor(.red); Text("Error: \(message)").foregroundColor(.red).font(.footnote) } }
    }
    struct LoadingIndicator: View {
        let text: String
        var body: some View { HStack { Spacer(); ProgressView(text); Spacer() } }
    }
    struct CancelButton: ToolbarContent {
        var action: () -> Void
        var body: some ToolbarContent { ToolbarItem(placement: .navigationBarLeading) { Button("Cancel", action: action) } }
    }
    struct LocationSearchRow: View {
        @Binding var location: String
        @Binding var showingSheet: Bool
        var body: some View {
            HStack {
                VStack(alignment: .leading) {
                    Text("Location").font(.caption).foregroundStyle(.placeholder)
                    Text(location.isEmpty ? "Tap the glass to search" : location)
                        .lineLimit(2)
                        .foregroundStyle(location.isEmpty ? Color(uiColor: .placeholderText): Color.primary)
                        
                }
                Spacer()
                Button { showingSheet = true } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(.borderless).foregroundStyle(.placeholder)
            }
        }
    }
    struct DescriptionEditor: View {
        @Binding var description: String
        var isFocused: FocusState<Bool>.Binding
        var body: some View {
            TextField("Add a description", text: $description, axis:.vertical)
                .lineLimit(5, reservesSpace: true)
              }
        }
    
    struct DateTimeValidationError: View {
         var body: some View { Text("End time must be after the start time.").font(.caption).foregroundColor(.red).frame(maxWidth: .infinity, alignment: .leading) }
     }
    struct MaxAttendeesInput: View {
        @Binding var maxAttendeesString: String
        var isValid: Bool
        var isFocused: FocusState<Bool>.Binding
        var body: some View {
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("Maximum Attendees").foregroundStyle(isValid ? .primary : Color.red)
                    Spacer()
                    TextField("Number", text: $maxAttendeesString).keyboardType(.numberPad).multilineTextAlignment(.trailing).frame(width: 80).focused(isFocused)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(isValid ? Color.clear : Color.red, lineWidth: !maxAttendeesString.isEmpty && !isValid ? 1 : 0))
                }
                if !maxAttendeesString.isEmpty && !isValid { Text("Enter a whole number (1 or more).").font(.caption).foregroundColor(.red).padding(.leading, 1) }
            }
        }
    }


    // MARK: - Action Methods

    /// Dismisses the sheet and clears related state.
    private func dismissSheet() {
        viewModel.errorMessage = nil; saveAttempted = false; dismiss()
    }

    /// Ensures the selected end time is after the selected start time on the same day.
    private func adjustEndTimeIfInvalid() {
        if let combinedEndDate = viewModel.combine(date: eventDate, time: endTime) {
            if combinedEndDate <= eventDate {
                endTime = Calendar.current.date(byAdding: .hour, value: 1, to: eventDate) ?? eventDate
                print("Adjusted end time to be 1 hour after start time.")
            }
        } else {
             endTime = Calendar.current.date(byAdding: .hour, value: 1, to: eventDate) ?? eventDate
             print("Could not combine dates, reset end time to 1 hour after start.")
        }
    }

    /// Clears the max attendees text field when "Unlimited" is toggled on.
    private func clearMaxAttendeesIfUnlimited(_ isUnlimited: Bool) {
        if isUnlimited { maxAttendeesString = ""; isMaxAttendeesFocused = false }
    }

    /// Resets ViewModel error state when the sheet disappears manually.
    private func resetStateOnDisappear() {
         if !viewModel.isLoading { saveAttempted = false; viewModel.errorMessage = nil; print("Sheet dismissed manually, resetting state.") }
    }

    /// Populates the form fields if editing an existing opportunity.
    private func populateFieldsForEditing() {
        guard let opp = opportunityToEdit, isEditing else {
            endTime = Calendar.current.date(byAdding: .hour, value: 1, to: eventDate) ?? eventDate
            hasUnlimitedSpots = true; maxAttendeesString = ""
            print("Create mode: Initializing fields."); return
        }
        print("Edit mode: Populating fields for opportunity \(opp.id)")
        name = opp.name; location = opp.location; description = opp.description
        eventDate = opp.eventDate; endTime = opp.endDate // Assign start/end dates
        if let max = opp.maxAttendees, max > 0 { hasUnlimitedSpots = false; maxAttendeesString = "\(max)" }
        else { hasUnlimitedSpots = true; maxAttendeesString = "" }
    }

    /// Handles the save/update button tap. Calls the appropriate ViewModel action.
    func saveOpportunity() {
        hideKeyboard(); viewModel.errorMessage = nil; saveAttempted = true
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let maxAttendees = maxAttendeesIntValue // Get calculated Int? value

        if let oppToEdit = opportunityToEdit { // Update Mode
            print("Calling updateOpportunity for ID: \(oppToEdit.id) with maxAttendees: \(String(describing: maxAttendees))")
            viewModel.updateOpportunity(
                opportunityId: oppToEdit.id, name: trimmedName, location: trimmedLocation, description: trimmedDesc,
                eventDate: eventDate, endTime: endTime, maxAttendeesInput: maxAttendees // Pass separate end time
            )
        } else { // Create Mode
            print("Calling addOpportunity with maxAttendees: \(String(describing: maxAttendees))")
            viewModel.addOpportunity(
                name: trimmedName, location: trimmedLocation, description: trimmedDesc,
                eventDate: eventDate, endTime: endTime, maxAttendeesInput: maxAttendees // Pass separate end time
            )
        }
    }

    /// Helper to dismiss the keyboard.
    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

    // Temporary MKLocalSearch Test Function REMOVED
    // private func performMKLocalSearchTest() { ... }

} // End struct CreateOpportunityView


