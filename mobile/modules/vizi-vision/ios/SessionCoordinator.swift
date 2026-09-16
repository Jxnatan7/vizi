import AVFoundation
import UIKit
import CoreMedia
import CoreVideo
import Foundation

/// Amarra câmera, fila e amostragem.
///
/// A transformação e a inferência entram aqui na fase 3 (T008–T013). Nesta
/// etapa o objetivo é só provar que os frames chegam — se a captura não estiver
/// sólida antes, todo problema posterior vai parecer problema de inferência.
final class SessionCoordinator: NSObject, CameraSessionDelegate {
  private let camera = CameraSession()
  private let gate = FrameGate()
  private let transform = FrameTransform()

  /// Carregado pelo módulo antes de iniciar a sessão.
  weak var engine: InferenceEngine?

  private let modeLock = NSLock()
  private var _mode: TransformMode = .stretch
  var mode: TransformMode {
    get { modeLock.lock(); defer { modeLock.unlock() }; return _mode }
    set { modeLock.lock(); _mode = newValue; modeLock.unlock() }
  }

  private var confidenceThreshold: Float = 0.25
  private var iouThreshold: Float = 0.7

  /// Janela corrente. Zerada a cada amostra — médias acumuladas escondem
  /// exatamente a degradação que este marco procura.
  private let statsLock = NSLock()
  private var transformMs: [Double] = []
  private var inferMs: [Double] = []
  private var decodeMs: [Double] = []
  private var e2eMs: [Double] = []
  private var lastInstanceCount = 0

  private var timer: DispatchSourceTimer?
  private let timerQueue = DispatchQueue(label: "com.jxnatan7.vizi.telemetry")

  /// Emitido a ~2 Hz, NUNCA por frame: 60 travessias por segundo violariam os
  /// princípios II e III de uma vez.
  var onSample: (([String: Any]) -> Void)?

  private var startedAt = Date()
  private var lastSampleAt = Date()
  private var lastReceived = 0
  private var lastProcessed = 0

  // MARK: - Ciclo de vida

  func start(sampleIntervalMs: Int, mode: TransformMode,
             confidenceThreshold: Float, iouThreshold: Float) throws -> [String: Any] {
    gate.reset()
    self.mode = mode
    self.confidenceThreshold = confidenceThreshold
    self.iouThreshold = iouThreshold
    resetWindow()
    camera.delegate = self
    try camera.configure()
    camera.start()

    startedAt = Date()
    lastSampleAt = startedAt
    lastReceived = 0
    lastProcessed = 0
    startTimer(intervalMs: max(100, sampleIntervalMs))

    return [
      "captureWidth": camera.captureWidth,
      "captureHeight": camera.captureHeight,
      "maxFrameRate": camera.maxFrameRate,
    ]
  }

  func stop() -> [String: Any] {
    timer?.cancel()
    timer = nil
    camera.stop()
    camera.delegate = nil
    return [
      "durationMs": Date().timeIntervalSince(startedAt) * 1000,
      "received": gate.received,
      "processed": gate.processed,
      "dropped": gate.dropped,
    ]
  }

  var isRunning: Bool { camera.isRunning }

  // MARK: - Amostragem

  private func startTimer(intervalMs: Int) {
    let t = DispatchSource.makeTimerSource(queue: timerQueue)
    t.schedule(deadline: .now() + .milliseconds(intervalMs),
               repeating: .milliseconds(intervalMs))
    t.setEventHandler { [weak self] in self?.emitSample() }
    timer = t
    t.resume()
  }

  private func emitSample() {
    let now = Date()
    let windowSec = now.timeIntervalSince(lastSampleAt)
    guard windowSec > 0 else { return }

    let received = gate.received
    let processed = gate.processed

    // Taxas da JANELA, não acumuladas desde o início: uma média acumulada
    // esconde exatamente a degradação que este marco existe para detectar.
    statsLock.lock()
    let tMs = Self.median(transformMs)
    let iMs = Self.median(inferMs)
    let dMs = Self.median(decodeMs)
    let eMs = Self.median(e2eMs)
    let count = lastInstanceCount
    transformMs.removeAll(keepingCapacity: true)
    inferMs.removeAll(keepingCapacity: true)
    decodeMs.removeAll(keepingCapacity: true)
    e2eMs.removeAll(keepingCapacity: true)
    statsLock.unlock()

    let payload: [String: Any] = [
      "t": now.timeIntervalSince(startedAt) * 1000,
      "fpsCaptured": Double(received - lastReceived) / windowSec,
      "fpsInferred": Double(processed - lastProcessed) / windowSec,
      "transformMs": tMs,
      "inferMs": iMs,
      "decodeMs": dMs,
      "e2eMs": eMs,
      "instanceCount": count,
      "transform": mode.rawValue,
      "queueDepth": gate.queueDepth,
      "dropped": gate.dropped,
      "thermalState": InferenceEngine.thermalStateLabel(),
      "batteryLevel": Self.batteryLevel(),
      "lowPowerMode": ProcessInfo.processInfo.isLowPowerModeEnabled,
    ]

    lastSampleAt = now
    lastReceived = received
    lastProcessed = processed
    onSample?(payload)
  }

  private static func batteryLevel() -> Double {
    UIDevice.current.isBatteryMonitoringEnabled = true
    let level = UIDevice.current.batteryLevel
    // -1 significa indisponível (simulador, ou monitoramento recém-ligado).
    return level < 0 ? -1 : Double(level)
  }

  // MARK: - Frames

  func cameraSession(_ session: CameraSession, didOutput buffer: CVPixelBuffer, at time: CMTime) {
    guard let first = gate.submit(buffer, at: time) else { return }

    var current: PendingFrame? = first
    while let frame = current {
      autoreleasepool { process(frame) }
      current = gate.finishAndTakeNext()
    }
  }

  private func process(_ frame: PendingFrame) {
    guard let engine, engine.isLoaded else { return }
    let side = engine.inputWidth
    guard side > 0 else { return }

    let t0 = CFAbsoluteTimeGetCurrent()
    guard let square = transform.transform(frame.buffer, mode: mode, side: side) else { return }
    let transformElapsed = (CFAbsoluteTimeGetCurrent() - t0) * 1000

    // O preview recebe o MESMO buffer que a inferência. Ver é literalmente ver
    // o que o modelo recebe.
    PreviewSink.shared.push(square)

    guard let result = try? engine.run(
      on: square,
      confidenceThreshold: confidenceThreshold,
      iouThreshold: iouThreshold) else { return }

    // Ponta-a-ponta a partir do carimbo do PRÓPRIO frame (FR-009). Medir do
    // início do processamento esconderia o tempo que ele passou esperando.
    let now = CMClockGetTime(CMClockGetHostTimeClock())
    let e2e = (now - frame.presentationTime).seconds * 1000

    statsLock.lock()
    transformMs.append(transformElapsed)
    inferMs.append(result.modelMs)
    decodeMs.append(result.decodeMs)
    e2eMs.append(e2e)
    lastInstanceCount = result.instances.count
    statsLock.unlock()
  }

  private func resetWindow() {
    statsLock.lock()
    transformMs.removeAll(keepingCapacity: true)
    inferMs.removeAll(keepingCapacity: true)
    decodeMs.removeAll(keepingCapacity: true)
    e2eMs.removeAll(keepingCapacity: true)
    statsLock.unlock()
  }

  private static func median(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    let s = values.sorted()
    return s[s.count / 2]
  }
}
