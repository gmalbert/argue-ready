import CoreText
import SwiftUI
import UIKit
import UniformTypeIdentifiers

enum TranscriptExportFormat {
    case text
    case pdf

    var contentType: UTType { self == .pdf ? .pdf : .plainText }
    var fileExtension: String { self == .pdf ? "pdf" : "txt" }

    func shareItem(transcript: String, title: String) throws -> TranscriptShareItem {
        let data = self == .pdf
            ? try TranscriptPDFExporter.data(transcript: transcript, title: title)
            : Data(transcript.utf8)
        return TranscriptShareItem(data: data, format: self,
            filename: transcriptExportFilename(title: title, fileExtension: fileExtension))
    }
}

/// Hand the bytes directly to the system share sheet. No app-owned export file
/// or permanent local copy is created, including when sharing is canceled.
struct TranscriptShareItem: Identifiable {
    let id = UUID()
    let data: Data
    let format: TranscriptExportFormat
    let filename: String

    var itemProvider: NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = filename
        provider.registerDataRepresentation(forTypeIdentifier: format.contentType.identifier,
                                             visibility: .all) { completion in
            completion(data, nil)
            return nil
        }
        return provider
    }
}

struct TranscriptShareSheet: UIViewControllerRepresentable {
    let item: TranscriptShareItem

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let configuration = UIActivityItemsConfiguration(itemProviders: [item.itemProvider])
        configuration.metadataProvider = { key in
            key == .title ? item.filename : nil
        }
        return UIActivityViewController(activityItemsConfiguration: configuration)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}

enum TranscriptPDFExporter {
    private enum ExportError: LocalizedError {
        case textLayoutFailed
        var errorDescription: String? { "The transcript could not be laid out for PDF export. Please try again." }
    }

    /// Generate selectable text with Core Text pagination, never a screenshot
    /// of the scroll view. The resulting bytes stay in memory for sharing.
    static func data(transcript: String, title: String) throws -> Data {
        let pageBounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let bodyBounds = CGRect(x: 48, y: 76, width: 516, height: 644)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 8
        let heading = NSMutableParagraphStyle()
        heading.paragraphSpacing = 16
        let text = NSMutableAttributedString(string: title + "\n", attributes: [
            .font: UIFont.systemFont(ofSize: 20, weight: .semibold),
            .foregroundColor: UIColor.black,
            .paragraphStyle: heading
        ])
        text.append(NSAttributedString(string: transcript, attributes: [
            .font: UIFont.systemFont(ofSize: 12),
            .foregroundColor: UIColor.black,
            .paragraphStyle: paragraph
        ]))
        let framesetter = CTFramesetterCreateWithAttributedString(text)
        // Core Text lays out in a bottom-left coordinate system.
        let path = CGPath(rect: CGRect(x: bodyBounds.minX,
                                      y: pageBounds.height - bodyBounds.maxY,
                                      width: bodyBounds.width, height: bodyBounds.height), transform: nil)
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextTitle as String: title,
                               kCGPDFContextCreator as String: "Transcript export"]
        let renderer = UIGraphicsPDFRenderer(bounds: pageBounds, format: format)
        var didFailLayout = false
        let data = renderer.pdfData { rendererContext in
            var offset = 0
            var pageNumber = 0
            while offset < text.length {
                let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0), path, nil)
                let visible = CTFrameGetVisibleStringRange(frame)
                guard visible.length > 0 else {
                    didFailLayout = true
                    break
                }
                rendererContext.beginPage()
                pageNumber += 1
                let furniture: [NSAttributedString.Key: Any] = [
                    .font: UIFont.systemFont(ofSize: 10, weight: .medium),
                    .foregroundColor: UIColor.darkGray
                ]
                ("Transcript" as NSString).draw(in: CGRect(x: 48, y: 40, width: 516, height: 16),
                                                 withAttributes: furniture)
                ("Page \(pageNumber)" as NSString).draw(in: CGRect(x: 48, y: 744, width: 516, height: 16),
                                                        withAttributes: furniture)
                let context = rendererContext.cgContext
                context.saveGState()
                context.textMatrix = .identity
                context.translateBy(x: 0, y: pageBounds.height)
                context.scaleBy(x: 1, y: -1)
                CTFrameDraw(frame, context)
                context.restoreGState()
                offset = visible.location + visible.length
            }
        }
        guard !didFailLayout else { throw ExportError.textLayoutFailed }
        return data
    }
}
