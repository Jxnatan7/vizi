import Accelerate
import CoreImage
import CoreVideo
import Foundation

/// Encontra o azimute do plano — o único número que a gravidade não dá.
///
/// Para um plano vertical, a gravidade fixa tudo menos o quanto ele está virado
/// em relação à câmera. E como o ponto de fuga horizontal **tem que estar sobre
/// o horizonte**, a busca é unidimensional: varrer direções e escolher a que
/// melhor concorda com as bordas da imagem.
///
/// Usa a foto inteira — prateleiras, móvel, parede, rodapé — em vez das
/// máscaras de vinte livros. É o que torna a estimativa independente de os
/// objetos estarem arrumados.
enum AzimuthSearch {

  struct Result {
    /// Ponto de fuga horizontal, homogêneo, no espaço retrato isotrópico.
    var vanishingPoint: Projective.H
    /// 0 a 1. Proeminência do pico sobre o restante da varredura.
    var confidence: Double
    /// A varredura inteira, normalizada. Um pico nítido significa estrutura
    /// horizontal dominante; um platô significa escolha arbitrária.
    var scores: [Double]
  }

  /// Trabalha numa versão reduzida, e **isotrópica**: no espaço canônico o
  /// esticamento 4:3→1:1 distorce ângulos, e a direção dos gradientes é
  /// exatamente o que está sendo medido.
  private static let workingSide = 192

  static func search(
    portrait image: CIImage,
    gravity g: DeviceAttitude.Gravity,
    fieldOfViewDegrees fov: Double,
    context: CIContext
  ) -> Result? {
    let w = image.extent.width, h = image.extent.height
    guard w > 1, h > 1 else { return nil }

    let scale = CGFloat(workingSide) / max(w, h)
    let small = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    let sw = Int(small.extent.width.rounded()), sh = Int(small.extent.height.rounded())
    guard sw > 8, sh > 8 else { return nil }

    guard let gray = luminance(small, width: sw, height: sh, context: context) else { return nil }

    // Sobel. Guardamos módulo e direção do gradiente por pixel.
    var mag = [Double](repeating: 0, count: sw * sh)
    var dirX = [Double](repeating: 0, count: sw * sh)
    var dirY = [Double](repeating: 0, count: sw * sh)
    var maxMag = 0.0

    for y in 1..<(sh - 1) {
      for x in 1..<(sw - 1) {
        let i = y * sw + x
        let gx = Double(gray[i - sw + 1]) + 2 * Double(gray[i + 1]) + Double(gray[i + sw + 1])
               - Double(gray[i - sw - 1]) - 2 * Double(gray[i - 1]) - Double(gray[i + sw - 1])
        let gy = Double(gray[i + sw - 1]) + 2 * Double(gray[i + sw]) + Double(gray[i + sw + 1])
               - Double(gray[i - sw - 1]) - 2 * Double(gray[i - sw]) - Double(gray[i - sw + 1])
        let m = hypot(gx, gy)
        mag[i] = m
        if m > 1e-6 { dirX[i] = gx / m; dirY[i] = gy / m }
        maxMag = max(maxMag, m)
      }
    }
    guard maxMag > 1e-6 else { return nil }
    let threshold = maxMag * 0.15

    // Base ortonormal do plano horizontal, perpendicular à gravidade.
    let gv = normalize((g.x, g.y, g.z))
    var e1 = cross(gv, (0, 0, 1))
    if norm(e1) < 1e-4 { e1 = cross(gv, (0, 1, 0)) }
    e1 = normalize(e1)
    let e2 = normalize(cross(gv, e1))

    // Focal isotrópica, em pixels da imagem reduzida.
    let half = fov * .pi / 360
    let f = half > 1e-6 ? (Double(max(sw, sh)) / 2) / tan(half) : Double(max(sw, sh))
    let cx = Double(sw) / 2, cy = Double(sh) / 2

    var best: (score: Double, vp: Projective.H)?
    var scores: [Double] = []
    let samples = 90

    for k in 0..<samples {
      let theta = Double(k) * .pi / Double(samples)
      // Direção horizontal no plano, em coordenadas da câmera.
      let d = (cos(theta) * e1.0 + sin(theta) * e2.0,
               cos(theta) * e1.1 + sin(theta) * e2.1,
               cos(theta) * e1.2 + sin(theta) * e2.2)
      // Projeção: ponto de fuga dessa direção.
      let vp: Projective.H = (cx * d.2 + f * d.0, cy * d.2 + f * d.1, d.2)

      var score = 0.0
      // Amostragem esparsa: a 192px, olhar um pixel em cada quatro basta e
      // deixa a varredura de 90 candidatos barata.
      var y = 1
      while y < sh - 1 {
        var x = 1
        while x < sw - 1 {
          let i = y * sw + x
          if mag[i] >= threshold {
            // Direção do pixel para o ponto de fuga.
            let ux = vp.x - vp.w * Double(x)
            let uy = vp.y - vp.w * Double(y)
            let un = hypot(ux, uy)
            if un > 1e-9 {
              // A borda aponta para o ponto de fuga quando o GRADIENTE é
              // perpendicular a essa direção.
              let align = abs(dirX[i] * ux / un + dirY[i] * uy / un)
              if align < 0.25 { score += mag[i] * (1 - align / 0.25) }
            }
          }
          x += 2
        }
        y += 2
      }
      scores.append(score)
      if best == nil || score > best!.score { best = (score, vp) }
    }

    guard let winner = best, winner.score > 0 else { return nil }

    // Confiança pela proeminência do pico: um máximo que mal se destaca da
    // mediana significa que a imagem não tem estrutura horizontal dominante.
    let sorted = scores.sorted()
    let median = sorted[sorted.count / 2]
    let prominence = median > 1e-9 ? (winner.score - median) / winner.score : 0

    // Converter de volta à escala original.
    let inv = 1 / Double(scale)
    let vp = winner.vp
    let full: Projective.H = (vp.x * inv, vp.y * inv, vp.w)

    let peak = scores.max() ?? 1
    return Result(vanishingPoint: full,
                  confidence: min(1, max(0, prominence)),
                  scores: peak > 0 ? scores.map { $0 / peak } : scores)
  }

