import CoreGraphics
import Foundation

/// A faixa de interesse (spec 005): onde a detecção conta.
///
/// Vive nas coordenadas normalizadas da imagem canônica, que é ao mesmo tempo a
/// entrada do modelo e o que a tela mostra. Por isso uma faixa só serve ao ao
/// vivo e à captura: a foto passa pela mesma transformação.
enum BandMode: String {
  case off
  case horizontal
  case vertical
}

struct Band: Equatable {
  var mode: BandMode
  /// Centro no eixo em que a faixa anda — y na horizontal, x na vertical —, de 0 a 1.
  var center: Double
  /// Fração da imagem nesse mesmo eixo, de 0 a 1.
  var thickness: Double

  var lower: Double { center - thickness / 2 }
  var upper: Double { center + thickness / 2 }

  /// O retângulo da faixa dentro do retângulo da imagem.
  ///
  /// Desligada, é a moldura inteira. É o que faz ligar e desligar serem o mesmo
  /// movimento: a faixa se abrindo até a moldura, ou se fechando a partir dela.
  func rect(in image: CGRect) -> CGRect {
    switch mode {
    case .off:
      return image
    case .horizontal:
      return CGRect(x: image.minX, y: image.minY + CGFloat(lower) * image.height,
                    width: image.width, height: CGFloat(thickness) * image.height)
    case .vertical:
      return CGRect(x: image.minX + CGFloat(lower) * image.width, y: image.minY,
                    width: CGFloat(thickness) * image.width, height: image.height)
    }
  }

  /// A regra de pertença (FR-004): a maior parte da caixa — `membership` dela —
  /// dentro da faixa, medida no eixo em que a faixa é limitada. Desligada, tudo
  /// pertence.
  ///
  /// A caixa, e não a máscara: a faixa é grosseira perto da precisão de uma
  /// máscara, e a caixa já está pronta em todo frame.
  func contains(_ inst: Instance, imageSide: Float, membership: Double) -> Bool {
    guard imageSide > 0 else { return true }
    let start: Float
    let extent: Float
    switch mode {
    case .off: return true
    case .horizontal: start = inst.y; extent = inst.height
    case .vertical: start = inst.x; extent = inst.width
    }
    guard extent > 0 else { return false }
    let a = Double(start / imageSide)
    let b = Double((start + extent) / imageSide)
    let overlap = max(0, min(b, upper) - max(a, lower))
    return overlap >= membership * (b - a)
  }

  func members(of instances: [Instance], imageSide: Float, membership: Double) -> [Instance] {
    guard mode != .off else { return instances }
    return instances.filter { contains($0, imageSide: imageSide, membership: membership) }
  }

  /// Para atravessar a fronteira: três números e um texto.
  var dictionary: [String: Any] {
    ["mode": mode.rawValue, "center": center, "thickness": thickness]
  }
}

/// Comportamento da faixa. Vem do TypeScript, em `SessionOptions.band` —
/// princípio IV. O que cada campo decide está no data-model da 005.
struct BandPolicy {
  var defaultThickness: Double
  var minThickness: Double
  var membership: Double
  var flipHysteresisDegrees: Double
  var offMargin: Double
  var rubberBand: Double
  var startSlopPoints: Double
  var edgeGrabPoints: Double
  var countWindowMs: Double
  var springResponse: Double
  var springDamping: Double
  var haptics: Bool

  /// Antes da primeira sessão. Zerada, como os defaults da ponte: uma faixa
  /// sem espessura, e o defeito à vista.
  static let unset = BandPolicy(
    defaultThickness: 0, minThickness: 0, membership: 0, flipHysteresisDegrees: 0,
    offMargin: 0, rubberBand: 0, startSlopPoints: 0, edgeGrabPoints: 0,
    countWindowMs: 0, springResponse: 0, springDamping: 0, haptics: false)
}

/// O estado da faixa (R26).
///
/// O nativo é a fonte da verdade; o JavaScript espelha. O gesto escreve no
/// thread principal e a fila da câmera lê, daí a trava.
final class BandModel {
  private let lock = NSLock()
  private var band = Band(mode: .off, center: 0.5, thickness: 0)
  private var policy = BandPolicy.unset
  private var generation: UInt64 = 0
  /// Religar volta a ela (FR-019). Some com a sessão.
  private var lastOn: Band?
  /// O último estado avisado ao JavaScript. `commit` só avisa se mudou.
  private var committed: Band?

  /// Mudança discreta: fim de gesto, troca de modo, volta ao centro, começo de
  /// sessão. **Nunca durante o arrasto** — princípio III. Chamado fora da trava.
  var onChange: ((Band) -> Void)?

  /// A geração muda a cada escrita: o overlay redesenha quando ela muda, mesmo
  /// sem inferência nova.
  func read() -> (band: Band, policy: BandPolicy, generation: UInt64) {
    lock.lock(); defer { lock.unlock() }
    return (band, policy, generation)
  }

  /// Escrita silenciosa, para o gesto: desenho e filtro veem na hora; o
  /// JavaScript, só no `commit`.
  func write(_ next: Band) {
    lock.lock()
    if next != band {
      band = next
      generation &+= 1
    }
    lock.unlock()
  }

  /// Avisa quem espelha, se o estado mudou desde o último aviso.
  func commit() {
    lock.lock()
    let current = band
    let changed = committed != current
    if changed { committed = current }
    lock.unlock()
    if changed { onChange?(current) }
  }

  /// Começo de sessão (FR-002): horizontal, no centro, espessura padrão —
  /// venha a sessão anterior de onde vier.
  @discardableResult
  func reset(policy next: BandPolicy) -> Band {
    lock.lock()
    policy = next
    lastOn = nil
    committed = nil
    band = Band(mode: .horizontal, center: 0.5, thickness: next.defaultThickness)
    generation &+= 1
    let current = band
    lock.unlock()
    return current
  }

  /// As transições de modo do contrato (`setBandMode`). Escreve o destino e
  /// devolve de onde e para onde, para quem anima; `nil` se já estava no modo.
  ///
  /// - desligada → uma orientação: volta à última faixa ligada, virando se for
  ///   a outra orientação; sem última, a faixa padrão
  /// - uma orientação → a outra: mantém centro e espessura
  /// - ligada → desligada: guarda a faixa para religar
  func setMode(_ mode: BandMode) -> (from: Band, to: Band)? {
    lock.lock(); defer { lock.unlock() }
    let from = band
    guard mode != from.mode else { return nil }
    let to: Band
    switch (from.mode, mode) {
    case (.off, _):
      let base = lastOn ?? Band(mode: mode, center: 0.5, thickness: policy.defaultThickness)
      to = Band(mode: mode, center: base.center, thickness: base.thickness)
    case (_, .off):
      lastOn = from
      to = Band(mode: .off, center: from.center, thickness: from.thickness)
    default:
      to = Band(mode: mode, center: from.center, thickness: from.thickness)
    }
    band = to
    generation &+= 1
    return (from, to)
  }
}
