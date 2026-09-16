import CoreMedia
import CoreVideo
import Foundation

struct PendingFrame {
  let buffer: CVPixelBuffer
  /// Carimbo do próprio frame. É o que torna a latência ponta-a-ponta
  /// mensurável em vez de estimada (FR-009).
  let presentationTime: CMTime
  let sequence: Int
}

/// Fila de profundidade 1, com descarte do mais antigo.
///
/// Princípio I da constituição: fila que cresce é latência que cresce sem
/// limite. Chegando frame novo com a inferência ocupada, o pendente é
/// *substituído* — nunca enfileirado.
final class FrameGate {
  private let lock = NSLock()
  private var pending: PendingFrame?
  private var processing = false
  private var sequence = 0

  private(set) var received = 0
  private(set) var dropped = 0
  private(set) var processed = 0

  /// Profundidade atual: 0 ou 1. Se algum dia passar disso, o descarte falhou.
  var queueDepth: Int {
    lock.lock(); defer { lock.unlock() }
    return pending == nil ? 0 : 1
  }

  /// Devolve o frame a processar agora, ou `nil` se já há um em processamento.
  func submit(_ buffer: CVPixelBuffer, at time: CMTime) -> PendingFrame? {
    lock.lock(); defer { lock.unlock() }
    received += 1
    sequence += 1
    let frame = PendingFrame(buffer: buffer, presentationTime: time, sequence: sequence)

    if processing {
      // Já havia um pendente: ele morre aqui. É o descarte do mais antigo.
      if pending != nil { dropped += 1 }
      pending = frame
      return nil
    }

    processing = true
    return frame
  }

  /// Fecha o frame atual e devolve o próximo, se houver.
  func finishAndTakeNext() -> PendingFrame? {
    lock.lock(); defer { lock.unlock() }
    processed += 1
    if let next = pending {
      pending = nil
      return next
    }
    processing = false
    return nil
  }

  func reset() {
    lock.lock(); defer { lock.unlock() }
    pending = nil
    processing = false
    received = 0
    dropped = 0
    processed = 0
    sequence = 0
  }
}
