import CoreImage
import CoreVideo
import Foundation

/// Peças da correção de perspectiva que não dependem de como ela é estimada.
///
/// A estimativa em si vive na `PlaneRectifier`. O `straighten` que morava aqui
/// retificava pelo quadrilátero dos objetos, e ficou sem chamador quando a
/// retificação passou a ser do plano.
enum Rectify {

  /// Uma fileira no resultado retificado.
  struct Shelf {
    var count: Int
    /// Divisões entre livros, normalizadas de 0 a 1 na largura.
    var dividers: [Double]
    /// Banda vertical que a fileira ocupa, normalizada de 0 a 1.
    var top: Double
    var bottom: Double
  }

  /// Resolve a homografia que leva `src` em `dst` — DLT de 4 pontos.
  ///
  /// O `CIPerspectiveCorrection` faz o warp sozinho, mas não devolve a matriz.
  /// A transição precisa dela para animar os cantos (R16).
  static func homography(from src: [CGPoint], to dst: [CGPoint]) -> [Double]? {
    guard src.count == 4, dst.count == 4 else { return nil }
    var a = [[Double]](repeating: [Double](repeating: 0, count: 9), count: 8)

    for i in 0..<4 {
      let x = Double(src[i].x), y = Double(src[i].y)
      let u = Double(dst[i].x), v = Double(dst[i].y)
      a[i * 2] = [x, y, 1, 0, 0, 0, -u * x, -u * y, u]
      a[i * 2 + 1] = [0, 0, 0, x, y, 1, -v * x, -v * y, v]
    }

    // Eliminação de Gauss com pivotamento parcial.
    for col in 0..<8 {
      var pivot = col
      for r in (col + 1)..<8 where abs(a[r][col]) > abs(a[pivot][col]) { pivot = r }
      guard abs(a[pivot][col]) > 1e-12 else { return nil }
      a.swapAt(col, pivot)
      let d = a[col][col]
      for c in col...8 { a[col][c] /= d }
      for r in 0..<8 where r != col {
        let f = a[r][col]
        guard f != 0 else { continue }
        for c in col...8 { a[r][c] -= f * a[col][c] }
      }
    }
    return (0..<8).map { a[$0][8] } + [1.0]
  }
}

extension Rectify {
  /// Renderiza para um buffer exibível. Uma vez por captura, não por frame.
  static func render(_ image: CIImage, context: CIContext) -> CVPixelBuffer? {
    let w = Int(image.extent.width.rounded()), h = Int(image.extent.height.rounded())
    guard w > 0, h > 0 else { return nil }

    var buffer: CVPixelBuffer?
    let attrs: [String: Any] = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferIOSurfacePropertiesKey as String: [:],
    ]
    guard CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA,
                              attrs as CFDictionary, &buffer) == kCVReturnSuccess,
          let buffer else { return nil }

    // Reancorar: a extensão pode ter origem negativa depois do recorte.
    let anchored = image.transformed(by: CGAffineTransform(
      translationX: -image.extent.minX, y: -image.extent.minY))
    context.render(anchored, to: buffer)
    return buffer
  }
}
