import CoreGraphics
import CoreML
import CoreVideo
import Foundation

/// O que a coleta guarda de uma marca e de uma captura (spec 007), e como isso
/// vira uma pasta de item.
///
/// O rastro só segura referências — buffers, tensores, números — no instante
/// em que o app já os tem. Decodificar de novo, codificar e escrever acontece
/// depois, na fila da coleta: nada daqui roda antes de o resultado aparecer.
///
/// As chaves do JSON são as de `specs/007-modo-coleta/contracts/zip-format.md`,
/// o arquivo que vai dentro do zip como `FORMAT.md`.
enum CollectionTrace {

  /// Os limiares em vigor no item.
  struct Thresholds {
    /// O que decide o que existe — o da sessão.
    var confidence: Float
    var iou: Float
    /// O que decide o que aparece no ao vivo — o do estilo do overlay.
    var appearance: Float

    /// A gravação usa o menor entre `minScore` e o limiar da sessão: a lista
    /// gravada contém sempre a do app (data-model, "Política da coleta").
    func recorded(minScore: Float) -> Float { min(minScore, confidence) }
  }

  /// O próximo quadro processado, fotografado pelo laço da câmera (R37).
  /// Imagens e resultado do mesmo quadro, por construção.
  struct LiveFrame {
    var camera: CVPixelBuffer
    var square: CVPixelBuffer
    var run: InferenceEngine.RunResult
    var band: Band
    var membership: Double
    var gravity: DeviceAttitude.Gravity?
    var presentationSeconds: Double
  }

  struct Mark {
    var frame: LiveFrame
    /// A mediana da faixa no toque; `nil` com a faixa desligada.
    var displayedCount: Int?
    var frameCount: Int
    var thresholds: Thresholds
    var transform: String
    var side: Int
    var maskCoeffCount: Int
  }

  /// A releitura de uma captura (spec 006), para o registro.
  struct RereadTrace {
    var square: CVPixelBuffer
    /// O retângulo do recorte no quadrado.
    var content: CGRect
    /// O recorte sem a margem, no quadrado.
    var core: CGRect
    var membership: Double
    var run: InferenceEngine.RunResult
    /// Fileiras e deitados, em âncoras.
    var rows: [[Int]]
    var lying: [Int]
  }

  struct Capture {
    var thresholds: Thresholds
    var transform: String
    var side: Int
    var maskCoeffCount: Int
    /// O `CaptureOptions` que a captura recebeu.
    var options: [String: Any]
    var photo: CVPixelBuffer
    var photoSquare: CVPixelBuffer
    var photoRun: InferenceEngine.RunResult
    var band: Band
    var membership: Double
    var gravity: DeviceAttitude.Gravity?
    /// Já com as chaves do formato, montada onde os valores existem.
    var geometry: [String: Any]
    /// O recorte endireitado, em resolução cheia, quando houve.
    var crop: CVPixelBuffer?
    var reread: RereadTrace?
    /// O que a tela recebeu.
    var result: [String: Any]
    var timings: [String: Any]
  }

  /// Os campos que todo item tem.
  struct Header {
    var id: String
    var seq: Int
    /// Milissegundos desde o início da sessão.
    var t: Double
    /// Milissegundos desde a época.
    var at: Double
  }

  // MARK: - Decodificar de novo

  /// O tensor cru, decodificado com o limiar de gravação (R38).
  ///
  /// O NMS do `Decode` é guloso por confiança: um candidato só é suprimido por
  /// um já aceito, logo mais confiante. Os abaixo do limiar da sessão entram
  /// depois de todos os acima e não mudam nenhuma decisão sobre eles — filtrada
  /// pelo limiar da sessão, esta lista é exatamente a do app.
  static func decode(
    _ run: InferenceEngine.RunResult, threshold: Float, iou: Float, side: Int, maskCoeffCount: Int
  ) -> [Instance] {
    guard let raw = run.detections else { return run.instances }
    return Decode.instances(
      from: raw, maskCoeffCount: maskCoeffCount, confidenceThreshold: threshold,
      inputWidth: side, inputHeight: side, iouThreshold: iou)
  }

  // MARK: - Escrever

