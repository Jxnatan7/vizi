import CoreImage
import ExpoModulesCore
import Foundation
import UIKit

/// Política da medição. Os valores vêm do TypeScript — princípio IV.
///
/// Os defaults existem só porque o protocolo `Record` exige um `init()`; o
/// TypeScript sempre envia todos os campos. Mantidos em sincronia com
/// `src/bench/runBenchmark.ts` para que uma divergência não passe despercebida
/// se algum dia um campo deixar de ser enviado.
struct BenchmarkOptions: Record {
  @Field var repetitions: Int = 100
  @Field var warmupDiscard: Int = 25
  @Field var confidenceThreshold: Double = 0.25
  @Field var iouThreshold: Double = 0.7
}

/// Política da sessão de câmera. Também vem do TypeScript — princípio IV.
/// Aparência do overlay. O nativo executa; o TypeScript decide (FR-010).
/// Política da captura. Vem do TypeScript — princípio IV.
struct CaptureOptions: Record {
  @Field var cropMargin: Double = 0.05
  @Field var minInstancesForGeometry: Int = 5
  @Field var minGeometryConfidence: Double = 0.6
  @Field var transitionMs: Int = 600
}

struct OverlayStyleRecord: Record {
  @Field var showBoxes: Bool = true
  @Field var showMasks: Bool = true
  @Field var boxWidth: Double = 3
  @Field var maskOpacity: Double = 0.45
  @Field var minConfidence: Double = 0.3
  /// Cores em "#RRGGBB".
  @Field var palette: [String] = []
}

struct SessionOptions: Record {
  @Field var sampleIntervalMs: Int = 500
  @Field var transform: String = "stretch"
  @Field var confidenceThreshold: Double = 0.25
  @Field var iouThreshold: Double = 0.7
}

public class ViziVisionModule: Module {
  private let engine = InferenceEngine()
  private let coordinator = SessionCoordinator()
  /// Usado só na captura, uma vez. Não está no caminho quente.
  private let ciContext = CIContext(options: [.cacheIntermediates: false])

