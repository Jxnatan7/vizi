import CoreImage
import Foundation

/// Retifica o **plano**, não os objetos.
///
/// A gravidade dá a vertical; o azimute dá a horizontal. Os livros deixam de
/// participar da transformação e passam a definir apenas **o que aparece** —
/// que são responsabilidades diferentes e estavam misturadas no quadrilátero.
enum PlaneRectifier {

  struct Output {
    var image: CIImage
    /// `false` quando só a rotação foi corrigida, sem perspectiva.
    var fullyRectified: Bool
    /// Mapeia do espaço da foto em retrato para o resultado.
    var transform: [Double]
    /// Onde o recorte caiu na foto original. Só para diagnóstico.
    var sourceQuad: [CGPoint]
    /// Ponto de fuga vertical usado, para diagnóstico.
    var verticalVP: Projective.H?
    /// Qual guarda disparou, quando houve recuo. Sem isto, "não endireitou"
    /// tem cinco causas possíveis com o mesmo sintoma.
    var fallbackReason: String?
    /// Retângulo do recorte no espaço retificado. Com ele e a `transform`,
    /// qualquer ponto da foto vira coordenada normalizada do resultado — é o
    /// que permite posicionar as divisões.
    var cropLeft = 0.0
    var cropRight = 0.0
    var cropTop = 0.0
    var cropBottom = 0.0

    /// Ponto da foto → coordenada de 0 a 1 no resultado.
    func normalize(_ p: CGPoint) -> CGPoint? {
      guard let r = PlaneRectifier.apply(transform, p) else { return nil }
      let dx = cropRight - cropLeft, dy = cropBottom - cropTop
      guard abs(dx) > 1e-9, abs(dy) > 1e-9 else { return nil }
      return CGPoint(x: (Double(r.x) - cropLeft) / dx, y: (Double(r.y) - cropTop) / dy)
    }
  }

