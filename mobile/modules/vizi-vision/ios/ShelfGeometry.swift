import CoreGraphics
import CoreML
import Foundation

/// Estima a geometria da estante a partir das **máscaras**.
///
/// Caixa alinhada aos eixos é idêntica para um livro reto e um inclinado — a
/// inclinação está na silhueta. É a segmentação pagando por algo que não foi
/// pedido a ela.
///
/// **A reta dos topos não é usada de propósito.** Livros têm alturas diferentes
/// por natureza, e ajustar uma reta a topos que legitimamente variam inventa
/// uma borda que não existe. As bases estão todas na mesma prateleira, e a
/// direção de cada lombada vem do eixo principal da sua máscara.
enum ShelfGeometry {

  struct Quad {
    var topLeft: CGPoint
    var topRight: CGPoint
    var bottomLeft: CGPoint
    var bottomRight: CGPoint
  }

  struct Estimate {
    var quad: Quad?
    var confidence: Double
    /// Texto para a tela, não para o log: "Poucos livros para estimar a
    /// perspectiva" diz o que fazer diferente; "confiança 0.31" não diz nada.
    var declineReason: String?
  }

  /// Uma lombada: onde está, para onde aponta, e onde começa e termina.
  private struct Spine {
    var center: CGPoint
    /// Vetor unitário do eixo principal, sempre apontando para cima.
    var axis: CGVector
    var base: CGPoint
    var top: CGPoint
    var halfWidth: Double
  }

  static func estimate(
    instances: [Instance],
    protos: MLMultiArray,
    imageSide: Int,
    minInstances: Int,
    minConfidence: Double
  ) -> Estimate {
    guard instances.count >= minInstances else {
      return Estimate(quad: nil, confidence: 0,
                      declineReason: "Poucos livros para estimar a perspectiva (\(instances.count))")
    }

    let spines = instances.compactMap { spine(for: $0, protos: protos, imageSide: imageSide) }
    guard spines.count >= minInstances else {
      return Estimate(quad: nil, confidence: 0,
                      declineReason: "Não foi possível medir a inclinação das lombadas")
    }

    // Reta das bases: y = a·x + b, por mínimos quadrados.
    let bases = spines.map { $0.base }
    guard let (slope, intercept, residual) = fitLine(bases) else {
      return Estimate(quad: nil, confidence: 0,
                      declineReason: "As bases dos livros não formam uma linha")
    }

    // Consistência das lombadas: se apontam para direções muito diferentes, ou
    // a cena não é uma estante, ou a segmentação está ruim.
    let angles = spines.map { atan2($0.axis.dy, $0.axis.dx) }
    let meanAngle = angles.reduce(0, +) / Double(angles.count)
    let angleSpread = angles.map { abs($0 - meanAngle) }.max() ?? .pi

    // Confiança: três sinais, todos entre 0 e 1.
    let countScore = min(1.0, Double(spines.count) / 12.0)
    let lineScore = max(0, 1 - residual / (Double(imageSide) * 0.02))
    let spreadScore = max(0, 1 - angleSpread / 0.5)   // ~29° de dispersão zera
    let confidence = countScore * 0.2 + lineScore * 0.4 + spreadScore * 0.4

    guard confidence >= minConfidence else {
      return Estimate(quad: nil, confidence: confidence,
                      declineReason: "Geometria pouco confiável — tente de frente para a estante")
    }

    // O quadrilátero: bases na reta ajustada, topos deslocados pela altura de
    // cada lombada nas pontas.
    let sorted = spines.sorted { $0.center.x < $1.center.x }
    guard let left = sorted.first, let right = sorted.last else {
      return Estimate(quad: nil, confidence: confidence, declineReason: "Sem extremos")
    }

    let onLine = { (x: Double) in CGPoint(x: x, y: slope * x + intercept) }
    let leftBase = onLine(Double(left.center.x) - left.halfWidth)
    let rightBase = onLine(Double(right.center.x) + right.halfWidth)

    let leftHeight = hypot(Double(left.top.x - left.base.x), Double(left.top.y - left.base.y))
    let rightHeight = hypot(Double(right.top.x - right.base.x), Double(right.top.y - right.base.y))

    let quad = Quad(
      topLeft: CGPoint(x: leftBase.x + left.axis.dx * leftHeight,
                       y: leftBase.y + left.axis.dy * leftHeight),
      topRight: CGPoint(x: rightBase.x + right.axis.dx * rightHeight,
                        y: rightBase.y + right.axis.dy * rightHeight),
      bottomLeft: leftBase,
      bottomRight: rightBase)

    guard isSane(quad, imageSide: imageSide) else {
      return Estimate(quad: nil, confidence: confidence,
                      declineReason: "O quadrilátero estimado não faz sentido")
    }

    return Estimate(quad: quad, confidence: confidence, declineReason: nil)
  }

  // MARK: - PCA de uma máscara