  /// Grava uma marca em `folder` — a pasta temporária do item. Devolve os
  /// bytes escritos.
  static func write(
    _ m: Mark, header: Header, quality: Double, minScore: Float, into folder: URL
  ) throws -> Int {
    let started = CFAbsoluteTimeGetCurrent()
    var bytes = 0

    // O quadrado primeiro: vem do pool do `FrameTransform`, que o ao vivo usa.
    let square = try CollectionWriter.writeJPEG(
      m.frame.square, named: "square.jpg", in: folder, quality: quality, upright: false)
    let frame = try CollectionWriter.writeJPEG(
      m.frame.camera, named: "frame.jpg", in: folder, quality: quality, upright: true)
    bytes += square.bytes + frame.bytes

    var protosFile: Any = NSNull()
    if let protos = m.frame.run.protos {
      bytes += try CollectionWriter.writeProtos(protos, named: "square.protos.f16", in: folder)
      protosFile = "square.protos.f16"
    }

    let recorded = m.thresholds.recorded(minScore: minScore)
    let side = Float(m.side)
    let detections = decode(
      m.frame.run, threshold: recorded, iou: m.thresholds.iou, side: m.side,
      maskCoeffCount: m.maskCoeffCount
    ).map { inst -> [String: Any] in
      let exists = inst.score >= m.thresholds.confidence
      let inBand = m.frame.band.contains(inst, imageSide: side, membership: m.frame.membership)
      return detection(inst, flags: [
        "exists": exists,
        "inBand": inBand,
        "shown": exists && inBand && inst.score >= m.thresholds.appearance,
        "counted": exists && inBand,
      ])
    }

    var item = common(header, kind: "mark", transform: m.transform, thresholds: m.thresholds,
                      recorded: recorded, band: m.frame.band, membership: m.frame.membership,
                      gravity: m.frame.gravity)
    item["images"] = ["square": square.dictionary, "frame": frame.dictionary]
    item["detections"] = detections
    item["protos"] = protosFile
    item["displayedCount"] = m.displayedCount.map { $0 as Any } ?? NSNull()
    item["frameCount"] = m.frameCount
    item["presentationTime"] = m.frame.presentationSeconds
    item["recordMs"] = (CFAbsoluteTimeGetCurrent() - started) * 1000
    bytes += try CollectionWriter.writeJSON(item, to: folder.appendingPathComponent("item.json"))
    return bytes
  }

