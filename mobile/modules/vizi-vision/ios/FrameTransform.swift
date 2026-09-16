import CoreImage
import CoreVideo
import Foundation
import Metal

/// Converte o frame da câmera no quadrado que o modelo espera.
///
/// As três opções existem porque a opção de redimensionamento usada no Roboblow
/// ao montar o dataset ainda não foi confirmada. A comparação no aparelho é o
/// método — ver spec, US3.
enum TransformMode: String {
  /// 4:3 → 1:1 esticando. Padrão do Roboflow ("Stretch to").
  case stretch
  /// Recorta o quadrado central. Perde as laterais da cena.
  case centerCrop
  /// Preserva a proporção e preenche com cinza, como o letterbox do YOLO.
  case letterbox
}

final class FrameTransform {
  private let context: CIContext
  private var pool: CVPixelBufferPool?
  private var poolSide = 0

  /// O cinza 114 é o que o Ultralytics usa no letterbox. Usar preto mudaria a
  /// estatística das bordas em relação ao treino.
  private static let letterboxGray = CIColor(red: 114.0 / 255, green: 114.0 / 255, blue: 114.0 / 255)

  init() {
    if let device = MTLCreateSystemDefaultDevice() {
      context = CIContext(mtlDevice: device, options: [.cacheIntermediates: false])
    } else {
      context = CIContext(options: [.cacheIntermediates: false])
    }
  }

  /// Buffers vêm de um pool reutilizado: alocar 1,6 MB por frame a 60 Hz seria
  /// ~100 MB/s de lixo.
  private func ensurePool(side: Int) -> CVPixelBufferPool? {
    if let pool, poolSide == side { return pool }

    let attrs: [String: Any] = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferWidthKey as String: side,
      kCVPixelBufferHeightKey as String: side,
      kCVPixelBufferIOSurfacePropertiesKey as String: [:],
    ]
    // Teto explícito: o preview e a inferência seguram um buffer cada, e o
    // pendente da fila segura um terceiro. Sem folga, a captura travaria
    // esperando buffer livre (R8).
    let poolAttrs: [String: Any] = [kCVPixelBufferPoolMinimumBufferCountKey as String: 6]

    var created: CVPixelBufferPool?
    guard CVPixelBufferPoolCreate(
      kCFAllocatorDefault, poolAttrs as CFDictionary, attrs as CFDictionary, &created
    ) == kCVReturnSuccess else { return nil }

    pool = created
    poolSide = side
    return created
  }

  func transform(_ source: CVPixelBuffer, mode: TransformMode, side: Int) -> CVPixelBuffer? {
    guard let pool = ensurePool(side: side) else { return nil }

    var destination: CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pool, &destination)
            == kCVReturnSuccess,
          let destination else { return nil }

    let srcW = CGFloat(CVPixelBufferGetWidth(source))
    let srcH = CGFloat(CVPixelBufferGetHeight(source))
    let target = CGFloat(side)
    var image = CIImage(cvPixelBuffer: source)

    switch mode {
    case .stretch:
      image = image.transformed(by: CGAffineTransform(scaleX: target / srcW, y: target / srcH))

    case .centerCrop:
      let square = min(srcW, srcH)
      let crop = CGRect(x: (srcW - square) / 2, y: (srcH - square) / 2, width: square, height: square)
      image = image.cropped(to: crop)
        .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
        .transformed(by: CGAffineTransform(scaleX: target / square, y: target / square))

    case .letterbox:
      let scale = min(target / srcW, target / srcH)
      image = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        .transformed(by: CGAffineTransform(
          translationX: (target - srcW * scale) / 2,
          y: (target - srcH * scale) / 2))
      let background = CIImage(color: Self.letterboxGray)
        .cropped(to: CGRect(x: 0, y: 0, width: target, height: target))
      image = image.composited(over: background)
    }

    context.render(image, to: destination)
    return destination
  }
}
