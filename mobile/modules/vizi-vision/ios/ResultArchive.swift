import CoreImage
import CoreVideo
import Foundation
import ImageIO

/// Grava no histórico o resultado que está na tela (US4, FR-013).
///
/// A imagem nasce e fica no nativo; o JavaScript recebe um caminho, nunca
/// pixels (princípio II). O caminho é **relativo** à pasta de documentos: o
/// iOS troca o caminho absoluto do contêiner quando o app é reinstalado, e a
/// reassinatura a cada 7 dias reinstala. Um caminho absoluto no índice
/// apontaria para o nada depois da primeira renovação.
enum ResultArchive {

  enum ArchiveError: LocalizedError {
    case noResult
    case folder(String)
    case write(String)

    var errorDescription: String? {
      switch self {
      case .noResult:
        return "Não há resultado na tela para salvar."
      case .folder(let m):
        return "Não foi possível criar a pasta do histórico: \(m)"
      case .write(let m):
        // Armazenamento cheio é o caso provável, e é o que a pessoa pode
        // resolver — daí vir antes do detalhe técnico.
        return "Não foi possível gravar a imagem — o aparelho pode estar sem espaço. (\(m))"
      }
    }
  }

  /// Pasta dentro dos documentos. O índice, mantido pelo TypeScript, mora ao
  /// lado das imagens.
  static let folderName = "history"

  struct Saved {
    /// Relativo à pasta de documentos.
    var file: String
    var width: Int
    var height: Int
    var bytes: Int
  }

  /// JPEG, e não HEIC: é o formato que vai sem conversão para o Colab, onde a
  /// releitura da faixa vai ser medida.
  static func save(
    _ buffer: CVPixelBuffer, id: String, quality: Double, context: CIContext
  ) throws -> Saved {
    let fm = FileManager.default
    guard let documents = fm.urls(for: .documentDirectory, in: .userDomainMask).first else {
      throw ArchiveError.folder("pasta de documentos indisponível")
    }
    let folder = documents.appendingPathComponent(folderName, isDirectory: true)
    do {
      try fm.createDirectory(at: folder, withIntermediateDirectories: true)
    } catch {
      throw ArchiveError.folder(error.localizedDescription)
    }

    let name = "\(id).jpg"
    let url = folder.appendingPathComponent(name)
    guard let space = CGColorSpace(name: CGColorSpace.sRGB) else {
      throw ArchiveError.write("espaço de cor sRGB indisponível")
    }
    let qualityKey = CIImageRepresentationOption(
      rawValue: kCGImageDestinationLossyCompressionQuality as String)
    do {
      try context.writeJPEGRepresentation(
        of: CIImage(cvPixelBuffer: buffer), to: url, colorSpace: space,
        options: [qualityKey: quality])
    } catch {
      throw ArchiveError.write(error.localizedDescription)
    }

    let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? NSNumber
    return Saved(
      file: "\(folderName)/\(name)",
      width: CVPixelBufferGetWidth(buffer),
      height: CVPixelBufferGetHeight(buffer),
      bytes: size?.intValue ?? 0)
  }
}
