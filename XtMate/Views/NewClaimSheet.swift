import SwiftUI

// MARK: - New Claim Sheet

/// Sheet for creating a new claim with email parsing support
struct NewClaimSheet: View {
    @Environment(\.dismiss) private var dismiss

    // Form state
    @State private var mode: InputMode = .paste
    @State private var emailText: String = ""
    @State private var parsedDispatch: ParsedDispatch?
    @State private var isParsing: Bool = false

    // Claim fields
    @State private var jobType: JobType = .insurance
    @State private var claimNumber: String = ""
    @State private var xaId: String = ""
    @State private var dateOfLoss: Date = Date()
    @State private var lossType: LossType = .water

    // Insured fields
    @State private var insuredName: String = ""
    @State private var insuredEmail: String = ""
    @State private var insuredPhone: String = ""

    // Property fields
    @State private var propertyAddress: String = ""
    @State private var propertyCity: String = ""
    @State private var propertyState: String = ""
    @State private var propertyZip: String = ""

    // Adjuster fields
    @State private var adjusterName: String = ""
    @State private var adjusterPhone: String = ""
    @State private var adjusterEmail: String = ""
    @State private var insuranceCompany: String = ""

    // Assignment selection
    @State private var createEmergency: Bool = true
    @State private var createRepairs: Bool = false
    @State private var createContents: Bool = false

    var onSave: ((ClaimData) -> Void)?

    enum InputMode {
        case paste
        case manual
    }