  /// - Parameters:
  ///   - portrait: a foto normalizada em retrato
  ///   - region: extensão dos objetos, em coordenadas da foto em retrato
  ///   - horizontalVP: `nil` recua para só endireitar a rotação
  static func rectify(
    portrait image: CIImage,
    gravity g: DeviceAttitude.Gravity,
    horizontalVP: Projective.H?,
    region: [CGPoint],
    fieldOfViewDegrees fov: Double,
    margin: Double
  ) -> Output? {
    guard !region.isEmpty else { return nil }
    let w = image.extent.width, h = image.extent.height
    let cx = Double(w) / 2, cy = Double(h) / 2

    let half = fov * .pi / 360
    let f = half > 1e-6 ? (Double(max(w, h)) / 2) / tan(half) : Double(max(w, h))

    // Vertical do mundo, projetada: para onde as verticais convergem.
    let up = (-g.x, -g.y, -g.z)
    let verticalVP: Projective.H = (cx * up.2 + f * up.0, cy * up.2 + f * up.1, up.2)

    guard let hVP = horizontalVP else {
      return rotationOnly(image: image, gravity: g, region: region, margin: margin)
    }

    // Origem no centro dos objetos: mantém o sistema bem condicionado.
    let ox = region.map { Double($0.x) }.reduce(0, +) / Double(region.count)
    let oy = region.map { Double($0.y) }.reduce(0, +) / Double(region.count)

    // **Normalizar as colunas.** Com livros verticais e estante quase frontal,
    // os dois pontos de fuga ficam perto do infinito e seus vetores homogêneos
    // saem com magnitudes muito diferentes — um na casa de 10⁶, outro de 10³.
    // A matriz fica mal escalada, as coordenadas retificadas saem com
    // proporção absurda, e a guarda de proporção rejeita o caso BOM.
    func unit(_ v: Projective.H) -> Projective.H {
      let n = sqrt(v.x * v.x + v.y * v.y + v.w * v.w)
      return n > 1e-12 ? (v.x / n, v.y / n, v.w / n) : v
    }
    let hN = unit(hVP), vN = unit(verticalVP), oN = unit((ox, oy, 1))

    // M leva o espaço retificado ao espaço da foto:
    //   (1,0,0) → ponto de fuga horizontal
    //   (0,1,0) → ponto de fuga vertical
    //   (0,0,1) → origem
    let m: [Double] = [hN.x, vN.x, oN.x,
                       hN.y, vN.y, oN.y,
                       hN.w, vN.w, oN.w]
    guard let hMat = invert(m) else {
      return rotationOnly(image: image, gravity: g, region: region, margin: margin)
    }

    // Onde os objetos caem no espaço retificado.
    let mapped = region.compactMap { apply(hMat, $0) }
    guard mapped.count == region.count else {
      return rotationOnly(image: image, gravity: g, region: region, margin: margin)
    }
    // Um ponto perto da linha de fuga explode ao ser retificado, e um único
    // desses domina o retângulo. O diagnóstico mostrou o recorte colapsando
    // numa linha — era isto.
    for p in mapped where !p.x.isFinite || !p.y.isFinite {
      return rotationOnly(image: image, gravity: g, region: region, margin: margin, reason: "ponto retificado não-finito")
    }
    var minX = mapped.map(\.x).min()!, maxX = mapped.map(\.x).max()!
    var minY = mapped.map(\.y).min()!, maxY = mapped.map(\.y).max()!
    let spanX = maxX - minX, spanY = maxY - minY
    guard spanX > 1e-6, spanY > 1e-6 else {
      return rotationOnly(image: image, gravity: g, region: region, margin: margin, reason: "retângulo sem extensão")
    }
    // Proporção absurda indica que a retificação esticou um eixo ao infinito.
    let ratio = max(spanX, spanY) / min(spanX, spanY)
    guard ratio < 40 else {
      return rotationOnly(image: image, gravity: g, region: region, margin: margin, reason: "proporção acima de 40:1")
    }

    // A margem entra AQUI, no espaço retificado — é o que garante que a base
    // dos livros apareça inteira, em vez de depender da geometria estimada.
    let mx = (maxX - minX) * margin, my = (maxY - minY) * margin
    minX -= mx; maxX += mx; minY -= my; maxY += my

    // ── Orientação dos eixos, descoberta por medição ──────────────────────
    //
    // O sinal de um ponto de fuga vindo de produto vetorial é **arbitrário**:
    // ele pode apontar para a esquerda ou para a direita conforme a reta foi
    // representada. Raciocinar sobre esses sinais já produziu imagem de cabeça
    // para baixo e depois espelhada.
    //
    // Em vez disso: mapear pontos cuja ordem na foto eu conheço, e ver para
    // onde foram. Autocorretivo nos dois eixos.
    guard let photoLeft = region.min(by: { $0.x < $1.x }),
          let photoRight = region.max(by: { $0.x < $1.x }),
          let photoTop = region.min(by: { $0.y < $1.y }),
          let photoBottom = region.max(by: { $0.y < $1.y }),
          let mLeft = apply(hMat, photoLeft), let mRight = apply(hMat, photoRight),
          let mTop = apply(hMat, photoTop), let mBottom = apply(hMat, photoBottom)
    else {
      return rotationOnly(image: image, gravity: g, region: region, margin: margin,
                          reason: "não foi possível medir a orientação dos eixos")
    }

    // O eixo x do espaço retificado cresce para a direita da foto?
    let xGrowsRight = mRight.x >= mLeft.x
    // E o y cresce para baixo? (a foto tem y para baixo)
    let yGrowsDown = mBottom.y >= mTop.y

    let leftX = xGrowsRight ? minX : maxX
    let rightX = xGrowsRight ? maxX : minX
    let topY = yGrowsDown ? minY : maxY
    let bottomY = yGrowsDown ? maxY : minY

    let corners = [CGPoint(x: leftX, y: topY), CGPoint(x: rightX, y: topY),
                   CGPoint(x: rightX, y: bottomY), CGPoint(x: leftX, y: bottomY)]
    let source = corners.compactMap { apply(m, $0) }
    guard source.count == 4 else {
      return rotationOnly(image: image, gravity: g, region: region, margin: margin)
    }
    // Fora da imagem por muito indica extrapolação, não enquadramento.
    for p in source where abs(Double(p.x)) > Double(w) * 3 || abs(Double(p.y)) > Double(h) * 3 {
      return rotationOnly(image: image, gravity: g, region: region, margin: margin)
    }

    // O quadrilátero de origem precisa ter ÁREA. Colapsado numa linha, o
    // CIPerspectiveCorrection produz lixo em vez de falhar — que foi
    // exatamente o que apareceu no diagnóstico.
    var area = 0.0
    for i in 0..<4 {
      let a = source[i], b = source[(i + 1) % 4]
      area += Double(a.x * b.y - b.x * a.y)
    }
    area = abs(area) / 2
    guard area > Double(w) * Double(h) * 0.01 else {
      return rotationOnly(image: image, gravity: g, region: region, margin: margin, reason: "quadrilátero sem área")
    }

    let flip = { (p: CGPoint) in CGPoint(x: p.x, y: h - p.y) }
    guard let filter = CIFilter(name: "CIPerspectiveCorrection") else { return nil }
    filter.setValue(image, forKey: kCIInputImageKey)
    filter.setValue(CIVector(cgPoint: flip(source[0])), forKey: "inputTopLeft")
    filter.setValue(CIVector(cgPoint: flip(source[1])), forKey: "inputTopRight")
    filter.setValue(CIVector(cgPoint: flip(source[2])), forKey: "inputBottomRight")
    filter.setValue(CIVector(cgPoint: flip(source[3])), forKey: "inputBottomLeft")
    guard let out = filter.outputImage, out.extent.width > 1, out.extent.height > 1 else {
      return rotationOnly(image: image, gravity: g, region: region, margin: margin)
    }

    return Output(image: out, fullyRectified: true, transform: hMat,
                  sourceQuad: source, verticalVP: verticalVP, fallbackReason: nil,
                  cropLeft: Double(leftX), cropRight: Double(rightX),
                  cropTop: Double(topY), cropBottom: Double(bottomY))
  }

