import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import UIKit

/// Desenha o que o algoritmo inferiu, sobre a foto **não retificada**.
///
/// Existe porque geometria projetiva falha de formas que parecem iguais na
/// saída: horizonte torto, ponto de fuga errado, cantos trocados e recorte mau
/// posicionado produzem todos "a imagem ficou estranha". Ver as etapas
/// intermediárias transforma cinco hipóteses num fato.
enum Diagnostics {

  static func draw(
    portrait image: CIImage,
    context: CIContext,
    horizon: Projective.H?,
    verticalVP: Projective.H?,
    horizontalVP: Projective.H?,
    cropQuad: [CGPoint],
    scores: [Double]
  ) -> CVPixelBuffer? {
    let w = Int(image.extent.width.rounded()), h = Int(image.extent.height.rounded())
    guard w > 1, h > 1 else { return nil }

    var buffer: CVPixelBuffer?
    let attrs: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
    guard CVPixelBufferCreate(kCFAllocatorDefault, w, h, kCVPixelFormatType_32BGRA,
                              attrs as CFDictionary, &buffer) == kCVReturnSuccess,
          let buffer else { return nil }

    let anchored = image.transformed(by: CGAffineTransform(
      translationX: -image.extent.minX, y: -image.extent.minY))
    context.render(anchored, to: buffer)

    CVPixelBufferLockBaseAddress(buffer, [])
    defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
    guard let base = CVPixelBufferGetBaseAddress(buffer),
          let ctx = CGContext(
            data: base, width: w, height: h, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
              | CGBitmapInfo.byteOrder32Little.rawValue)
    else { return nil }

    // O contexto tem origem embaixo; a geometria está em coordenadas de imagem
    // com y para baixo. Inverter aqui uma vez evita inverter em cada desenho.
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: 1, y: -1)
    ctx.setLineWidth(max(2, CGFloat(w) / 400))

    let W = Double(w), H = Double(h)

    // Horizonte — amarelo. Tudo que é horizontal no mundo converge sobre ele.
    if let l = horizon {
      ctx.setStrokeColor(UIColor.yellow.cgColor)
      if let (a, b) = clip(line: l, width: W, height: H) {
        ctx.move(to: a); ctx.addLine(to: b); ctx.strokePath()
      }
    }

    // Raios para o ponto de fuga vertical — ciano. Devem seguir as lombadas.
    if let vp = verticalVP {
      ctx.setStrokeColor(UIColor.cyan.cgColor)
      for k in 1...6 {
        let x = W * Double(k) / 7
        drawRay(ctx, from: CGPoint(x: x, y: H * 0.9), toward: vp, width: W, height: H)
      }
    }

    // Raios para o ponto de fuga horizontal — magenta. Devem seguir as
    // prateleiras. Se não seguirem, o azimute está errado.
    if let vp = horizontalVP {
      ctx.setStrokeColor(UIColor.magenta.cgColor)
      for k in 1...6 {
        let y = H * Double(k) / 7
        drawRay(ctx, from: CGPoint(x: W * 0.1, y: y), toward: vp, width: W, height: H)
      }
    }

    // Recorte — verde. É o que vira o resultado.
    if cropQuad.count == 4 {
      ctx.setStrokeColor(UIColor.green.cgColor)
      ctx.setLineWidth(max(3, CGFloat(w) / 250))
      ctx.move(to: cropQuad[0])
      for p in cropQuad.dropFirst() { ctx.addLine(to: p) }
      ctx.closePath(); ctx.strokePath()
    }

    // Curva de pontuação do azimute, no rodapé. Um pico nítido significa que a
    // imagem tem estrutura horizontal dominante; um platô significa que a
    // escolha foi arbitrária.
    if scores.count > 1, let peak = scores.max(), peak > 0 {
      ctx.setStrokeColor(UIColor.white.cgColor)
      ctx.setLineWidth(max(1, CGFloat(w) / 600))
      let bandH = H * 0.12, baseY = H * 0.98
      for (i, s) in scores.enumerated() {
        let x = W * Double(i) / Double(scores.count - 1)
        let y = baseY - bandH * (s / peak)
        if i == 0 { ctx.move(to: CGPoint(x: x, y: y)) } else { ctx.addLine(to: CGPoint(x: x, y: y)) }
      }
      ctx.strokePath()
    }

    return buffer
  }

  // MARK: - Auxiliares

  private static func drawRay(_ ctx: CGContext, from p: CGPoint, toward vp: Projective.H,
                              width: Double, height: Double) {
    let dx: Double, dy: Double
    if abs(vp.w) > 1e-9 {
      dx = vp.x / vp.w - Double(p.x); dy = vp.y / vp.w - Double(p.y)
    } else {
      dx = vp.x; dy = vp.y
    }
    let n = hypot(dx, dy)
    guard n > 1e-9 else { return }
    let len = max(width, height) * 1.5
    ctx.move(to: CGPoint(x: Double(p.x) - dx / n * len, y: Double(p.y) - dy / n * len))
    ctx.addLine(to: CGPoint(x: Double(p.x) + dx / n * len, y: Double(p.y) + dy / n * len))
    ctx.strokePath()
  }

  /// Recorta uma reta homogênea às bordas da imagem.
  private static func clip(line l: Projective.H, width w: Double, height h: Double)
    -> (CGPoint, CGPoint)? {
    var pts: [CGPoint] = []
    // Interseções com x=0, x=w, y=0, y=h.
    if abs(l.y) > 1e-12 {
      for x in [0.0, w] {
        let y = -(l.x * x + l.w) / l.y
        if y >= -1, y <= h + 1 { pts.append(CGPoint(x: x, y: y)) }
      }
    }
    if abs(l.x) > 1e-12 {
      for y in [0.0, h] {
        let x = -(l.y * y + l.w) / l.x
        if x >= -1, x <= w + 1 { pts.append(CGPoint(x: x, y: y)) }
      }
    }
    guard pts.count >= 2 else { return nil }
    return (pts[0], pts[1])
  }
}