    var body: some View {
        NavigationStack {
            Form {
                // Input mode section
                if mode == .paste && parsedDispatch == nil {
                    emailPasteSection
                } else {
                    // Job type picker
                    Section {
                        Picker("Job Type", selection: $jobType) {
                            ForEach(JobType.allCases, id: \.self) { type in
                                Label(type.displayName, systemImage: type.icon)
                                    .tag(type)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    // Claim info
                    claimInfoSection

                    // Insured info
                    insuredSection

                    // Property info
                    propertySection

                    // Adjuster info
                    adjusterSection

                    // Assignments to create
                    assignmentsSection
                }
            }
            .navigationTitle("New Claim")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        saveClaim()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    // MARK: - Email Paste Section

    private var emailPasteSection: some View {
        Section {
            VStack(alignment: .leading, spacing: PaulDavisTheme.Spacing.md) {
                Text("Paste your dispatch email from XactAnalysis")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                TextEditor(text: $emailText)
                    .frame(minHeight: 200)
                    .font(.system(.caption, design: .monospaced))
                    .overlay(
                        RoundedRectangle(cornerRadius: PaulDavisTheme.Radius.sm)
                            .strokeBorder(Color.secondary.opacity(0.3))
                    )

                HStack {
                    Button(action: parseEmail) {
                        HStack {
                            if isParsing {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            Text("Parse Email")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(emailText.isEmpty || isParsing)

                    Button("Manual Entry") {
                        withAnimation {
                            mode = .manual
                        }
                    }
                    .buttonStyle(.bordered)
                }
            }
        } header: {
            Label("Dispatch Email", systemImage: "envelope.fill")
        }
    }

    // MARK: - Claim Info Section

    private var claimInfoSection: some View {
        Section {
            LabeledContent("Claim #") {
                TextField("Claim Number", text: $claimNumber)
                    .multilineTextAlignment(.trailing)
            }

            if jobType == .insurance {
                LabeledContent("XA ID") {
                    TextField("XactAnalysis ID", text: $xaId)
                        .multilineTextAlignment(.trailing)
                }
            }

            DatePicker("Date of Loss", selection: $dateOfLoss, displayedComponents: .date)

            Picker("Loss Type", selection: $lossType) {
                ForEach(LossType.allCases, id: \.self) { type in
                    Label(type.displayName, systemImage: type.icon)
                        .tag(type)
                }
            }
        } header: {
            Label("Claim Information", systemImage: "doc.text.fill")
        }
    }

    // MARK: - Insured Section

    private var insuredSection: some View {
        Section {
            LabeledContent("Name") {
                TextField("Full Name", text: $insuredName)
                    .multilineTextAlignment(.trailing)
            }

            LabeledContent("Phone") {
                TextField("Phone Number", text: $insuredPhone)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.phonePad)
            }

            LabeledContent("Email") {
                TextField("Email Address", text: $insuredEmail)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
            }
        } header: {
            Label("Insured", systemImage: "person.fill")
        }
    }

    // MARK: - Property Section

    private var propertySection: some View {
        Section {
            LabeledContent("Address") {
                TextField("Street Address", text: $propertyAddress)
                    .multilineTextAlignment(.trailing)
            }

            LabeledContent("City") {
                TextField("City", text: $propertyCity)
                    .multilineTextAlignment(.trailing)
            }

            HStack {
                LabeledContent("State") {
                    TextField("State", text: $propertyState)
                        .multilineTextAlignment(.trailing)
                }

                Divider()

                LabeledContent("Zip") {
                    TextField("Zip Code", text: $propertyZip)
                        .multilineTextAlignment(.trailing)
                }
            }
        } header: {
            Label("Property", systemImage: "house.fill")
        }
    }

    // MARK: - Adjuster Section

    private var adjusterSection: some View {
        Section {
            LabeledContent("Name") {
                TextField("Adjuster Name", text: $adjusterName)
                    .multilineTextAlignment(.trailing)
            }

            LabeledContent("Phone") {
                TextField("Phone Number", text: $adjusterPhone)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.phonePad)
            }

            LabeledContent("Email") {
                TextField("Email Address", text: $adjusterEmail)
                    .multilineTextAlignment(.trailing)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
            }

            if jobType == .insurance {
                LabeledContent("Insurance Co.") {
                    TextField("Company Name", text: $insuranceCompany)
                        .multilineTextAlignment(.trailing)
                }
            }
        } header: {
            Label("Adjuster", systemImage: "person.badge.shield.checkmark.fill")
        } footer: {
            Text("You can fill this in later after contacting the adjuster")
                .font(.caption)
        }
    }

    // MARK: - Assignments Section

    private var assignmentsSection: some View {
        Section {
            Toggle(isOn: $createEmergency) {
                HStack {
                    Image(systemName: AssignmentType.emergency.icon)
                        .foregroundStyle(AssignmentType.emergency.color)
                    Text(jobType == .insurance ? "Emergency (E)" : "Emergency (A)")
                }
            }

            Toggle(isOn: $createRepairs) {
                HStack {
                    Image(systemName: AssignmentType.repairs.icon)
                        .foregroundStyle(AssignmentType.repairs.color)
                    Text(jobType == .insurance ? "Repairs (R)" : "Repairs (P)")
                }
            }

            Toggle(isOn: $createContents) {
                HStack {
                    Image(systemName: AssignmentType.contents.icon)
                        .foregroundStyle(AssignmentType.contents.color)
                    Text("Contents (C)")
                }
            }
        } header: {
            Label("Assignments to Create", systemImage: "list.clipboard.fill")
        } footer: {
            Text("Emergency must complete before Repairs can begin")
                .font(.caption)
        }
    }

    // MARK: - Actions

    private var canSave: Bool {
        !insuredName.isEmpty || !propertyAddress.isEmpty
    }

    private func parseEmail() {
        isParsing = true

        // Parse on background thread
        DispatchQueue.global(qos: .userInitiated).async {
            let parser = DispatchEmailParser()
            let result = parser.parse(emailText)

            DispatchQueue.main.async {
                isParsing = false
                parsedDispatch = result

                // Populate fields from parsed data
                if let name = result.insuredName { insuredName = name }
                if let email = result.insuredEmail { insuredEmail = email }
                if let address = result.propertyAddress { propertyAddress = address }
                if let city = result.propertyCity { propertyCity = city }
                if let state = result.propertyState { propertyState = state }
                if let zip = result.propertyZip { propertyZip = zip }
                if let claim = result.claimNumber { claimNumber = claim }
                if let xa = result.xaId { xaId = xa }
                if let dol = result.dateOfLoss { dateOfLoss = dol }
                if let loss = result.typeOfLoss { lossType = loss }
                if let company = result.insuranceCompany { insuranceCompany = company }

                withAnimation {
                    mode = .manual
                }
            }
        }
    }

    private func saveClaim() {
        // Build assignment types to create
        var assignmentTypes: [AssignmentType] = []
        if createEmergency {
            assignmentTypes.append(jobType == .insurance ? .emergency : .emergencyPrivate)
        }
        if createRepairs {
            assignmentTypes.append(jobType == .insurance ? .repairs : .repairsPrivate)
        }
        if createContents {
            assignmentTypes.append(.contents)
        }

        let claimData = ClaimData(
            jobType: jobType,
            claimNumber: claimNumber.isEmpty ? nil : claimNumber,
            xaId: xaId.isEmpty ? nil : xaId,
            dateOfLoss: dateOfLoss,
            lossType: lossType,
            insuredName: insuredName.isEmpty ? nil : insuredName,
            insuredEmail: insuredEmail.isEmpty ? nil : insuredEmail,
            insuredPhone: insuredPhone.isEmpty ? nil : insuredPhone,
            propertyAddress: propertyAddress.isEmpty ? nil : propertyAddress,
            propertyCity: propertyCity.isEmpty ? nil : propertyCity,
            propertyState: propertyState.isEmpty ? nil : propertyState,
            propertyZip: propertyZip.isEmpty ? nil : propertyZip,
            adjusterName: adjusterName.isEmpty ? nil : adjusterName,
            adjusterPhone: adjusterPhone.isEmpty ? nil : adjusterPhone,
            adjusterEmail: adjusterEmail.isEmpty ? nil : adjusterEmail,
            insuranceCompany: insuranceCompany.isEmpty ? nil : insuranceCompany,
            assignmentTypes: assignmentTypes,
            rawDispatchEmail: parsedDispatch?.rawEmail
        )

        onSave?(claimData)
        dismiss()
    }
}

// MARK: - Claim Data

/// Data structure for creating a new claim
struct ClaimData {
    var jobType: JobType
    var claimNumber: String?
    var xaId: String?
    var dateOfLoss: Date
    var lossType: LossType

    var insuredName: String?
    var insuredEmail: String?
    var insuredPhone: String?

    var propertyAddress: String?
    var propertyCity: String?
    var propertyState: String?
    var propertyZip: String?

    var adjusterName: String?
    var adjusterPhone: String?
    var adjusterEmail: String?
    var insuranceCompany: String?

    var assignmentTypes: [AssignmentType]
    var rawDispatchEmail: String?

    /// Generate a display name for the claim
    var displayName: String {
        if let address = propertyAddress {
            return address
        } else if let name = insuredName {
            return name
        } else if let claim = claimNumber {
            return "Claim #\(claim)"
        } else {
            return "New Claim"
        }
    }
}

// MARK: - Preview

#Preview("New Claim Sheet") {
    NewClaimSheet()
}
