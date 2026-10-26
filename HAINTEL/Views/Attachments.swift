import PhotosUI
import QuickLook
import SwiftUI
import UniformTypeIdentifiers
import VisionKit

/// Largest file people can attach. Photos are shrunk to well under this; PDFs are sent as they are.
private let maxAttachmentBytes = 20 * 1024 * 1024

// MARK: - Adding files (in the edit forms)

/// The Attachments section of an opinion or vet report form: what's attached, plus ways to add more
/// (photo library, Files app, or scanning a paper report with the camera). Files upload right away;
/// the form saves the list. `uploaded` collects this visit's uploads so Cancel can remove them again.
struct AttachmentEditor: View {
    @Environment(SaleStore.self) private var store
    @Binding var attachments: [Attachment]
    @Binding var uploaded: [Attachment]
    @Binding var busy: Bool
    let folder: AttachmentFolder
    let footer: String

    @State private var pickedPhotos: [PhotosPickerItem] = []
    @State private var importing = false
    @State private var scanning = false
    @State private var problem: String?
    @State private var preview: URL?

    var body: some View {
        Section {
            ForEach(attachments) { attachment in
                Button {
                    Task { await open(attachment) }
                } label: {
                    AttachmentRow(attachment: attachment)
                }
                .swipeActions {
                    Button("Remove", role: .destructive) { remove(attachment) }
                }
            }
            if busy {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Uploading…").foregroundStyle(Theme.slate)
                }
            } else {
                PhotosPicker(selection: $pickedPhotos, maxSelectionCount: 10, matching: .images) {
                    Label("Add photos", systemImage: "photo.on.rectangle")
                }
                Button {
                    importing = true
                } label: {
                    Label("Add PDF or image file", systemImage: "doc.badge.plus")
                }
                if VNDocumentCameraViewController.isSupported {
                    Button {
                        scanning = true
                    } label: {
                        Label("Scan paper report", systemImage: "doc.viewfinder")
                    }
                }
            }
            if let problem {
                Text(problem).foregroundStyle(Theme.red)
            }
        } header: {
            Text("Attachments")
        } footer: {
            Text(attachments.isEmpty ? footer : "\(footer) Swipe left on a file to remove it.")
        }
        .onChange(of: pickedPhotos) { _, items in
            guard !items.isEmpty else { return }
            pickedPhotos = []
            Task { await addPhotos(items) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): Task { await addFiles(urls) }
            case .failure(let error): problem = error.localizedDescription
            }
        }
        .fullScreenCover(isPresented: $scanning) {
            DocumentScanner { pages in
                scanning = false
                Task { await addScan(pages) }
            } onCancel: {
                scanning = false
            }
            .ignoresSafeArea()
        }
        .quickLookPreview($preview)
    }

    private func addPhotos(_ items: [PhotosPickerItem]) async {
        await work {
            for (i, item) in items.enumerated() {
                guard let data = try await item.loadTransferable(type: Data.self),
                      let jpeg = AttachmentFiles.jpeg(from: data) else {
                    throw BackendError(message: "Couldn’t read one of those photos. Try another one.")
                }
                let name = items.count == 1 ? "Photo.jpg" : "Photo \(i + 1).jpg"
                try await upload(jpeg, name: name, contentType: "image/jpeg")
            }
        }
    }

    private func addFiles(_ urls: [URL]) async {
        await work {
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let data = try Data(contentsOf: url)
                let name = url.lastPathComponent
                if UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) == true {
                    try await upload(data, name: name, contentType: "application/pdf")
                } else if let jpeg = AttachmentFiles.jpeg(from: data) {
                    let base = url.deletingPathExtension().lastPathComponent
                    try await upload(jpeg, name: "\(base).jpg", contentType: "image/jpeg")
                } else {
                    throw BackendError(message: "\(name) isn’t a PDF or an image.")
                }
            }
        }
    }

    private func addScan(_ pages: [UIImage]) async {
        guard !pages.isEmpty else { return }
        await work {
            let pdf = AttachmentFiles.pdf(from: pages)
            let name = "Scanned report \(Date().formatted(.dateTime.month(.abbreviated).day())).pdf"
            try await upload(pdf, name: name, contentType: "application/pdf")
        }
    }

    private func upload(_ data: Data, name: String, contentType: String) async throws {
        guard data.count <= maxAttachmentBytes else {
            throw BackendError(message: "\(name) is \(ByteCountFormatter.string(fromByteCount: Int64(data.count), countStyle: .file)). Files can be up to 20 MB.")
        }
        let attachment = try await store.uploadAttachment(data, name: name, contentType: contentType, to: folder)
        attachments.append(attachment)
        uploaded.append(attachment)
    }

    private func remove(_ attachment: Attachment) {
        attachments.removeAll { $0.path == attachment.path }
    }

    private func open(_ attachment: Attachment) async {
        do {
            preview = try await store.localFile(for: attachment)
        } catch {
            problem = error.localizedDescription
        }
    }

    private func work(_ job: () async throws -> Void) async {
        busy = true
        problem = nil
        defer { busy = false }
        do {
            try await job()
        } catch {
            problem = error.localizedDescription
        }
    }
}

