import CoreML
import Foundation

/// Localiza e prepara os recursos embarcados pelo `resource_bundles` do podspec.
enum ModelAssets {
  enum AssetError: LocalizedError {
    case bundleMissing
    case modelMissing
    case imageMissing(String)

    var errorDescription: String? {
      switch self {
      case .bundleMissing:
        return "ViziVisionAssets.bundle não foi encontrado no app. O resource_bundles do podspec não entrou no build."
      case .modelMissing:
        return "Nem vizi-seg.mlmodelc nem vizi-seg.mlpackage foram encontrados no bundle de recursos."
      case .imageMissing(let name):
        return "Imagem de referência '\(name)' não encontrada no bundle de recursos."
      }
    }
  }

  static func assetsBundle() throws -> Bundle {
    let host = Bundle(for: BundleToken.self)
    guard let url = host.url(forResource: "ViziVisionAssets", withExtension: "bundle"),
          let bundle = Bundle(url: url)
    else { throw AssetError.bundleMissing }
    return bundle
  }

  /// URL de um modelo pronto para `MLModel(contentsOf:)`.
  ///
  /// Dois caminhos possíveis, porque não dá para saber de antemão qual acontece:
  /// se o Xcode compilou o `.mlpackage` durante o build, existe um `.mlmodelc`
  /// e ele é usado direto. Senão, o `.mlpackage` cru é compilado aqui, uma vez,
  /// e o resultado é guardado em cache — compilar custa segundos e não pode
  /// acontecer a cada abertura.
  static func compiledModelURL() throws -> (url: URL, compiledAtRuntime: Bool) {
    let bundle = try assetsBundle()

    if let precompiled = bundle.url(forResource: "vizi-seg", withExtension: "mlmodelc") {
      return (precompiled, false)
    }

    guard let package = bundle.url(forResource: "vizi-seg", withExtension: "mlpackage") else {
      throw AssetError.modelMissing
    }

    let caches = try FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    let cached = caches.appendingPathComponent("vizi-seg.mlmodelc")

    if FileManager.default.fileExists(atPath: cached.path) {
      return (cached, false)
    }

    let compiled = try MLModel.compileModel(at: package)
    try? FileManager.default.removeItem(at: cached)
    try FileManager.default.moveItem(at: compiled, to: cached)
    return (cached, true)
  }

  static func referenceImageURL(_ name: String = "reference") throws -> URL {
    let bundle = try assetsBundle()
    guard let url = bundle.url(forResource: name, withExtension: "jpg") else {
      throw AssetError.imageMissing(name)
    }
    return url
  }
}

private final class BundleToken {}