  /// Grava uma captura em `folder`. Devolve os bytes escritos.
  static func write(
    _ c: Capture, header: Header, quality: Double, minScore: Float, into folder: URL
  ) throws -> Int {
    let started = CFAbsoluteTimeGetCurrent()
    var bytes = 0
    var images: [String: Any] = [:]

    // Os dois quadrados primeiro: vêm do pool do `FrameTransform` (R40).
    let photoSquare = try CollectionWriter.writeJPEG(
      c.photoSquare, named: "photo-square.jpg", in: folder, quality: quality, upright: false)
    images["photoSquare"] = photoSquare.dictionary
    bytes += photoSquare.bytes
    if let r = c.reread {
      let written = try CollectionWriter.writeJPEG(
        r.square, named: "reread-square.jpg", in: folder, quality: quality, upright: false)
      images["rereadSquare"] = written.dictionary
      bytes += written.bytes
    }
    if let crop = c.crop {
      let written = try CollectionWriter.writeJPEG(
        crop, named: "crop.jpg", in: folder, quality: quality, upright: false)
      images["crop"] = written.dictionary
      bytes += written.bytes
    }
    let photo = try CollectionWriter.writeJPEG(
      c.photo, named: "photo.jpg", in: folder, quality: quality, upright: true)
    images["photo"] = photo.dictionary
    bytes += photo.bytes

    let recorded = c.thresholds.recorded(minScore: minScore)
    let side = Float(c.side)

    // ── A leitura da foto ───────────────────────────────────────────────────
    var photoProtos: Any = NSNull()
    if let protos = c.photoRun.protos {
      bytes += try CollectionWriter.writeProtos(protos, named: "photo-square.protos.f16", in: folder)
      photoProtos = "photo-square.protos.f16"
    }
    let photoDetections = decode(
      c.photoRun, threshold: recorded, iou: c.thresholds.iou, side: c.side,
      maskCoeffCount: c.maskCoeffCount
    ).map { inst -> [String: Any] in
      let exists = inst.score >= c.thresholds.confidence
      let inBand = c.band.contains(inst, imageSide: side, membership: c.membership)
      return detection(inst, flags: ["exists": exists, "inBand": inBand, "counted": exists && inBand])
    }

    // ── A releitura ─────────────────────────────────────────────────────────
    var reread: Any = NSNull()
    if let r = c.reread {
      var rereadProtos: Any = NSNull()
      if let protos = r.run.protos {
        bytes += try CollectionWriter.writeProtos(
          protos, named: "reread-square.protos.f16", in: folder)
        rereadProtos = "reread-square.protos.f16"
      }
      let rereadDetections = decode(
        r.run, threshold: recorded, iou: c.thresholds.iou, side: c.side,
        maskCoeffCount: c.maskCoeffCount
      ).map { inst -> [String: Any] in
        let exists = inst.score >= c.thresholds.confidence
        // A mesma regra das bordas que contou (spec 006, FR-004).
        let inCore = !Reread.inside([inst], core: r.core, membership: r.membership).isEmpty
        return detection(inst, flags: ["exists": exists, "inCore": inCore, "counted": exists && inCore])
      }
      reread = [
        "content": rect(r.content),
        "core": rect(r.core),
        "membership": r.membership,
        "detections": rereadDetections,
        "protos": rereadProtos,
        "rows": r.rows,
        "lying": r.lying,
      ] as [String: Any]
    }

    var item = common(header, kind: "capture", transform: c.transform, thresholds: c.thresholds,
                      recorded: recorded, band: c.band, membership: c.membership,
                      gravity: c.gravity)
    item["options"] = c.options
    item["images"] = images
    item["photoRead"] = ["detections": photoDetections, "protos": photoProtos] as [String: Any]
    item["geometry"] = c.geometry
    item["reread"] = reread
    item["result"] = c.result
    item["timings"] = c.timings
    item["recordMs"] = (CFAbsoluteTimeGetCurrent() - started) * 1000
    bytes += try CollectionWriter.writeJSON(item, to: folder.appendingPathComponent("item.json"))
    return bytes
  }

  // MARK: - Peças do JSON

  private static func common(
    _ h: Header, kind: String, transform: String, thresholds: Thresholds, recorded: Float,
    band: Band, membership: Double, gravity: DeviceAttitude.Gravity?
  ) -> [String: Any] {
    [
      "format": 1,
      "id": h.id,
      "kind": kind,
      "seq": h.seq,
      "t": h.t,
      "at": h.at,
      "transform": transform,
      "thresholds": [
        "confidence": thresholds.confidence,
        "iou": thresholds.iou,
        "appearance": thresholds.appearance,
        "recorded": recorded,
      ] as [String: Any],
      "band": [
        "mode": band.mode.rawValue,
        "center": band.center,
        "thickness": band.thickness,
        "membership": membership,
      ] as [String: Any],
      "gravity": gravity.map { ["x": $0.x, "y": $0.y, "z": $0.z] as Any } ?? NSNull(),
    ]
  }

  /// Uma detecção gravada (data-model): âncora, confiança, caixa no quadrado,
  /// coeficientes e as marcas do que o app fez com ela.
  private static func detection(_ inst: Instance, flags: [String: Bool]) -> [String: Any] {
    var d: [String: Any] = [
      "anchor": inst.anchorIndex,
      "score": inst.score,
      "box": [inst.x, inst.y, inst.width, inst.height],
      "coef": inst.coefficients,
    ]
    for (key, value) in flags { d[key] = value }
    return d
  }

  static func rect(_ r: CGRect) -> [Double] {
    [Double(r.minX), Double(r.minY), Double(r.width), Double(r.height)]
  }

  /// Ponto homogêneo ou reta, `[x, y, w]`.
  static func homogeneous(_ h: Projective.H?) -> Any {
    guard let h else { return NSNull() }
    return [h.x, h.y, h.w]
  }
}
