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

  func start(sampleIntervalMs: Int) throws -> [String: Any] {
    gate.reset()
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
    let payload: [String: Any] = [
      "t": now.timeIntervalSince(startedAt) * 1000,
      "fpsCaptured": Double(received - lastReceived) / windowSec,
      "fpsInferred": Double(processed - lastProcessed) / windowSec,
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
    guard var frame = gate.submit(buffer, at: time) else { return }

    // Fase 2: nada é feito com o frame além de contá-lo. Transformação e
    // inferência entram em T008–T012, exatamente aqui.
    while true {
      _ = frame
      guard let next = gate.finishAndTakeNext() else { break }
      frame = next
    }
  }
}
