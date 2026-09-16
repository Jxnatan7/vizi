import Accelerate
import CoreGraphics
import CoreML
import Foundation

/// Coeficientes × protótipos → silhuetas, compostas num bitmap único.
///
/// A conta é uma multiplicação de matrizes densa: `[N, 32] × [32, 25600]`.
/// Com N=24 são ~19,6 milhões de multiplicações por frame, e a 60 Hz isso é
/// 1,2 GFLOP/s — trabalho pequeno para o Accelerate, que usa SIMD.
///
/// Composta na resolução dos protótipos (160×160) e ampliada pelo compositor.
/// É o que o Ultralytics faz, então não há perda contra a referência — e o
/// bitmap resultante tem 102 KB em vez dos 1,6 MB da resolução do preview.
final class MaskCompose {
  private var logits: [Float] = []
  private var coefficients: [Float] = []
  private var rgba: [UInt8] = []

  /// - Parameters:
  ///   - instances: já filtradas pelo que vai ser desenhado
  ///   - protos: `[1, 32, 160, 160]`
  ///   - imageSide: lado do espaço do modelo (640), para mapear as caixas
  func compose(
    instances: [Instance],
    protos: MLMultiArray,
    imageSide: Int,
    colorFor: (Instance) -> (UInt8, UInt8, UInt8),
    opacity: Double
  ) -> CGImage? {
    let shape = protos.shape.map { $0.intValue }
    guard shape.count == 4, !instances.isEmpty else { return nil }

    let channels = shape[1]
    let height = shape[2]
    let width = shape[3]
    let pixels = height * width
    let count = instances.count

    // O GEMM exige memória contígua. Se algum dia o Core ML devolver um
    // tensor com passos irregulares, é melhor não desenhar do que desenhar
    // lixo silenciosamente.
    let strides = protos.strides.map { $0.intValue }
    guard strides.last == 1, strides[1] == pixels else { return nil }

    if coefficients.count != count * channels {
      coefficients = [Float](repeating: 0, count: count * channels)
    }
    if logits.count != count * pixels {
      logits = [Float](repeating: 0, count: count * pixels)
    }
    if rgba.count != pixels * 4 {
      rgba = [UInt8](repeating: 0, count: pixels * 4)
    }

    for (i, inst) in instances.enumerated() {
      guard inst.coefficients.count == channels else { return nil }
      for c in 0..<channels { coefficients[i * channels + c] = inst.coefficients[c] }
    }
    for i in rgba.indices { rgba[i] = 0 }

    var image: CGImage?

    protos.withUnsafeMutableBufferPointer(ofType: Float32.self) { buf, _ in
      guard let protoPtr = buf.baseAddress else { return }

      coefficients.withUnsafeBufferPointer { coeffPtr in
        logits.withUnsafeMutableBufferPointer { outPtr in
          cblas_sgemm(
            CblasRowMajor, CblasNoTrans, CblasNoTrans,
            Int32(count), Int32(pixels), Int32(channels),
            1.0,
            coeffPtr.baseAddress, Int32(channels),
            protoPtr, Int32(pixels),
            0.0,
            outPtr.baseAddress, Int32(pixels))
        }
      }

      // Maior confiança por último: quem escreve depois vence o pixel
      // disputado. Determinístico porque a confiança é estável entre frames,
      // então a fronteira entre dois objetos não cintila (R13).
      let order = instances.indices.sorted { instances[$0].score < instances[$1].score }
      let scale = Float(width) / Float(imageSide)
      let alpha = UInt8(max(0, min(1, opacity)) * 255)

      for i in order {
        let inst = instances[i]
        let (r, g, b) = colorFor(inst)

        // Recorte à caixa (FR-005): fora dela a resposta do protótipo é ruído.
        let x0 = max(0, Int((inst.x) * scale))
        let y0 = max(0, Int((inst.y) * scale))
        let x1 = min(width, Int(((inst.x + inst.width) * scale).rounded(.up)))
        let y1 = min(height, Int(((inst.y + inst.height) * scale).rounded(.up)))
        guard x1 > x0, y1 > y0 else { continue }

        let base = i * pixels
        for y in y0..<y1 {
          let row = y * width
          for x in x0..<x1 {
            // sigmoid(v) > 0.5  ⟺  v > 0. Evita 600 mil exponenciais por frame.
            guard logits[base + row + x] > 0 else { continue }
            let p = (row + x) * 4
            rgba[p] = r
            rgba[p + 1] = g
            rgba[p + 2] = b
            rgba[p + 3] = alpha
          }
        }
      }

      guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return }
      image = CGImage(
        width: width, height: height,
        bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
        provider: provider, decode: nil, shouldInterpolate: true,
        intent: .defaultIntent)
    }

    return image
  }
}
