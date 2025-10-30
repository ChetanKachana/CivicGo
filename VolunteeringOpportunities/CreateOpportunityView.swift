import SwiftUI
import FirebaseFirestore

// MARK: - Create/Edit Opportunity View (Single Day Event)
struct CreateOpportunityView: View {
    // MARK: - Environment Objects and State
    @EnvironmentObject var viewModel: OpportunityViewModel
    @EnvironmentObject var authViewModel: AuthenticationViewModel
    @Environment(\.dismiss) var dismiss

    let opportunityToEdit: Opportunity?

    @State private var name: String = ""
    @State private var location: String = ""
    @State private var description: String = ""
    @State private var eventDate: Date = Date()
    @State private var endTime: Date = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()

    @State private var maxAttendeesString: String = ""
    @State private var hasUnlimitedSpots: Bool = true

    @State private var showingLocationSearchSheet = false
    @State private var saveAttempted: Bool = false
    @FocusState private var isDescriptionEditorFocused: Bool
    @FocusState private var isMaxAttendeesFocused: Bool

    // MARK: - Computed Properties
    private var isEditing: Bool { opportunityToEdit != nil }
    private var navigationTitle: String { isEditing ? "Edit Opportunity" : "New Opportunity" }
    private var saveButtonText: String { isEditing ? "Update Opportunity" : "Create Opportunity" }

    private var isEndTimeValid: Bool {
        guard let combinedEndDate = viewModel.combine(date: eventDate, time: endTime) else { return false }
        return combinedEndDate > eventDate
    }
    private var isMaxAttendeesValid: Bool {
        if hasUnlimitedSpots { return true }
        guard let maxInt = Int(maxAttendeesString.trimmingCharacters(in: .whitespaces)), maxInt >= 1 else { return false }
        return true
    }
     private var maxAttendeesIntValue: Int? {
         if hasUnlimitedSpots { return nil }
         guard let maxInt = Int(maxAttendeesString.trimmingCharacters(in: .whitespaces)), maxInt >= 1 else { return nil }
         return maxInt
     }
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
                detailsSection
                dateTimeSection
                attendeeLimitSection

                if let errorMessage = viewModel.errorMessage, !viewModel.isLoading {
                    Section { ErrorDisplay(message: errorMessage) }
                }

                Section {
                    Button(saveButtonText) { saveOpportunity() }
                        .disabled(!canSubmit)
                        .frame(maxWidth: .infinity, alignment: .center)
                }

                if viewModel.isLoading {
                    Section { LoadingIndicator(text: isEditing ? "Updating..." : "Saving...") }
                }

            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { CancelButton(action: dismissSheet) }
            .onAppear(perform: populateFieldsForEditing)
            .onChange(of: viewModel.isLoading) { oldVal, newVal in
                 if saveAttempted && oldVal == true && newVal == false {
                     if viewModel.errorMessage == nil { dismissSheet() }
                     else { print("Save/Update failed, keeping sheet open.") }
                 }
             }
            .onChange(of: eventDate) { adjustEndTimeIfInvalid() }
            .onChange(of: endTime) { adjustEndTimeIfInvalid() }
            .onChange(of: hasUnlimitedSpots) { clearMaxAttendeesIfUnlimited($0) }
            .sheet(isPresented: $showingLocationSearchSheet) { LocationSearchView(selectedLocationString: $location) }
            .onDisappear(perform: resetStateOnDisappear)

        }
    }

    // MARK: - Extracted Subview Properties

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

    private var dateTimeSection: some View {
        Section(header: Text("Date and Time")) {
            DatePicker("Date", selection: $eventDate, displayedComponents: [.date])
            DatePicker("Starts At", selection: $eventDate, displayedComponents: [.hourAndMinute])
            DatePicker("Ends At", selection: $endTime, displayedComponents: [.hourAndMinute])
            if !isEndTimeValid { DateTimeValidationError() }
        }
    }

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

    private func dismissSheet() {
        viewModel.errorMessage = nil; saveAttempted = false; dismiss()
    }

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

    private func clearMaxAttendeesIfUnlimited(_ isUnlimited: Bool) {
        if isUnlimited { maxAttendeesString = ""; isMaxAttendeesFocused = false }
    }

    private func resetStateOnDisappear() {
         if !viewModel.isLoading { saveAttempted = false; viewModel.errorMessage = nil; print("Sheet dismissed manually, resetting state.") }
    }

    private func populateFieldsForEditing() {
        guard let opp = opportunityToEdit, isEditing else {
            endTime = Calendar.current.date(byAdding: .hour, value: 1, to: eventDate) ?? eventDate
            hasUnlimitedSpots = true; maxAttendeesString = ""
            print("Create mode: Initializing fields."); return
        }
        print("Edit mode: Populating fields for opportunity \(opp.id)")
        name = opp.name; location = opp.location; description = opp.description
        eventDate = opp.eventDate; endTime = opp.endDate
        if let max = opp.maxAttendees, max > 0 { hasUnlimitedSpots = false; maxAttendeesString = "\(max)" }
        else { hasUnlimitedSpots = true; maxAttendeesString = "" }
    }

    func saveOpportunity() {
        hideKeyboard(); viewModel.errorMessage = nil; saveAttempted = true
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLocation = location.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDesc = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let maxAttendees = maxAttendeesIntValue

        if let oppToEdit = opportunityToEdit {
            print("Calling updateOpportunity for ID: \(oppToEdit.id) with maxAttendees: \(String(describing: maxAttendees))")
            viewModel.updateOpportunity(
                opportunityId: oppToEdit.id, name: trimmedName, location: trimmedLocation, description: trimmedDesc,
                eventDate: eventDate, endTime: endTime, maxAttendeesInput: maxAttendees
            )
        } else {
            print("Calling addOpportunity with maxAttendees: \(String(describing: maxAttendees))")
            viewModel.addOpportunity(
                name: trimmedName, location: trimmedLocation, description: trimmedDesc,
                eventDate: eventDate, endTime: endTime, maxAttendeesInput: maxAttendees
            )
        }
    }

    private func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }

}