  public func definition() -> ModuleDefinition {
    Name("ViziVision")

    // Emitido a ~2 Hz. Um evento por frame seriam 60 travessias por segundo e
    // 60 re-renders — princípios II e III violados de uma vez.
    Events("onTelemetry")

    Function("probe") { () -> [String: Any] in
      let info = ProcessInfo.processInfo
      return [
        "module": "ViziVision",
        "os": info.operatingSystemVersionString,
        "processorCount": info.processorCount,
        "physicalMemoryMB": Int(info.physicalMemory / 1_048_576),
        "lowPowerMode": info.isLowPowerModeEnabled,
      ]
    }

    // AsyncFunction roda fora da thread de interface — princípio I. Mesmo sem
    // loop de desenho neste marco, o precedente contrário custaria caro depois.
    AsyncFunction("loadModel") { () -> [String: Any] in
      try self.engine.load()
      return [
        "identifier": "vizi-seg",
        "inputWidth": self.engine.inputWidth,
        "inputHeight": self.engine.inputHeight,
        "classes": self.engine.classes.reduce(into: [String: String]()) { $0["\($1.key)"] = $1.value },
        "maskCoeffCount": self.engine.maskCoeffCount,
        "computeUnits": self.engine.requestedComputeUnits,
        "compiledAtRuntime": self.engine.compiledAtRuntime,
        "loadMs": self.engine.compileMs,
      ]
    }

    AsyncFunction("runBenchmark") { (options: BenchmarkOptions) -> [String: Any] in
      let threshold = Float(options.confidenceThreshold)
      let iou = Float(options.iouThreshold)
      let total = max(1, options.repetitions)

      var modelMs: [Double] = []
      var cycleMs: [Double] = []
      modelMs.reserveCapacity(total)
      cycleMs.reserveCapacity(total)

      var lastInstances: [Instance] = []
      for _ in 0..<total {
        let r = try self.engine.runOnce(confidenceThreshold: threshold, iouThreshold: iou)
        modelMs.append(r.modelMs)
        cycleMs.append(r.cycleMs)
        lastInstances = r.instances
      }

      // Latências INDIVIDUAIS, não agregados: é o que permite caracterizar o
      // aquecimento (T029) e manter a agregação como política do TypeScript.
      // ~100 valores por série; ordens de grandeza abaixo do limite de 64 KB.
      return [
        "modelMsAll": modelMs,
        "cycleMsAll": cycleMs,
        "thermalState": InferenceEngine.thermalStateLabel(),
        "executionUnit": self.engine.requestedComputeUnits,
        "instances": lastInstances.map {
          [
            "classIndex": $0.classIndex, "score": Double($0.score),
            "x": Double($0.x), "y": Double($0.y),
            "width": Double($0.width), "height": Double($0.height),
          ]
        },
      ]
    }

    AsyncFunction("unloadModel") {
      self.engine.unload()
    }

    // MARK: - Câmera (marco 2)

    AsyncFunction("hasCameraPermission") { () -> Bool in
      CameraSession.hasPermission()
    }

    AsyncFunction("requestCameraPermission") { () async -> Bool in
      await CameraSession.requestPermission()
    }

    AsyncFunction("startSession") { (options: SessionOptions) -> [String: Any] in
      // O modelo precisa estar carregado antes: carregar leva ~720 ms e faria
      // os primeiros segundos de telemetria medirem a carga, não a inferência.
      if !self.engine.isLoaded { try self.engine.load() }

      self.coordinator.engine = self.engine
      self.coordinator.onSample = { [weak self] sample in
        self?.sendEvent("onTelemetry", sample)
      }
      // Configuração vai para o sink, não para a view: ela ainda não existe
      // neste instante, e só nasce quando o JSX reage ao retorno desta função.
      PreviewSink.shared.store = self.coordinator.results
      PreviewSink.shared.imageSide = CGFloat(self.engine.inputWidth)
      PreviewSink.shared.active = true
      return try self.coordinator.start(
        sampleIntervalMs: options.sampleIntervalMs,
        mode: TransformMode(rawValue: options.transform) ?? .stretch,
        confidenceThreshold: Float(options.confidenceThreshold),
        iouThreshold: Float(options.iouThreshold))
    }

    AsyncFunction("setTransform") { (transform: String) in
      self.coordinator.mode = TransformMode(rawValue: transform) ?? .stretch
    }

    // MARK: - Captura (marco 4)

    AsyncFunction("capture") { (options: CaptureOptions) -> [String: Any] in
      // Congela ANTES de qualquer reconfiguração: a tela precisa segurar a
      // última imagem enquanto o formato é trocado (FR-009).
      // Congela imagem E overlay juntos. Separá-los mostraria caixas de um
      // frame sobre a imagem de outro.
      PreviewSink.shared.frozen = true
      self.coordinator.results.setPaused(true)

      do {
        let shot = try await self.coordinator.capturePhoto()
        let side = self.engine.inputWidth
        let square = try self.coordinator.squareFromPhoto(shot.buffer, side: side)
        let result = try self.engine.run(
          on: square,
          confidenceThreshold: 0.25,
          iouThreshold: 0.7)

        // As detecções da FOTO substituem as do último frame ao vivo. As
        // coordenadas são comparáveis: as duas passaram pela mesma
        // transformação para 640×640.
        // Geometria da estante, a partir das MÁSCARAS. Caixa alinhada aos
        // eixos não informa inclinação.
        var straightened = false
        var declineReason = "sem protótipos de máscara"
        var confidence = 0.0
        var shelves: [[String: Any]] = []
        var shelfCount = 0
        var lyingCount = 0
        var usedGravity = false
        var displayBuffer = square

        if let protos = result.protos {
          // A atitude é amostrada NO disparo, não depois: medir a inclinação
          // um instante mais tarde é medir outro momento.
          let gravity = self.coordinator.attitude.snapshot()
          let photoW = Double(CVPixelBufferGetWidth(shot.buffer))
          let photoH = Double(CVPixelBufferGetHeight(shot.buffer))
          let focal = Projective.Focal.from(
            fieldOfViewDegrees: self.coordinator.fieldOfView,
            sensorLongSide: max(photoW, photoH),
            portraitWidth: min(photoW, photoH),
            portraitHeight: max(photoW, photoH),
            canonicalSide: Double(side))

          let estimate = ShelfGeometry.estimate(
            instances: result.instances,
            protos: protos,
            imageSide: side,
            gravity: gravity,
            focal: focal,
            minInstances: options.minInstancesForGeometry,
            minConfidence: options.minGeometryConfidence)

          confidence = estimate.confidence
          declineReason = estimate.declineReason ?? ""
          shelfCount = estimate.rows.count
          lyingCount = estimate.lying.count
          usedGravity = estimate.usedGravity

          if let quad = estimate.quad,
             let out = Rectify.straighten(
               photo: shot.buffer, quad: quad, rows: estimate.rows,
               instances: result.instances, imageSide: side, margin: options.cropMargin),
             let rendered = Rectify.render(out.image, context: self.ciContext) {
            displayBuffer = rendered
            shelves = out.shelves.map {
              ["count": $0.count, "dividers": $0.dividers, "top": $0.top, "bottom": $0.bottom]
            }
            straightened = true
          } else if estimate.quad != nil {
            // O quadrilátero existia mas o warp falhou: recusar é desfecho
            // válido, não erro (FR-011).
            declineReason = "não foi possível aplicar a correção"
          }
        }

        // Uma imagem na tela, e as detecções são dela. Endireitada quando deu
        // para endireitar; a canônica quando não deu.
        PreviewSink.shared.showStill(displayBuffer)

        // O overlay ao vivo não vale sobre a imagem endireitada — as
        // coordenadas são de outro espaço. Limpa em vez de desenhar errado.
        if straightened {
          self.coordinator.results.publishOverriding(instances: [], protos: nil)
        } else {
          self.coordinator.results.publishOverriding(
            instances: result.instances, protos: result.protos)
        }

        return [
          "count": result.instances.count,
          "straightened": straightened,
          "declineReason": declineReason,
          "geometryConfidence": confidence,
          "shelves": shelves,
          "shelfCount": shelfCount,
          "lyingCount": lyingCount,
          "usedGravity": usedGravity,
          "imageId": UUID().uuidString,
          "elapsedMs": shot.elapsedMs,
          "photoWidth": CVPixelBufferGetWidth(shot.buffer),
          "photoHeight": CVPixelBufferGetHeight(shot.buffer),
          "instances": result.instances.count,
        ]
      } catch {
        PreviewSink.shared.frozen = false
        self.coordinator.results.setPaused(false)
        throw error
      }
    }

    AsyncFunction("dismissResult") {
      self.coordinator.results.setPaused(false)
      PreviewSink.shared.frozen = false
    }

    AsyncFunction("setOverlayStyle") { (record: OverlayStyleRecord) in
      var style = OverlayStyle()
      style.showBoxes = record.showBoxes
      style.showMasks = record.showMasks
      style.boxWidth = CGFloat(record.boxWidth)
      style.maskOpacity = CGFloat(record.maskOpacity)
      style.minConfidence = Float(record.minConfidence)
      if !record.palette.isEmpty {
        style.palette = record.palette.compactMap { UIColor(hex: $0)?.cgColor }
      }
      // Trocar estilo não pode custar um frame nem depender da view existir.
      PreviewSink.shared.style = style
    }

    // Preview: mostra o buffer JÁ TRANSFORMADO, o mesmo que vai ao modelo.
    View(PreviewView.self) {}

    AsyncFunction("stopSession") { () -> [String: Any] in
      PreviewSink.shared.active = false
      let summary = self.coordinator.stop()
      self.coordinator.onSample = nil
      return summary
    }

    // Se a view sumir sem stopSession, a câmera continuaria ligada gastando
    // bateria e aquecendo o aparelho — que é justamente o que o marco mede.
    OnDestroy {
      _ = self.coordinator.stop()
    }
  }
}
