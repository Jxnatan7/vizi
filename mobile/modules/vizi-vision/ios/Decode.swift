import CoreML
import Foundation

struct Instance {
  var classIndex: Int
  var score: Float
  var x: Float       // canto superior esquerdo, em pixels da entrada
  var y: Float
  var width: Float
  var height: Float
}

/// Saída crua do YOLO → instâncias. O que sai daqui é a única coisa que
/// atravessa a fronteira para o JavaScript (princípio II da constituição).
enum Decode {
  /// - Parameters:
  ///   - detections: `[1, 4 + nc + maskCoeffs, anchors]`
  ///   - maskCoeffCount: derivado da forma dos protótipos, não fixado em código
  static func instances(
    from detections: MLMultiArray,
    maskCoeffCount: Int,
    confidenceThreshold: Float,
    iouThreshold: Float = 0.45
  ) -> [Instance] {
    let shape = detections.shape.map { $0.intValue }
    guard shape.count == 3 else { return [] }

    let rows = shape[1]
    let anchors = shape[2]
    let classCount = rows - 4 - maskCoeffCount
    guard classCount > 0 else { return [] }

    var kept: [Instance] = []
    kept.reserveCapacity(256)

    detections.withUnsafeMutableBufferPointer(ofType: Float32.self) { buf, _ in
      let p = buf.baseAddress!

      // Filtro por confiança antes de qualquer ordenação: de 8400 candidatos
      // sobram tipicamente algumas dezenas, e só então vale ordenar.
      for a in 0..<anchors {
        var best = 0
        var bestScore = p[4 * anchors + a]
        if classCount > 1 {
          for c in 1..<classCount {
            let s = p[(4 + c) * anchors + a]
            if s > bestScore { bestScore = s; best = c }
          }
        }
        guard bestScore >= confidenceThreshold else { continue }

        let cx = p[a], cy = p[anchors + a]
        let w = p[2 * anchors + a], h = p[3 * anchors + a]
        kept.append(Instance(
          classIndex: best, score: bestScore,
          x: cx - w / 2, y: cy - h / 2, width: w, height: h))
      }
    }

    return nms(kept, iouThreshold: iouThreshold)
  }

  private static func nms(_ boxes: [Instance], iouThreshold: Float) -> [Instance] {
    let sorted = boxes.sorted { $0.score > $1.score }
    var result: [Instance] = []
    result.reserveCapacity(sorted.count)

    for candidate in sorted {
      var overlaps = false
      for kept in result where kept.classIndex == candidate.classIndex {
        if iou(kept, candidate) > iouThreshold { overlaps = true; break }
      }
      if !overlaps { result.append(candidate) }
    }
    return result
  }

  private static func iou(_ a: Instance, _ b: Instance) -> Float {
    let x1 = max(a.x, b.x), y1 = max(a.y, b.y)
    let x2 = min(a.x + a.width, b.x + b.width)
    let y2 = min(a.y + a.height, b.y + b.height)
    let inter = max(0, x2 - x1) * max(0, y2 - y1)
    guard inter > 0 else { return 0 }
    let union = a.width * a.height + b.width * b.height - inter
    return union > 0 ? inter / union : 0
  }
}