  /// Recuo: só deixa a imagem em pé, usando a gravidade.
  ///
  /// Corrige a inclinação do aparelho, não a perspectiva. Melhor que nada, e
  /// **nunca piora** — uma rotação não pode deixar a imagem mais torta.
  private static func rotationOnly(
    image: CIImage, gravity g: DeviceAttitude.Gravity,
    region: [CGPoint], margin: Double, reason: String = "sem ponto de fuga horizontal"
  ) -> Output? {
    let h = image.extent.height
    // A gravidade vem em coordenadas de imagem (y para baixo); o CIImage tem y
    // para cima. Convertida, queremos girar até ela apontar para (0, -1).
    let gci = (x: g.x, y: -g.y)
    let angle = -Double.pi / 2 - atan2(gci.y, gci.x)
    let rot = CGAffineTransform(rotationAngle: CGFloat(angle))
    let rotated = image.transformed(by: rot)

    let flip = { (p: CGPoint) in CGPoint(x: p.x, y: h - p.y) }
    let mapped = region.map { flip($0).applying(rot) }
    var minX = mapped.map(\.x).min()!, maxX = mapped.map(\.x).max()!
    var minY = mapped.map(\.y).min()!, maxY = mapped.map(\.y).max()!
    let mx = (maxX - minX) * CGFloat(margin), my = (maxY - minY) * CGFloat(margin)
    minX -= mx; maxX += mx; minY -= my; maxY += my

    let crop = rotated.cropped(to: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY))
    guard crop.extent.width > 1, crop.extent.height > 1 else { return nil }
    return Output(image: crop, fullyRectified: false,
                  transform: [Double(rot.a), Double(rot.c), Double(rot.tx),
                              Double(rot.b), Double(rot.d), Double(rot.ty), 0, 0, 1],
                  sourceQuad: [], verticalVP: nil, fallbackReason: reason)
  }

  // MARK: - Matriz 3×3

  static func apply(_ m: [Double], _ p: CGPoint) -> CGPoint? {
    let x = Double(p.x), y = Double(p.y)
    let w = m[6] * x + m[7] * y + m[8]
    guard abs(w) > 1e-12 else { return nil }
    return CGPoint(x: (m[0] * x + m[1] * y + m[2]) / w,
                   y: (m[3] * x + m[4] * y + m[5]) / w)
  }

  static func invert(_ m: [Double]) -> [Double]? {
    let a = m[0], b = m[1], c = m[2]
    let d = m[3], e = m[4], f = m[5]
    let g = m[6], h = m[7], i = m[8]
    let det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
    guard abs(det) > 1e-12 else { return nil }
    return [(e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det,
            (f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det,
            (d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det]
  }
}
