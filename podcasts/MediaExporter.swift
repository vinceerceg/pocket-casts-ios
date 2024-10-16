import Foundation
import AVFoundation
import PocketCastsUtils

struct MediaExporter {

    #if !os(watchOS)

    typealias ProgressCallback = (Float, Int64) -> ()

    private static var currentExporter: AVAssetExportSession?

    private static func reportProgress(session: AVAssetExportSession, progressCallback: ProgressCallback? = nil) async {
        let statusInProgress: Set<AVAssetExportSession.Status> = [.unknown, .exporting, .waiting]
        let size = (try? await session.estimatedOutputFileLengthInBytes) ?? 0
        while session.progress != 1, statusInProgress.contains(session.status) {
            progressCallback?(session.progress, size)
            try? await Task.sleep(nanoseconds: 1 * 1_000_000_000)
            //Only enable the logging bellow in order to help debug export session progress.
            //FileLog.shared.addMessage("DownloadManager export session: \(session.outputURL!.lastPathComponent) | \(session.progress) | \(session.status) | \(size)")
        }
    }

    static func exportMediaItem(_ item: AVPlayerItem, to outputURL: URL, progressCallback: ProgressCallback? = nil) async -> Bool {
        currentExporter?.cancelExport()
        let composition = AVMutableComposition()

        guard let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: CMPersistentTrackID(kCMPersistentTrackID_Invalid)),
            let tracks = try? await item.asset.loadTracks(withMediaType: .audio),
            let sourceAudioTrack = tracks.first else {
            FileLog.shared.addMessage("DownloadManager export session: failed to create audio track")
            return false
        }
        do {
            try compositionAudioTrack.insertTimeRange(CMTimeRangeMake(start: .zero, duration: item.asset.duration), of: sourceAudioTrack, at: CMTime.zero)
        } catch {
            FileLog.shared.addMessage("DownloadManager export session: failed to create audio track -> \(error)")
            return false
        }

        guard let exporter = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            FileLog.shared.addMessage("DownloadManager export session: failed to create export session")
            return false
        }
        currentExporter = exporter
        exporter.outputURL = outputURL
        exporter.outputFileType = AVFileType.m4a

        if FileManager.default.fileExists(atPath: outputURL.path) {
            do {
                try FileManager.default.removeItem(at: outputURL)
            } catch let error {
                FileLog.shared.addMessage("DownloadManager export session: failed to delete file with error -> \(error)")
                return false
            }
        }
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                await exporter.export()
            }
            group.addTask {
                await reportProgress(session: exporter, progressCallback: progressCallback)
            }
        }

        if let error = exporter.error {
            FileLog.shared.addMessage("DownloadManager export session: finished with error -> \(error)")
        }

        if exporter.status == .cancelled {
            FileLog.shared.addMessage("DownloadManager export session: cancelled")
            return false
        }

        if exporter.status == .failed {
            FileLog.shared.addMessage("DownloadManager export session: failed")
            return false
        }
        FileLog.shared.addMessage("DownloadManager export session: Finished exporting successfully")
        return true
    }
    #endif
}
