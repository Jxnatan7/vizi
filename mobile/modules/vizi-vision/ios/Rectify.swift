import CoreImage
import CoreVideo
import Foundation

/// Aplica a correção de perspectiva e recorta a faixa de livros.
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

  struct Output {
    var image: CIImage
    var shelves: [Shelf]
  }

  /// Resolve a homografia que leva `src` em `dst` — DLT de 4 pontos.
  ///
  /// O `CIPerspectiveCorrection` faz o warp sozinho, mas não devolve a matriz.
  /// Precisamos dela para mapear as fronteiras entre livros (FR-008) e, no
  /// marco seguinte, para animar a transição.
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

  static func apply(_ h: [Double], to p: CGPoint) -> CGPoint {
    let x = Double(p.x), y = Double(p.y)
    let w = h[6] * x + h[7] * y + h[8]
    guard abs(w) > 1e-12 else { return .zero }
    return CGPoint(x: (h[0] * x + h[1] * y + h[2]) / w,
                   y: (h[3] * x + h[4] * y + h[5]) / w)
  }

  /// - Parameters:
  ///   - photo: a foto original, em qualquer orientação
  ///   - quad: o quadrilátero da estante inteira, no espaço canônico
  ///   - rows: as fileiras, para divisões e bandas
  static func straighten(
    photo: CVPixelBuffer,
    quad: ShelfGeometry.Quad,
    rows: [ShelfGeometry.Row],
    instances: [Instance],
    imageSide: Int,
    margin: Double
  ) -> Output? {
    // Mesma normalização de orientação do caminho canônico. Sem isto os cantos
    // não corresponderiam à foto.
    var image = CIImage(cvPixelBuffer: photo)
    if image.extent.width > image.extent.height { image = image.oriented(.right) }
    image = image.transformed(by: CGAffineTransform(
      translationX: -image.extent.minX, y: -image.extent.minY))

    // Canônico (640×640) → foto normalizada. Esticamento alinhado aos eixos,
    // então basta escalar cada coordenada.
    let sx = image.extent.width / CGFloat(imageSide)
    let sy = image.extent.height / CGFloat(imageSide)
    let toPhoto = { (p: CGPoint) in CGPoint(x: p.x * sx, y: p.y * sy) }

    // O CIImage tem a origem embaixo; o espaço do modelo tem em cima.
    let flip = { (p: CGPoint) in CGPoint(x: p.x, y: image.extent.height - p.y) }
    let src = [quad.topLeft, quad.topRight, quad.bottomRight, quad.bottomLeft]
      .map { flip(toPhoto($0)) }

    guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
    filter.setValue(image, forKey: kCIInputImageKey)
    filter.setValue(CIVector(cgPoint: src[0]), forKey: "inputTopLeft")
    filter.setValue(CIVector(cgPoint: src[1]), forKey: "inputTopRight")
    filter.setValue(CIVector(cgPoint: src[2]), forKey: "inputBottomRight")
    filter.setValue(CIVector(cgPoint: src[3]), forKey: "inputBottomLeft")
    guard var corrected = filter.outputImage else { return nil }

    let w = corrected.extent.width, h = corrected.extent.height
    guard w > 1, h > 1 else { return nil }

    // A mesma homografia, calculada por nós, para mapear fronteiras e bandas.
    let dst = [CGPoint(x: 0, y: h), CGPoint(x: w, y: h),
               CGPoint(x: w, y: 0), CGPoint(x: 0, y: 0)]
    var shelves: [Shelf] = []

    if let hm = homography(from: src, to: dst) {
      let project = { (p: CGPoint) in apply(hm, to: flip(toPhoto(p))) }

      // Fileiras de baixo para cima na imagem viram de cima para baixo aqui.
      for row in rows.sorted(by: { $0.level > $1.level }) {
        let members = row.indices.compactMap { instances.indices.contains($0) ? instances[$0] : nil }
        guard !members.isEmpty else { continue }
        let ordered = members.sorted { $0.x < $1.x }

        var cuts: [Double] = []
        for i in 0..<max(0, ordered.count - 1) {
          let edge = CGFloat(ordered[i].x + ordered[i].width + ordered[i + 1].x) / 2
          let y = row.usedForGeometry
            ? CGFloat(row.slope * Double(edge) + row.intercept)
            : CGFloat(ordered[i].y + ordered[i].height)
          let t = Double(project(CGPoint(x: edge, y: y)).x / w)
          if t > 0.01, t < 0.99 { cuts.append(t) }
        }

        // Banda vertical: do topo mais alto à base mais baixa da fileira.
        let topY = CGFloat(members.map(\.y).min() ?? 0)
        let bottomY = CGFloat(members.map { $0.y + $0.height }.max() ?? 0)
        let midX = CGFloat(members.map { $0.x + $0.width / 2 }.reduce(0, +)) / CGFloat(members.count)
        let topN = 1 - Double(project(CGPoint(x: midX, y: topY)).y / h)
        let bottomN = 1 - Double(project(CGPoint(x: midX, y: bottomY)).y / h)

        shelves.append(Shelf(count: members.count, dividers: cuts,
                             top: min(topN, bottomN), bottom: max(topN, bottomN)))
      }
    }

    // Recorte com margem, sobre o resultado já retificado.
    let inset = CGFloat(margin) * h
    corrected = corrected.cropped(to: corrected.extent.insetBy(dx: -inset, dy: -inset))
    return Output(image: corrected, shelves: shelves)
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
