import Foundation

/// Acumula a sessão. Buffer circular: uma sessão longa não pode crescer sem
/// limite, e truncar em silêncio seria pior que truncar avisando.
final class Telemetry {
  /// 4000 amostras a 2 Hz são ~33 minutos. Acima disso, as mais antigas saem.
  private let capacity: Int

  private let lock = NSLock()
  private var samples: [[String: Any]] = []
  private var transitions: [[String: Any]] = []
  private var lastThermal: String?
  private(set) var truncated = false

  init(capacity: Int = 4000) {
    self.capacity = capacity
  }

  func reset() {
    lock.lock(); defer { lock.unlock() }
    samples.removeAll(keepingCapacity: true)
    transitions.removeAll(keepingCapacity: true)
    lastThermal = nil
    truncated = false
  }

  func record(_ sample: [String: Any]) {
    lock.lock(); defer { lock.unlock() }

    // FR-007: o instante de cada mudança de estado térmico. Sem isto, sabe-se
    // que o aparelho esquentou, mas não em que minuto — e é o minuto que diz
    // se o uso contínuo é viável.
    if let state = sample["thermalState"] as? String, state != lastThermal {
      transitions.append([
        "t": sample["t"] ?? 0,
        "from": lastThermal ?? "início",
        "to": state,
      ])
      lastThermal = state
    }

    samples.append(sample)
    if samples.count > capacity {
      samples.removeFirst(samples.count - capacity)
      truncated = true
    }
  }

  func snapshot() -> (samples: [[String: Any]], transitions: [[String: Any]], truncated: Bool) {
    lock.lock(); defer { lock.unlock() }
    return (samples, transitions, truncated)
  }
}
