import AppKit
import Observation
import PDFKit
import SwiftUI

@main
struct PDFViewerApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .defaultSize(width: 860, height: 980)
    }
}

@Observable
final class ViewerModel {
    var document: PDFDocument?
    var pageIndex = 0
    var errorMessage: String?
    var rebuilding = false
    var banner = ""
    var bannerIsProblem = false

    var pageCount: Int {
        document?.pageCount ?? 0
    }

    var canGoPrevious: Bool {
        document != nil && pageIndex > 0
    }

    var canGoNext: Bool {
        document != nil && pageIndex + 1 < pageCount
    }

    var pageLabel: String {
        guard document != nil else { return "—" }
        return "\(pageIndex + 1) of \(pageCount)"
    }

    func choosePDF() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.title = "Open PDF"
        panel.prompt = "Open"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(url)
    }

    func open(_ url: URL) {
        let accessed = url.startAccessingSecurityScopedResource()
        defer {
            if accessed {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let data = try? Data(contentsOf: url),
              let document = PDFDocument(data: data),
              document.pageCount > 0
        else {
            errorMessage = "That file could not be read as a PDF."
            return
        }

        self.document = document
        pageIndex = 0
    }

    func previous() {
        guard canGoPrevious else { return }
        pageIndex -= 1
    }

    func next() {
        guard canGoNext else { return }
        pageIndex += 1
    }

    func dismissBanner() {
        banner = ""
        bannerIsProblem = false
    }

    func rebuild() {
        guard !rebuilding else { return }
        let project = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/pdfViewer", isDirectory: true)
        let script = project.appendingPathComponent("build.sh")
        guard FileManager.default.isExecutableFile(atPath: script.path) else {
            banner = "Could not find ./build.sh."
            bannerIsProblem = true
            return
        }

        let logs = supportDirectory.appendingPathComponent("logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let log = logs.appendingPathComponent("install.log").path
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        proc.arguments = [
            "-MPOSIX", "-e", "POSIX::setsid(); exec @ARGV",
            "/bin/zsh", "-c", "./build.sh > \"$1\" 2>&1 && open \"$HOME/Desktop/PDF Viewer.app\"",
            "rebuild", log
        ]
        proc.currentDirectoryURL = project
        proc.environment = commandEnvironment()
        proc.standardInput = FileHandle.nullDevice
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = FileHandle.nullDevice
        proc.terminationHandler = { _ in
            Task { @MainActor in
                self.rebuilding = false
                self.banner = "Rebuild failed. The log is at \(log)."
                self.bannerIsProblem = true
            }
        }
        do {
            try proc.run()
            rebuilding = true
            banner = "Rebuilding. PDF Viewer reopens when it finishes."
            bannerIsProblem = false
        } catch {
            banner = "Could not start ./build.sh."
            bannerIsProblem = true
        }
    }

    private var supportDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/pdf-viewer", isDirectory: true)
    }

    private func commandEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let prefix = "\(home)/.local/bin:\(home)/.nix-profile/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        if let current = env["PATH"], !current.isEmpty {
            env["PATH"] = prefix + ":" + current
        } else {
            env["PATH"] = prefix
        }
        env["HOME"] = home
        return env
    }
}

struct ContentView: View {
    @State private var model = ViewerModel()
    @State private var confirmRebuild = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Button("Open") {
                    model.choosePDF()
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Rebuild") {
                    confirmRebuild = true
                }
                .disabled(model.rebuilding)
                .help("Run ./build.sh, then reopen PDF Viewer")
                .alert("Are you sure?", isPresented: $confirmRebuild) {
                    Button("Cancel", role: .cancel) {}
                    Button("Rebuild") {
                        model.rebuild()
                    }
                } message: {
                    Text("PDF Viewer will quit, rebuild, and reopen.")
                }

                Spacer()

                Button(action: model.previous) {
                    Image(systemName: "chevron.left")
                        .frame(width: 16, height: 16)
                }
                .disabled(!model.canGoPrevious)
                .accessibilityLabel("Previous page")

                Text(model.pageLabel)
                    .font(.body.monospacedDigit())
                    .frame(minWidth: 88)

                Button(action: model.next) {
                    Image(systemName: "chevron.right")
                        .frame(width: 16, height: 16)
                }
                .disabled(!model.canGoNext)
                .accessibilityLabel("Next page")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            if !model.banner.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(model.banner)
                        .font(.caption2)
                        .foregroundStyle(model.bannerIsProblem ? Color.orange : Color.secondary)
                        .lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button("Dismiss") {
                        model.dismissBanner()
                    }
                    .buttonStyle(.plain)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            }

            Divider()

            Group {
                if let document = model.document {
                    PDFPageView(document: document, pageIndex: model.pageIndex)
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "doc")
                            .font(.system(size: 42))
                            .foregroundStyle(.secondary)
                        Text("Open a PDF to start reading.")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 640, minHeight: 480)
        .alert("Could Not Open PDF", isPresented: errorIsPresented) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var errorIsPresented: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    model.errorMessage = nil
                }
            }
        )
    }
}

struct PDFPageView: NSViewRepresentable {
    let document: PDFDocument
    let pageIndex: Int

    func makeNSView(context: Context) -> SinglePagePDFView {
        let pdfView = SinglePagePDFView()
        pdfView.autoScales = false
        pdfView.displayMode = .singlePage
        pdfView.displaysPageBreaks = false
        pdfView.displayDirection = .vertical
        pdfView.backgroundColor = .windowBackgroundColor
        pdfView.document = document
        pdfView.show(pageAt: pageIndex)
        return pdfView
    }

    func updateNSView(_ pdfView: SinglePagePDFView, context: Context) {
        if pdfView.document !== document {
            pdfView.document = document
        }
        pdfView.show(pageAt: pageIndex)
    }
}

final class SinglePagePDFView: PDFView {
    private var requestedIndex: Int?
    private var isFitting = false
    private var fittedBounds: CGRect = .zero

    func show(pageAt index: Int) {
        requestedIndex = index
        showRequestedPage()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        showRequestedPage()
    }

    override func layout() {
        super.layout()
        guard !isFitting, document != nil, bounds.width > 1, bounds.height > 1 else { return }
        if bounds != fittedBounds {
            isFitting = true
            fittedBounds = bounds
            let fit = scaleFactorForSizeToFit
            if fit > 0 {
                scaleFactor = fit
            }
            isFitting = false
        }
        showRequestedPage()
    }

    private func showRequestedPage() {
        guard window != nil, bounds.width > 1, let document, let requestedIndex else { return }
        guard let page = document.page(at: requestedIndex), currentPage !== page else { return }
        go(to: page)
    }
}
