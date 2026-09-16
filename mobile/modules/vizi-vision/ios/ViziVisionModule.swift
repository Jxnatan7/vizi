import ExpoModulesCore
import Foundation

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
struct SessionOptions: Record {
  @Field var sampleIntervalMs: Int = 500
  @Field var transform: String = "stretch"
  @Field var confidenceThreshold: Double = 0.25
  @Field var iouThreshold: Double = 0.7
}

public class ViziVisionModule: Module {
  private let engine = InferenceEngine()
  private let coordinator = SessionCoordinator()

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
      return try self.coordinator.start(
        sampleIntervalMs: options.sampleIntervalMs,
        mode: TransformMode(rawValue: options.transform) ?? .stretch,
        confidenceThreshold: Float(options.confidenceThreshold),
        iouThreshold: Float(options.iouThreshold))
    }

    AsyncFunction("setTransform") { (transform: String) in
      self.coordinator.mode = TransformMode(rawValue: transform) ?? .stretch
    }

    // Preview: mostra o buffer JÁ TRANSFORMADO, o mesmo que vai ao modelo.
    View(PreviewView.self) {}

    AsyncFunction("stopSession") { () -> [String: Any] in
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
