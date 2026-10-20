import Foundation
import UIKit

/// Exportar uma sessão de coleta (spec 007, R44): o zip vem do próprio
/// sistema, e o menu de compartilhar é o do iOS. Nenhuma dependência nova.
enum CollectionExport {

  /// O `FORMAT.md` vai para a pasta da sessão antes do zip (FR-017). Ele vem
  /// do bundle, para onde o config plugin o copia a partir do contrato da
  /// spec — uma cópia só, que não diverge.
  static func copyFormat(into folder: URL) throws {
    let bundle = try ModelAssets.assetsBundle()
    guard let source = bundle.url(forResource: "FORMAT", withExtension: "md")
      ?? Bundle.main.url(forResource: "FORMAT", withExtension: "md")
    else {
      throw CollectionRecorder.RecorderError.export(
        "FORMAT.md não está no bundle do app — o withViziAssets não o copiou.")
    }
    let fm = FileManager.default
    let destination = folder.appendingPathComponent("FORMAT.md")
    try? fm.removeItem(at: destination)
    do {
      try fm.copyItem(at: source, to: destination)
    } catch {
      throw CollectionRecorder.RecorderError.export(error.localizedDescription)
    }
  }

  /// Ler uma pasta com `.forUploading` entrega um zip dela num endereço
  /// temporário, que vale enquanto a leitura dura. Ele sai de lá para
  /// `destination`, substituindo o anterior.
  static func zip(_ folder: URL, to destination: URL) throws {
    let fm = FileManager.default
    var coordinationError: NSError?
    var moveError: Error?
    NSFileCoordinator().coordinate(
      readingItemAt: folder, options: [.forUploading], error: &coordinationError
    ) { zipped in
      do {
        try? fm.removeItem(at: destination)
        do {
          try fm.moveItem(at: zipped, to: destination)
        } catch {
          try fm.copyItem(at: zipped, to: destination)
        }
      } catch {
        moveError = error
      }
    }
    if let error = (coordinationError as Error?) ?? moveError {
      throw CollectionRecorder.RecorderError.export(error.localizedDescription)
    }
  }

  /// `vizi-coleta-<id>[-<nome>].zip`, com o nome sem acento nem espaço.
  static func shareName(id: String, name: String?) -> String {
    var slug = ""
    if let name {
      let folded = name.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        .lowercased()
      let parts = folded.unicodeScalars.split { !CharacterSet.alphanumerics.contains($0) }
      slug = parts.map { String(String.UnicodeScalarView($0)) }.joined(separator: "-")
    }
    return slug.isEmpty ? "vizi-coleta-\(id).zip" : "vizi-coleta-\(id)-\(slug).zip"
  }

  /// O menu de compartilhar, a partir do controlador atual. Devolve se a
  /// pessoa compartilhou; fechar sem escolher devolve `false`, e o zip fica.
  ///
  /// O que vai ao menu é um link com o nome sugerido — o menu mostra o nome do
  /// arquivo, e o zip guardado continua com o id. Link físico: nada é copiado.
  @MainActor
  static func share(_ zip: URL, named name: String, from presenter: UIViewController) async -> Bool {
    let fm = FileManager.default
    let folder = fm.temporaryDirectory.appendingPathComponent("vizi-share", isDirectory: true)
    // Os links da exportação anterior saem aqui, e não ao fechar o menu: uma
    // transferência pode continuar depois dele.
    try? fm.removeItem(at: folder)
    try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
    let link = folder.appendingPathComponent(name)
    let item = (try? fm.linkItem(at: zip, to: link)) != nil ? link : zip

    // O UIKit recusa apresentar de um controlador fora da janela ou que já
    // apresenta outro — e aí o menu nunca fecha, porque nunca abriu, e a
    // promessa ficaria pendurada. O zip já está guardado de qualquer jeito.
    guard presenter.viewIfLoaded?.window != nil, presenter.presentedViewController == nil else {
      return false
    }

    return await withCheckedContinuation { continuation in
      var resumed = false
      let activity = UIActivityViewController(activityItems: [item], applicationActivities: nil)
      activity.completionWithItemsHandler = { _, completed, _, _ in
        guard !resumed else { return }
        resumed = true
        continuation.resume(returning: completed)
      }
      activity.popoverPresentationController?.sourceView = presenter.view
      presenter.present(activity, animated: true)
    }
  }
}
