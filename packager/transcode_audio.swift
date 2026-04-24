import AVFoundation
import Foundation

func transcode(inputPath: String, outputPath: String) -> Int32 {
    let input = URL(fileURLWithPath: inputPath)
    let output = URL(fileURLWithPath: outputPath)
    try? FileManager.default.removeItem(at: output)

    let asset = AVURLAsset(url: input)
    guard let exporter = AVAssetExportSession(
        asset: asset,
        presetName: AVAssetExportPresetAppleM4A
    ) else {
        FileHandle.standardError.write(Data("failed to create exporter\n".utf8))
        return 1
    }

    exporter.outputURL = output
    exporter.outputFileType = .m4a

    let semaphore = DispatchSemaphore(value: 0)
    exporter.exportAsynchronously { semaphore.signal() }
    semaphore.wait()

    if exporter.status == .completed {
        return 0
    }

    let message =
        "export failed: \(exporter.status.rawValue) \(exporter.error?.localizedDescription ?? "unknown")\n"
    FileHandle.standardError.write(Data(message.utf8))
    return 2
}

guard CommandLine.arguments.count == 3 else {
    FileHandle.standardError.write(
        Data("usage: swift transcode_audio.swift input.mp3 output.m4a\n".utf8)
    )
    exit(64)
}

exit(transcode(inputPath: CommandLine.arguments[1], outputPath: CommandLine.arguments[2]))