  private static func spine(for inst: Instance, protos: MLMultiArray, imageSide: Int) -> Spine? {
    let shape = protos.shape.map { $0.intValue }
    guard shape.count == 4, inst.coefficients.count == shape[1] else { return nil }

    let channels = shape[1], height = shape[2], width = shape[3]
    let pixels = height * width
    let scale = Float(width) / Float(imageSide)

    let x0 = max(0, Int(inst.x * scale)), y0 = max(0, Int(inst.y * scale))
    let x1 = min(width, Int(((inst.x + inst.width) * scale).rounded(.up)))
    let y1 = min(height, Int(((inst.y + inst.height) * scale).rounded(.up)))
    guard x1 > x0, y1 > y0 else { return nil }

    var sumX = 0.0, sumY = 0.0, n = 0.0
    var points: [(Double, Double)] = []
    points.reserveCapacity((x1 - x0) * (y1 - y0) / 2)

    protos.withUnsafeMutableBufferPointer(ofType: Float32.self) { buf, _ in
      guard let p = buf.baseAddress else { return }
      for y in y0..<y1 {
        for x in x0..<x1 {
          var v: Float = 0
          for c in 0..<channels { v += inst.coefficients[c] * p[c * pixels + y * width + x] }
          // sigmoid(v) > 0.5 ⟺ v > 0
          guard v > 0 else { continue }
          let px = Double(x), py = Double(y)
          points.append((px, py)); sumX += px; sumY += py; n += 1
        }
      }
    }
    guard n >= 20 else { return nil }

    let mx = sumX / n, my = sumY / n
    var cxx = 0.0, cxy = 0.0, cyy = 0.0
    for (px, py) in points {
      let dx = px - mx, dy = py - my
      cxx += dx * dx; cxy += dx * dy; cyy += dy * dy
    }
    cxx /= n; cxy /= n; cyy /= n

    // Autovetor dominante de uma matriz simétrica 2×2, em forma fechada.
    let trace = cxx + cyy
    let det = cxx * cyy - cxy * cxy
    let disc = max(0, trace * trace / 4 - det)
    let lambda = trace / 2 + sqrt(disc)
    var ax = cxy, ay = lambda - cxx
    if abs(ax) < 1e-9 && abs(ay) < 1e-9 { ax = 1; ay = 0 }
    let norm = hypot(ax, ay)
    ax /= norm; ay /= norm
    // No espaço da imagem o y cresce para baixo: o eixo aponta para cima.
    if ay > 0 { ax = -ax; ay = -ay }

    // Extremos ao longo do eixo, convertidos de volta ao espaço da imagem.
    var minT = Double.infinity, maxT = -Double.infinity
    for (px, py) in points {
      let t = (px - mx) * ax + (py - my) * ay
      minT = min(minT, t); maxT = max(maxT, t)
    }
    let inv = Double(imageSide) / Double(width)
    let center = CGPoint(x: mx * inv, y: my * inv)
    let top = CGPoint(x: (mx + ax * maxT) * inv, y: (my + ay * maxT) * inv)
    let base = CGPoint(x: (mx + ax * minT) * inv, y: (my + ay * minT) * inv)

    return Spine(center: center, axis: CGVector(dx: ax, dy: ay),
                 base: base, top: top, halfWidth: Double(inst.width) / 2)
  }

  // MARK: - Auxiliares

  /// Mínimos quadrados, devolvendo também o resíduo médio.
  private static func fitLine(_ points: [CGPoint]) -> (Double, Double, Double)? {
    let n = Double(points.count)
    guard n >= 2 else { return nil }
    let sx = points.reduce(0.0) { $0 + Double($1.x) }
    let sy = points.reduce(0.0) { $0 + Double($1.y) }
    let sxx = points.reduce(0.0) { $0 + Double($1.x) * Double($1.x) }
    let sxy = points.reduce(0.0) { $0 + Double($1.x) * Double($1.y) }
    let denom = n * sxx - sx * sx
    guard abs(denom) > 1e-6 else { return nil }
    let a = (n * sxy - sx * sy) / denom
    let b = (sy - a * sx) / n
    let residual = points.reduce(0.0) {
      $0 + abs(Double($1.y) - (a * Double($1.x) + b))
    } / n
    return (a, b, residual)
  }

  /// Convexo, sem auto-cruzamento, e com proporção plausível.
  private static func isSane(_ q: Quad, imageSide: Int) -> Bool {
    let side = Double(imageSide)
    let pts = [q.topLeft, q.topRight, q.bottomRight, q.bottomLeft]
    for p in pts where !p.x.isFinite || !p.y.isFinite { return false }
    // Fora da imagem por mais de uma imagem inteira é sinal de extrapolação.
    for p in pts where abs(Double(p.x)) > side * 2 || abs(Double(p.y)) > side * 2 { return false }

    let w = hypot(Double(q.bottomRight.x - q.bottomLeft.x), Double(q.bottomRight.y - q.bottomLeft.y))
    let h = hypot(Double(q.topLeft.x - q.bottomLeft.x), Double(q.topLeft.y - q.bottomLeft.y))
    guard w > side * 0.05, h > side * 0.02 else { return false }

    // Convexidade: os quatro produtos vetoriais têm de ter o mesmo sinal.
    var sign = 0.0
    for i in 0..<4 {
      let a = pts[i], b = pts[(i + 1) % 4], c = pts[(i + 2) % 4]
      let cross = Double((b.x - a.x) * (c.y - b.y) - (b.y - a.y) * (c.x - b.x))
      if sign == 0 { sign = cross } else if cross * sign < 0 { return false }
    }
    return true
  }
}
