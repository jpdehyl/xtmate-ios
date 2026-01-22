//
//  PreliminaryReportPreviewView.swift
//  XtMate
//
//  Created by XtMate on 2026-01-17.
//
//  PDF-style preview of the Preliminary Report matching the Paul Davis format.
//  Shows how the final report will look when exported/shared.
//

import SwiftUI

@available(iOS 16.0, *)
struct PreliminaryReportPreviewView: View {
    let report: PreliminaryReport

    // Estimate data (would be passed from parent)
    var customerName: String = ""
    var propertyAddress: String = ""
    var policyNumber: String = ""
    var claimNumber: String = ""

    @State private var showingShareSheet = false
    @State private var pdfData: Data?
    @State private var isGeneratingPDF = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    // Page content styled like PDF
                    reportContent
                        .padding(20)
                        .background(Color.white)
                        .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
                        .padding()
                }
            }
            .background(Color(.systemGray5))
            .navigationTitle("Report Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        generateAndSharePDF()
                    } label: {
                        if isGeneratingPDF {
                            ProgressView()
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    .disabled(isGeneratingPDF)
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let pdfData = pdfData {
                    ShareSheet(items: [pdfData])
                }
            }
        }
    }

    // MARK: - Report Content

    private var reportContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            // Header
            headerSection

            Divider()
                .background(Color.gray)

            // Customer & Policy Info
            customerInfoSection

            Divider()
                .background(Color.gray)

            // Title
            Text("PRELIMINARY REPORT")
                .font(.system(size: 18, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)

            // Claim Log
            claimLogSection

            // Emergency Services
            emergencyServicesSection

            // Cause of Loss
            causeOfLossSection

            // Photos for each affected area
            if !report.photos.isEmpty {
                photosSection
            }

            // Resulting Structural Damage
            structuralDamageSection

            // More photos organized by room
            roomPhotosSection

            // Repair Costs
            repairCostsSection
        }
        .foregroundColor(.black)
    }

    // MARK: - Header Section

    private var headerSection: some View {
        HStack(alignment: .top) {
            // Company logo/name area (placeholder)
            VStack(alignment: .leading, spacing: 4) {
                Text("XTMATE")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.accentColor)
                Text("Property Restoration")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }

            Spacer()

            // Company info
            VStack(alignment: .trailing, spacing: 2) {
                Text("123 Business Ave")
                Text("City, State 12345")
                Text("555-123-4567")
            }
            .font(.system(size: 10))
            .foregroundColor(.gray)
        }
    }

    // MARK: - Customer Info Section

    private var customerInfoSection: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(customerName.isEmpty ? "Customer Name" : customerName)
                        .font(.system(size: 12, weight: .semibold))
                    Text("Customer Name")
                        .font(.system(size: 8))
                        .foregroundColor(.gray)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 4) {
                    Text(propertyAddress.isEmpty ? "Property Address" : propertyAddress)
                        .font(.system(size: 12, weight: .semibold))
                    Text("Address")
                        .font(.system(size: 8))
                        .foregroundColor(.gray)
                }
            }

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(policyNumber.isEmpty ? "Policy #" : policyNumber)
                        .font(.system(size: 12, weight: .semibold))
                    Text("Policy #")
                        .font(.system(size: 8))
                        .foregroundColor(.gray)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 4) {
                    Text(claimNumber.isEmpty ? "Claim #" : claimNumber)
                        .font(.system(size: 12, weight: .semibold))
                    Text("Claim #")
                        .font(.system(size: 8))
                        .foregroundColor(.gray)
                }
            }
        }
    }

    // MARK: - Claim Log Section

    private var claimLogSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Claim Log")
                .font(.system(size: 14, weight: .bold))

            if let date = report.claimReceivedDate {
                Text("Claim received in office, \(formatDate(date)).")
                    .font(.system(size: 11))
            }

            if let date = report.insuredContactedDate {
                Text("The insured was contacted, \(formatDate(date)).")
                    .font(.system(size: 11))
            }

            if let date = report.siteInspectedDate {
                Text("Site inspected, \(formatDate(date)).")
                    .font(.system(size: 11))
            }
        }
    }

    // MARK: - Emergency Services Section

    private var emergencyServicesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Emergency Services")
                .font(.system(size: 14, weight: .bold))

            if report.emergencyServicesCompleted {
                if report.emergencyServicesByOther {
                    Text("Emergency work completed by another contractor")
                        .font(.system(size: 11))
                } else {
                    Text(report.emergencyServicesDescription.isEmpty ?
                         "Emergency services were performed." :
                         report.emergencyServicesDescription)
                        .font(.system(size: 11))
                }
            } else {
                Text("No emergency services required.")
                    .font(.system(size: 11))
            }
        }
    }

    // MARK: - Cause of Loss Section

    private var causeOfLossSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cause of Loss")
                .font(.system(size: 14, weight: .bold))

            Text(report.causeOfLoss.isEmpty ?
                 "\(report.causeOfLossType.rawValue) damage to the property." :
                 report.causeOfLoss)
                .font(.system(size: 11))
        }
    }

    // MARK: - Initial Photos Section

    private var photosSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Show first 2 photos as overview
            let overviewPhotos = Array(report.photos.prefix(2))

            if !overviewPhotos.isEmpty {
                HStack(alignment: .top, spacing: 16) {
                    ForEach(overviewPhotos) { photo in
                        photoWithCaption(photo)
                    }
                }
            }
        }
    }

    // MARK: - Structural Damage Section

    private var structuralDamageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Resulting Structural Damage")
                .font(.system(size: 14, weight: .bold))

            ForEach(report.roomDamage) { damage in
                if !damage.affectedMaterials.isEmpty {
                    Text(damage.fullDescription)
                        .font(.system(size: 11))
                }
            }
        }
    }

    // MARK: - Room Photos Section

    private var roomPhotosSection: some View {
        let groupedPhotos = Dictionary(grouping: report.photos) { $0.roomName }
        let sortedRooms = groupedPhotos.keys.sorted()

        return ForEach(sortedRooms, id: \.self) { roomName in
            if let photos = groupedPhotos[roomName], !photos.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    // Show photos in rows of 2-3
                    let photoRows = photos.chunked(into: 3)

                    ForEach(Array(photoRows.enumerated()), id: \.offset) { _, row in
                        HStack(alignment: .top, spacing: 12) {
                            ForEach(row) { photo in
                                photoWithCaption(photo, showRoom: false)
                            }

                            // Fill remaining space
                            if row.count < 3 {
                                ForEach(0..<(3 - row.count), id: \.self) { _ in
                                    Spacer()
                                        .frame(maxWidth: .infinity)
                                }
                            }
                        }
                    }
                }
                .padding(.vertical, 8)
            }
        }
    }

    // MARK: - Repair Costs Section

    private var repairCostsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Repair Costs")
                .font(.system(size: 14, weight: .bold))

            if let repairMin = report.repairCostMin,
               let repairMax = report.repairCostMax {
                Text("Repairs: \(formatCurrency(repairMin)) - \(formatCurrency(repairMax))")
                    .font(.system(size: 11))
            }

            if let contentsMin = report.contentsCostMin,
               let contentsMax = report.contentsCostMax {
                Text("Contents: \(formatCurrency(contentsMin)) - \(formatCurrency(contentsMax))")
                    .font(.system(size: 11))
            }

            if let emergency = report.emergencyCost, emergency > 0 {
                Text("Emergency: \(formatCurrency(emergency))")
                    .font(.system(size: 11))
            }
        }
    }

    // MARK: - Helper Views

    private func photoWithCaption(_ photo: PreliminaryReportPhoto, showRoom: Bool = true) -> some View {
        VStack(spacing: 4) {
            if let data = photo.imageData,
               let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
                    .clipped()
                    .cornerRadius(4)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(maxWidth: .infinity)
                    .frame(height: 150)
                    .cornerRadius(4)
            }

            Text(showRoom ? photo.roomName : (photo.caption.isEmpty ? photo.roomName : photo.caption))
                .font(.system(size: 10))
                .foregroundColor(.gray)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Formatting Helpers

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM d, yyyy h:mm a"
        return formatter
    }()

    private func formatDate(_ date: Date) -> String {
        Self.dateFormatter.string(from: date)
    }

    private func formatCurrency(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSNumber(value: value)) ?? "$0"
    }

    // MARK: - PDF Generation

    private func generateAndSharePDF() {
        isGeneratingPDF = true

        // Generate PDF on background thread
        DispatchQueue.global(qos: .userInitiated).async {
            let pdfData = generatePDFData()

            DispatchQueue.main.async {
                self.pdfData = pdfData
                self.isGeneratingPDF = false
                self.showingShareSheet = true
            }
        }
    }

    private func generatePDFData() -> Data {
        // Create PDF renderer
        let pageWidth: CGFloat = 612  // 8.5 inches at 72 dpi
        let pageHeight: CGFloat = 792 // 11 inches at 72 dpi
        let pageRect = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)

        let data = renderer.pdfData { context in
            context.beginPage()

            // Draw content
            let margin: CGFloat = 36
            var yOffset: CGFloat = margin

            // Title
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 18),
                .foregroundColor: UIColor.black
            ]

            let title = "PRELIMINARY REPORT"
            title.draw(at: CGPoint(x: margin, y: yOffset), withAttributes: titleAttributes)
            yOffset += 30

            // Claim log
            let sectionAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 14),
                .foregroundColor: UIColor.black
            ]

            let textAttributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11),
                .foregroundColor: UIColor.black
            ]

            "Claim Log".draw(at: CGPoint(x: margin, y: yOffset), withAttributes: sectionAttributes)
            yOffset += 20

            if let date = report.claimReceivedDate {
                let text = "Claim received in office, \(formatDate(date))."
                text.draw(at: CGPoint(x: margin, y: yOffset), withAttributes: textAttributes)
                yOffset += 16
            }

            if let date = report.insuredContactedDate {
                let text = "The insured was contacted, \(formatDate(date))."
                text.draw(at: CGPoint(x: margin, y: yOffset), withAttributes: textAttributes)
                yOffset += 16
            }

            if let date = report.siteInspectedDate {
                let text = "Site inspected, \(formatDate(date))."
                text.draw(at: CGPoint(x: margin, y: yOffset), withAttributes: textAttributes)
                yOffset += 24
            }

            // Emergency Services
            "Emergency Services".draw(at: CGPoint(x: margin, y: yOffset), withAttributes: sectionAttributes)
            yOffset += 20

            let emergencyText = report.emergencyServicesByOther ?
                "Emergency work completed by another contractor" :
                (report.emergencyServicesDescription.isEmpty ? "Emergency services were performed." : report.emergencyServicesDescription)
            emergencyText.draw(at: CGPoint(x: margin, y: yOffset), withAttributes: textAttributes)
            yOffset += 24

            // Cause of Loss
            "Cause of Loss".draw(at: CGPoint(x: margin, y: yOffset), withAttributes: sectionAttributes)
            yOffset += 20

            let causeText = report.causeOfLoss.isEmpty ?
                "\(report.causeOfLossType.rawValue) damage to the property." : report.causeOfLoss
            causeText.draw(at: CGPoint(x: margin, y: yOffset), withAttributes: textAttributes)
            yOffset += 24

            // Structural Damage
            "Resulting Structural Damage".draw(at: CGPoint(x: margin, y: yOffset), withAttributes: sectionAttributes)
            yOffset += 20

            for damage in report.roomDamage {
                if !damage.affectedMaterials.isEmpty {
                    damage.fullDescription.draw(at: CGPoint(x: margin, y: yOffset), withAttributes: textAttributes)
                    yOffset += 16
                }
            }
            yOffset += 8

            // Photos (simplified - just show count for now)
            if !report.photos.isEmpty {
                let photoText = "\(report.photos.count) photos attached"
                photoText.draw(at: CGPoint(x: margin, y: yOffset), withAttributes: textAttributes)
                yOffset += 24
            }

            // Repair Costs
            "Repair Costs".draw(at: CGPoint(x: margin, y: yOffset), withAttributes: sectionAttributes)
            yOffset += 20

            if let repairMin = report.repairCostMin,
               let repairMax = report.repairCostMax {
                "Repairs: \(formatCurrency(repairMin)) - \(formatCurrency(repairMax))".draw(
                    at: CGPoint(x: margin, y: yOffset), withAttributes: textAttributes)
                yOffset += 16
            }

            if let contentsMin = report.contentsCostMin,
               let contentsMax = report.contentsCostMax {
                "Contents: \(formatCurrency(contentsMin)) - \(formatCurrency(contentsMax))".draw(
                    at: CGPoint(x: margin, y: yOffset), withAttributes: textAttributes)
            }
        }

        return data
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

// MARK: - Array Extension for Chunking

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}