  // MARK: - Auxiliares

  private static func luminance(_ image: CIImage, width: Int, height: Int,
                                context: CIContext) -> [UInt8]? {
    var buffer: CVPixelBuffer?
    let attrs: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
    guard CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                              kCVPixelFormatType_32BGRA, attrs as CFDictionary,
                              &buffer) == kCVReturnSuccess, let buffer else { return nil }

    let anchored = image.transformed(by: CGAffineTransform(
      translationX: -image.extent.minX, y: -image.extent.minY))
    context.render(anchored, to: buffer)

    CVPixelBufferLockBaseAddress(buffer, .readOnly)
    defer { CVPixelBufferUnlockBaseAddress(buffer, .readOnly) }
    guard let base = CVPixelBufferGetBaseAddress(buffer) else { return nil }
    let stride = CVPixelBufferGetBytesPerRow(buffer)
    let p = base.assumingMemoryBound(to: UInt8.self)

    var out = [UInt8](repeating: 0, count: width * height)
    for y in 0..<height {
      for x in 0..<width {
        let o = y * stride + x * 4
        // BGRA → luminância aproximada.
        out[y * width + x] = UInt8((Int(p[o + 2]) * 77 + Int(p[o + 1]) * 150 + Int(p[o]) * 29) >> 8)
      }
    }
    return out
  }

  private static func cross(_ a: (Double, Double, Double), _ b: (Double, Double, Double))
    -> (Double, Double, Double) {
    (a.1 * b.2 - a.2 * b.1, a.2 * b.0 - a.0 * b.2, a.0 * b.1 - a.1 * b.0)
  }

  private static func norm(_ v: (Double, Double, Double)) -> Double {
    sqrt(v.0 * v.0 + v.1 * v.1 + v.2 * v.2)
  }

  private static func normalize(_ v: (Double, Double, Double)) -> (Double, Double, Double) {
    let n = norm(v)
    return n > 1e-9 ? (v.0 / n, v.1 / n, v.2 / n) : (1, 0, 0)
  }
}