// MARK: - Showing files (on the opinion and vet report screens)

/// A card listing attached reports. Tapping one downloads it and opens it full screen
/// (zoom, share, print, as the person's access allows).
struct AttachmentList: View {
    @Environment(SaleStore.self) private var store
    let attachments: [Attachment]
    @State private var opening: String?
    @State private var preview: URL?
    @State private var problem: String?

    var body: some View {
        if !attachments.isEmpty {
            Card {
                Eyebrow(text: attachments.count == 1 ? "Attached report" : "Attached reports (\(attachments.count))")
                ForEach(attachments) { attachment in
                    Button {
                        Task { await open(attachment) }
                    } label: {
                        HStack {
                            AttachmentRow(attachment: attachment)
                            Spacer(minLength: 8)
                            if opening == attachment.path {
                                ProgressView()
                            } else {
                                Image(systemName: "chevron.right").foregroundStyle(Theme.slate)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .disabled(opening != nil)
                }
                if let problem {
                    Text(problem).font(Theme.sans(14)).foregroundStyle(Theme.red)
                }
            }
            .quickLookPreview($preview)
        }
    }

    private func open(_ attachment: Attachment) async {
        opening = attachment.path
        problem = nil
        defer { opening = nil }
        do {
            preview = try await store.localFile(for: attachment)
        } catch {
            problem = error.localizedDescription
        }
    }
}

/// Icon, name and size of one file.
struct AttachmentRow: View {
    let attachment: Attachment

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: attachment.isPDF ? "doc.richtext" : "photo")
                .font(.title3)
                .foregroundStyle(Theme.blue)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(attachment.name).foregroundStyle(Theme.ink).lineLimit(2)
                Text("\(attachment.isPDF ? "PDF" : "Image") · \(attachment.sizeText)")
                    .font(.footnote).foregroundStyle(Theme.slate)
            }
        }
    }
}

// MARK: - File helpers

enum AttachmentFiles {
    /// Any photo (HEIC, PNG, JPEG…) as a JPEG no wider or taller than 2400 px: sharp enough to read
    /// a report or radiograph, small enough to upload quickly.
    static func jpeg(from data: Data) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        return downscaled(image, maxSide: 2400).jpegData(compressionQuality: 0.82)
    }

    /// Scanned pages as one PDF, each page fitted onto US Letter.
    static func pdf(from pages: [UIImage]) -> Data {
        let page = CGRect(x: 0, y: 0, width: 612, height: 792)
        let area = page.insetBy(dx: 18, dy: 18)
        return UIGraphicsPDFRenderer(bounds: page).pdfData { context in
            for scan in pages {
                let small = downscaled(scan, maxSide: 2000)
                let image = small.jpegData(compressionQuality: 0.7).flatMap(UIImage.init(data:)) ?? small
                context.beginPage()
                let scale = min(area.width / image.size.width, area.height / image.size.height)
                let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                image.draw(in: CGRect(x: area.midX - size.width / 2, y: area.midY - size.height / 2,
                                      width: size.width, height: size.height))
            }
        }
    }

    static func downscaled(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let pixels = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        let scale = min(1, maxSide / max(pixels.width, pixels.height))
        let size = CGSize(width: (pixels.width * scale).rounded(), height: (pixels.height * scale).rounded())
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}

/// The camera's document scanner: finds the page edges, flattens and cleans up each page.
struct DocumentScanner: UIViewControllerRepresentable {
    let onFinish: ([UIImage]) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: VNDocumentCameraViewController, context: Context) {}

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScanner
        init(_ parent: DocumentScanner) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController,
                                          didFinishWith scan: VNDocumentCameraScan) {
            parent.onFinish((0..<scan.pageCount).map { scan.imageOfPage(at: $0) })
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            parent.onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            parent.onCancel()
        }
    }
}
