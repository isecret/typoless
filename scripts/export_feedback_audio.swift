import Foundation

@main
struct ExportFeedbackAudio {
    static func main() {
        let outputPath = CommandLine.arguments.dropFirst().first ?? "app/preview-audio"
        let outputURL = URL(fileURLWithPath: outputPath, isDirectory: true)

        do {
            let urls = try FeedbackSoundDesigner.exportPreviewFiles(to: outputURL)
            for url in urls {
                print(url.path)
            }
        } catch {
            fputs("Failed to export feedback audio: \(error)\n", stderr)
            exit(1)
        }
    }
}
