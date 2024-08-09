import SwiftUI
import AVFoundation
import UIKit
import PocketCastsUtils

protocol AnimatableContent: View {
    func update(for progress: Double)
}

class SwiftUIVideoExporter<Content: AnimatableContent> {
    private let view: Content
    private let duration: TimeInterval
    private let size: CGSize
    private let fps: Int
    private let audioPlayerItem: AVPlayerItem?
    private let audioStartTime: CMTime
    private let audioDuration: CMTime

    init(view: Content, duration: TimeInterval, size: CGSize, fps: Int = 60, audioPlayerItem: AVPlayerItem, audioStartTime: CMTime, audioDuration: CMTime) {
        self.view = view
        self.duration = duration
        self.size = size
        self.fps = fps
        self.audioPlayerItem = audioPlayerItem
        self.audioStartTime = audioStartTime
        self.audioDuration = audioDuration
    }

    @MainActor
    func exportToMP4(outputURL: URL, progress: Progress) async throws {
        let loopDuration: Double = 10
        let loopFrameCount = Int(loopDuration * Double(fps))

        let start = Date()
        FileLog.shared.addMessage("SwiftUIVideoExporter Started: \(start)")

        let temporaryFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mp4")

        progress.totalUnitCount = Int64(loopFrameCount) + 50

        try await withTaskCancellationHandler {
            // Export initial 10-second video
            try await exportInitialVideo(to: temporaryFileURL, frameCount: loopFrameCount, progress: progress)
            FileLog.shared.addMessage("SwiftUIVideoExporter Initial Video Ended: \(start.timeIntervalSinceNow)")

            // Export final composition at full length
            try await createFinalComposition(from: temporaryFileURL, outputURL: outputURL, progress: progress)

            // Clean up temporary file
            try? FileManager.default.removeItem(at: temporaryFileURL)
            progress.completedUnitCount = progress.totalUnitCount
            FileLog.shared.addMessage("SwiftUIVideoExporter Ended: \(start.timeIntervalSinceNow)")
        } onCancel: {
            progress.cancel()
        }
    }

    // Step 1 of video export
    private func exportInitialVideo(to outputURL: URL, frameCount: Int, progress: Progress) async throws {
        let videoWriter = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: size.width,
            AVVideoHeightKey: size.height
        ]
        let videoWriterInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoWriterInput, sourcePixelBufferAttributes: nil)

        videoWriter.add(videoWriterInput)
        videoWriter.startWriting()
        videoWriter.startSession(atSourceTime: .zero)

        try await writeFrames(videoWriterInput: videoWriterInput, videoWriter: videoWriter, adaptor: adaptor, progress: progress, frameCount: frameCount)
    }

    // Part of Step 1
    private func writeFrames(videoWriterInput: AVAssetWriterInput, videoWriter: AVAssetWriter, adaptor: AVAssetWriterInputPixelBufferAdaptor, progress: Progress, frameCount: Int) async throws {
        let counter = Counter()

        try await videoWriterInput.unsafeRequestMediaDataWhenReady { [weak self] continuation in
            guard let self else { return }
            while await counter.count <= frameCount, videoWriterInput.isReadyForMoreMediaData {
                do {
                    try await counter.run {
                        let frameProgress = Double(await counter.count) / Double(frameCount)
                        self.view.update(for: frameProgress)

                        let buffer = try await self.pixelBuffer(for: self.view, size: self.size)
                        let frameTime = CMTime(seconds: Double(await counter.count) / Double(self.fps), preferredTimescale: CMTimeScale(NSEC_PER_SEC))
                        adaptor.append(buffer.wrappedValue, withPresentationTime: frameTime)
                        progress.completedUnitCount += 1
                    }
                } catch {
                    continuation.resume(throwing: error)
                    return
                }
            }

            if await counter.count >= frameCount {
                videoWriterInput.markAsFinished()
                videoWriter.finishWriting {
                    continuation.resume()
                }
            }
        }
    }

    @MainActor
    private func pixelBuffer(for view: some View, size: CGSize) throws -> UnsafeTransfer<CVPixelBuffer> {
        try UnsafeTransfer(view.frame(width: size.width, height: size.height).pixelBuffer(size: size))
    }

    // Part 2 of video export, creating the final track from the initial video loop
    private func createFinalComposition(from sourceURL: URL, outputURL: URL, progress: Progress) async throws {
        let asset = AVAsset(url: sourceURL)
        let composition = AVMutableComposition()

        guard let compositionVideoTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid),
              let sourceVideoTrack = try? await asset.loadTracks(withMediaType: .video).first else {
            throw ExportError.failedToCreateCompositionTrack
        }

        let sourceTimeRange = try await asset.load(.duration)
        var currentTime: CMTime = .zero

        while currentTime < CMTime(seconds: duration, preferredTimescale: 600) {
            try compositionVideoTrack.insertTimeRange(CMTimeRange(start: .zero, duration: sourceTimeRange),
                                                      of: sourceVideoTrack,
                                                      at: currentTime)
            currentTime = CMTimeAdd(currentTime, sourceTimeRange)
        }

        if let audioPlayerItem = audioPlayerItem,
           let audioTrack = try await audioPlayerItem.asset.loadTracks(withMediaType: .audio).first {
            try add(audioTrack: audioTrack, to: composition)
        }

        try await exportFinalComposition(composition: composition, outputURL: outputURL, progress: progress)
    }

    // Part of Step 2 of video export to add the audio track
    private func add(audioTrack: AVAssetTrack, to composition: AVMutableComposition) throws {
        guard let compositionAudioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw ExportError.failedToAddAudioTrack
        }
        try compositionAudioTrack.insertTimeRange(CMTimeRange(start: audioStartTime, duration: audioDuration), of: audioTrack, at: .zero)
    }

    // Part of Step 2 of video export to export the final file
    private func exportFinalComposition(composition: AVMutableComposition, outputURL: URL, progress: Progress) async throws {
        guard let exportSession = AVAssetExportSession(asset: composition, presetName: AVAssetExportPresetHighestQuality) else {
            throw ExportError.failedToCreateExportSession
        }

        exportSession.outputURL = outputURL
        exportSession.outputFileType = .mp4
        exportSession.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: duration, preferredTimescale: 600))

        let timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            progress.completedUnitCount = (progress.totalUnitCount - 50) + Int64((50 * exportSession.progress))
        }

        await exportSession.export()
        timer.invalidate()

        guard exportSession.status == .completed else {
            throw ExportError.exportFailed(exportSession.error)
        }
    }

    enum ExportError: Error {
        case failedToCreateAssetWriter
        case failedToCreateCompositionTrack
        case failedToCreateExportSession
        case failedToAddAudioTrack
        case exportFailed(Error?)
        case exportCancelled
        case unknownError
    }
}

/// Used to safely increment a counter from within an async context
actor Counter {
    var count: Int = 0

    func run(block: () async throws -> Void) async throws {
        try await block()
        await increment()
    }

    func increment() async {
        count += 1
    }
}

extension AVAssetWriterInput {
    func unsafeRequestMediaDataWhenReady(_ block: @escaping (CheckedContinuation<Void, Error>) async -> Void) async throws {
        try await withCheckedThrowingContinuation { continuation in
            requestMediaDataWhenReady(on: .global(qos: .userInitiated)) {
                _unsafeWait {
                    await block(continuation)
                }
            }
        }
    }
}
