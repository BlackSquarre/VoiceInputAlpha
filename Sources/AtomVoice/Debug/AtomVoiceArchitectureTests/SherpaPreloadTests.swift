import AVFoundation
import Cocoa
import Foundation
import Security
@testable import AtomVoiceCore

enum SherpaPreloadTests {
    static func run(_ runner: inout TestRunner) async {
        await runner.run("Model manifest discovers nested files offline") {
            let root = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let exp = root.appendingPathComponent("exp", isDirectory: true)
            let lang = root.appendingPathComponent("data/lang_char", isDirectory: true)
            try FileManager.default.createDirectory(at: exp, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: lang, withIntermediateDirectories: true)

            try writeDummyFile(exp.appendingPathComponent("streaming-encoder-int8.onnx"))
            try writeDummyFile(exp.appendingPathComponent("streaming-encoder.onnx"))
            try writeDummyFile(exp.appendingPathComponent("streaming-decoder-int8.onnx"))
            try writeDummyFile(exp.appendingPathComponent("streaming-decoder.onnx"))
            try writeDummyFile(exp.appendingPathComponent("streaming-joiner-int8.onnx"))
            try writeDummyFile(lang.appendingPathComponent("tokens.txt"))

            let manifest = try require(ModelManifest.discover(in: root), "manifest should be discovered")

            try expect(manifest.family == .onlineTransducer)
            try expect(manifest.encoder == "exp/streaming-encoder-int8.onnx")
            try expect(manifest.decoder == "exp/streaming-decoder.onnx")
            try expect(manifest.joiner == "exp/streaming-joiner-int8.onnx")
            try expect(manifest.tokens == "data/lang_char/tokens.txt")
            try expect(manifest.isComplete(in: root))
        }
        await runner.run("Model manifest discovers paraformer files without joiner") {
            let root = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: root) }
            let exp = root.appendingPathComponent("exp", isDirectory: true)
            let lang = root.appendingPathComponent("data/lang_char", isDirectory: true)
            try FileManager.default.createDirectory(at: exp, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: lang, withIntermediateDirectories: true)

            try writeDummyFile(exp.appendingPathComponent("paraformer-encoder.onnx"))
            try writeDummyFile(exp.appendingPathComponent("paraformer-encoder.int8.onnx"))
            try writeDummyFile(exp.appendingPathComponent("paraformer-decoder.onnx"))
            try writeDummyFile(exp.appendingPathComponent("paraformer-decoder.int8.onnx"))
            try writeDummyFile(lang.appendingPathComponent("tokens.txt"))

            let manifest = try require(ModelManifest.discover(in: root), "paraformer manifest should be discovered")

            try expect(manifest.family == .onlineParaformer)
            try expect(manifest.encoder == "exp/paraformer-encoder.int8.onnx")
            try expect(manifest.decoder == "exp/paraformer-decoder.int8.onnx")
            try expect(manifest.joiner == nil)
            try expect(manifest.tokens == "data/lang_char/tokens.txt")
            try expect(manifest.isComplete(in: root))
        }
        await runner.run("Model manifest loads legacy transducer manifest without family field") {
            let root = try makeTemporaryDirectory()
            defer { try? FileManager.default.removeItem(at: root) }

            try writeDummyFile(root.appendingPathComponent("encoder.int8.onnx"))
            try writeDummyFile(root.appendingPathComponent("decoder.onnx"))
            try writeDummyFile(root.appendingPathComponent("joiner.int8.onnx"))
            try writeDummyFile(root.appendingPathComponent("tokens.txt"))

            let legacy = """
            {"encoder":"encoder.int8.onnx","decoder":"decoder.onnx","joiner":"joiner.int8.onnx","tokens":"tokens.txt"}
            """
            try legacy.write(to: root.appendingPathComponent(ModelManifest.filename), atomically: true, encoding: .utf8)

            let manifest = try require(ModelManifest.load(from: root), "legacy manifest should load")

            try expect(manifest.family == .onlineTransducer)
            try expect(manifest.joiner == "joiner.int8.onnx")
            try expect(manifest.isComplete(in: root))
        }
    }
}
