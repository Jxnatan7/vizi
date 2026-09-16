import CoreGraphics
import CoreML
import CoreVideo
import Foundation
import ImageIO

/// Carga do modelo, preparo da entrada e cronometragem.
///
/// Nada aqui decide política: repetições, descarte de aquecimento e limiar de
/// confiança chegam como parâmetro do TypeScript (princípio IV).
final class InferenceEngine {
  enum EngineError: LocalizedError {
    case notLoaded
    case badOutput(String)
    case imageDecode

    var errorDescription: String? {
      switch self {
      case .notLoaded: return "Modelo não carregado. Chame loadModel() antes."
      case .badOutput(let d): return "Saída do modelo em formato inesperado: \(d)"
      case .imageDecode: return "Não foi possível decodificar a imagem de referência."
      }
    }
  }

  private var model: MLModel?
  private var inputName = ""
  private var referenceBuffer: CVPixelBuffer?

  private(set) var inputWidth = 0
  private(set) var inputHeight = 0
  private(set) var maskCoeffCount = 32
  private(set) var classes: [Int: String] = [:]
  private(set) var requestedComputeUnits = "all"
  private(set) var compiledAtRuntime = false
  private(set) var compileMs: Double = 0

  // MARK: - Carga

  func load() throws {
    let started = CFAbsoluteTimeGetCurrent()
    let (url, compiled) = try ModelAssets.compiledModelURL()
    compiledAtRuntime = compiled

    let config = MLModelConfiguration()
    config.computeUnits = .all   // deixa o sistema usar o acelerador dedicado
    let m = try MLModel(contentsOf: url, configuration: config)
    compileMs = (CFAbsoluteTimeGetCurrent() - started) * 1000

    let desc = m.modelDescription

    guard let input = desc.inputDescriptionsByName.first(where: {
      $0.value.type == .image
    }) else {
      throw EngineError.badOutput("nenhuma entrada do tipo imagem")
    }
    inputName = input.key
    if let c = input.value.imageConstraint {
      inputWidth = c.pixelsWide
      inputHeight = c.pixelsHigh
    }

    // Os nomes de saída são gerados automaticamente (var_1011, var_1049) e
    // mudam entre exports. Resolver por FORMA: 3 dimensões é detecção,
    // 4 dimensões são os protótipos de máscara.
    for (_, out) in desc.outputDescriptionsByName {
      guard let shape = out.multiArrayConstraint?.shape.map({ $0.intValue }) else { continue }
      if shape.count == 4 { maskCoeffCount = shape[1] }
    }

    classes = parseClassNames(from: desc.metadata)
    model = m
    referenceBuffer = try makeReferenceBuffer()
  }

  func unload() {
    model = nil
    referenceBuffer = nil
  }

  private func parseClassNames(from metadata: [MLModelMetadataKey: Any]) -> [Int: String] {
    guard let user = metadata[.creatorDefinedKey] as? [String: String],
          let raw = user["names"] else { return [:] }
    // Formato do Ultralytics: {0: 'book', 1: 'other'}
    var out: [Int: String] = [:]
    let scanner = raw.replacingOccurrences(of: "'", with: "\"")
    for part in scanner.trimmingCharacters(in: CharacterSet(charactersIn: "{}")).split(separator: ",") {
      let kv = part.split(separator: ":", maxSplits: 1)
      guard kv.count == 2,
            let k = Int(kv[0].trimmingCharacters(in: .whitespaces)) else { continue }
      out[k] = kv[1].trimmingCharacters(in: CharacterSet.whitespaces.union(CharacterSet(charactersIn: "\"")))
    }
    return out
  }

  // MARK: - Entrada

  /// A imagem vira CVPixelBuffer UMA vez, na carga.
  ///
  /// Na câmera, o frame já chega como CVPixelBuffer — decodificar JPEG a cada
  /// iteração inflaria o ciclo com um custo que o app real nunca paga.
  private func makeReferenceBuffer() throws -> CVPixelBuffer {
    let url = try ModelAssets.referenceImageURL()
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cg = CGImageSourceCreateImageAtIndex(src, 0, nil)
    else { throw EngineError.imageDecode }

    var pb: CVPixelBuffer?
    let attrs: [CFString: Any] = [
      kCVPixelBufferCGImageCompatibilityKey: true,
      kCVPixelBufferCGBitmapContextCompatibilityKey: true,
    ]
    CVPixelBufferCreate(kCFAllocatorDefault, inputWidth, inputHeight,
                        kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb)
    guard let buffer = pb else { throw EngineError.imageDecode }

    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let ctx = CGContext(
      data: CVPixelBufferGetBaseAddress(buffer),
      width: inputWidth, height: inputHeight,
      bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        | CGBitmapInfo.byteOrder32Little.rawValue)
    else { throw EngineError.imageDecode }

    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: inputWidth, height: inputHeight))
    return buffer
  }

  // MARK: - Execução

  struct RunResult {
    var modelMs: Double
    var cycleMs: Double
    var instances: [Instance]
  }

  func runOnce(confidenceThreshold: Float) throws -> RunResult {
    guard let model, let referenceBuffer else { throw EngineError.notLoaded }

    let cycleStart = CFAbsoluteTimeGetCurrent()

    let provider = try MLDictionaryFeatureProvider(
      dictionary: [inputName: MLFeatureValue(pixelBuffer: referenceBuffer)])

    let modelStart = CFAbsoluteTimeGetCurrent()
    let out = try model.prediction(from: provider)
    let modelMs = (CFAbsoluteTimeGetCurrent() - modelStart) * 1000

    var detections: MLMultiArray?
    for name in out.featureNames {
      guard let arr = out.featureValue(for: name)?.multiArrayValue else { continue }
      if arr.shape.count == 3 { detections = arr }
    }
    guard let detections else { throw EngineError.badOutput("saída de detecção ausente") }

    let instances = Decode.instances(
      from: detections,
      maskCoeffCount: maskCoeffCount,
      confidenceThreshold: confidenceThreshold,
      inputWidth: inputWidth,
      inputHeight: inputHeight)

    return RunResult(
      modelMs: modelMs,
      cycleMs: (CFAbsoluteTimeGetCurrent() - cycleStart) * 1000,
      instances: instances)
  }

  static func thermalStateLabel() -> String {
    switch ProcessInfo.processInfo.thermalState {
    case .nominal: return "nominal"
    case .fair: return "fair"
    case .serious: return "serious"
    case .critical: return "critical"
    @unknown default: return "unknown"
    }
  }
}
