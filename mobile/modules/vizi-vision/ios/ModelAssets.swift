import CoreML
import Foundation

/// Localiza e prepara os recursos embarcados pelo `resource_bundles` do podspec.
enum ModelAssets {
  enum AssetError: LocalizedError {
    case bundleMissing
    case modelMissing(contents: [String])
    case imageMissing(String, contents: [String])

    var errorDescription: String? {
      switch self {
      case .bundleMissing:
        return "ViziVisionAssets.bundle não foi encontrado no app. O resource_bundles do podspec não entrou no build."
      case .modelMissing(let contents):
        return "Nem vizi-seg.mlmodelc nem vizi-seg.mlpackage no bundle. Conteúdo: \(describe(contents))"
      case .imageMissing(let name, let contents):
        return "Imagem '\(name).jpg' não está no bundle. Conteúdo: \(describe(contents))"
      }
    }
  }

  /// O que o bundle realmente contém. Sem console no aparelho, esta lista é a
  /// única forma de distinguir "o recurso não foi copiado" de "o nome mudou".
  private static func contents(of bundle: Bundle) -> [String] {
    (try? FileManager.default.contentsOfDirectory(atPath: bundle.bundlePath)) ?? []
  }

  private static func describe(_ items: [String]) -> String {
    items.isEmpty ? "(vazio)" : items.sorted().joined(separator: ", ")
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

    // O Xcode pode ter compilado o .mlpackage durante o build; se compilou,
    // não há o que fazer em tempo de execução.
    if let precompiled = bundle.url(forResource: "vizi-seg", withExtension: "mlmodelc")
      ?? Bundle.main.url(forResource: "vizi-seg", withExtension: "mlmodelc") {
      return (precompiled, false)
    }

    guard let package = bundle.url(forResource: "vizi-seg", withExtension: "mlpackage")
      // Se o CocoaPods copiar para o bundle principal em vez do sub-bundle.
      ?? Bundle.main.url(forResource: "vizi-seg", withExtension: "mlpackage")
    else {
      throw AssetError.modelMissing(contents: contents(of: bundle))
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
    guard let url = bundle.url(forResource: name, withExtension: "jpg")
      ?? Bundle.main.url(forResource: name, withExtension: "jpg")
    else {
      throw AssetError.imageMissing(name, contents: contents(of: bundle))
    }
    return url
  }
}

private final class BundleToken {}
