import CoreML
import QuartzCore
import UIKit

/// Aparência do overlay. Dado enviado pelo TypeScript, não decisão do nativo —
/// é a mitigação do princípio IV registrada no plano.
struct OverlayStyle {
  var showBoxes = true
  var showMasks = true
  /// Em pixels do espaço do modelo (640), não da tela: a view muda de tamanho,
  /// o espaço do modelo não.
  var boxWidth: CGFloat = 3
  var maskOpacity: CGFloat = 0.45
  var minConfidence: Float = 0.3
  var palette: [CGColor] = OverlayStyle.defaultPalette

  static let defaultPalette: [CGColor] = [
    UIColor(red: 0.29, green: 0.78, blue: 0.62, alpha: 1).cgColor,
    UIColor(red: 0.98, green: 0.71, blue: 0.33, alpha: 1).cgColor,
    UIColor(red: 0.42, green: 0.65, blue: 0.96, alpha: 1).cgColor,
    UIColor(red: 0.95, green: 0.46, blue: 0.50, alpha: 1).cgColor,
    UIColor(red: 0.73, green: 0.58, blue: 0.94, alpha: 1).cgColor,
    UIColor(red: 0.40, green: 0.85, blue: 0.87, alpha: 1).cgColor,
  ]
}

/// Publica o último resultado da inferência para quem quiser ler.
///
/// É o princípio I em código: o desenho **lê**, nunca aguarda. A inferência
/// publica e segue; se ninguém ler, nada acontece.
final class ResultStore {
  private let lock = NSLock()
  private var instances: [Instance] = []
  private var protos: MLMultiArray?
  private var generation: UInt64 = 0

  func publish(instances: [Instance], protos: MLMultiArray?) {
    lock.lock()
    self.instances = instances
    self.protos = protos
    generation &+= 1
    lock.unlock()
  }

  /// Nunca devolve vazio por falta de resultado novo — FR-009: sumir é pior
  /// que atrasar.
  func read() -> (instances: [Instance], protos: MLMultiArray?, generation: UInt64) {
    lock.lock(); defer { lock.unlock() }
    return (instances, protos, generation)
  }

  func clear() {
    lock.lock()
    instances = []
    protos = nil
    generation &+= 1
    lock.unlock()
  }
}

/// Desenha no relógio do display, lendo o último resultado publicado.
final class OverlayRenderer {
  let boxLayer = CALayer()
  let maskLayer = CALayer()

  var style = OverlayStyle()
  var imageSide: CGFloat = 640
  weak var store: ResultStore?

  /// Custo do último desenho, lido pela telemetria (FR-006).
  private(set) var lastDrawMs: Double = 0

  private var link: CADisplayLink?
  private var lastGeneration: UInt64 = .max

  /// Uma sublayer por caixa. Uma `CAShapeLayer` única tem uma só `strokeColor`,
  /// e o FR-004 pede cor distinta por objeto vizinho.
  ///
  /// O pool cresce até o máximo de instâncias já visto e não encolhe: camadas
  /// ocultas não custam nada, e realocar a cada frame custaria.
  private var boxPool: [CAShapeLayer] = []

  init() {
    maskLayer.magnificationFilter = .linear
    maskLayer.contentsGravity = .resize
  }

  func attach(to host: CALayer) {
    host.addSublayer(maskLayer)
    host.addSublayer(boxLayer)   // caixas por cima das máscaras
  }

  func layout(_ bounds: CGRect) {
    boxLayer.frame = bounds
    maskLayer.frame = bounds
    boxPool.forEach { $0.frame = boxLayer.bounds }
  }

  func start() {
    guard link == nil else { return }
    let l = CADisplayLink(target: self, selector: #selector(tick))
    l.add(to: .main, forMode: .common)
    link = l
  }

  func stop() {
    link?.invalidate()
    link = nil
    lastGeneration = .max
    boxPool.forEach { $0.isHidden = true }
    maskLayer.contents = nil
  }

  @objc private func tick() {
    guard let store else { return }
    let snapshot = store.read()
    // Nada novo desde o último desenho: não há por que repintar.
    guard snapshot.generation != lastGeneration else { return }
    lastGeneration = snapshot.generation

    let started = CFAbsoluteTimeGetCurrent()
    let visible = snapshot.instances.filter { $0.score >= style.minConfidence }

    // Sem animação implícita: a 60 Hz, interpolar entre estados produziria
    // arrasto em vez de acompanhamento.
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    drawBoxes(visible)
    CATransaction.commit()

    lastDrawMs = (CFAbsoluteTimeGetCurrent() - started) * 1000
  }

  // MARK: - Caixas

  private func drawBoxes(_ instances: [Instance]) {
    guard style.showBoxes else {
      boxPool.forEach { $0.isHidden = true }
      return
    }

    growPool(to: instances.count)
    let scale = boxLayer.bounds.width / imageSide
    let width = style.boxWidth * scale

    for (i, inst) in instances.enumerated() {
      let shape = boxPool[i]
      shape.isHidden = false
      shape.path = CGPath(rect: CGRect(
        x: CGFloat(inst.x) * scale,
        y: CGFloat(inst.y) * scale,
        width: CGFloat(inst.width) * scale,
        height: CGFloat(inst.height) * scale), transform: nil)
      shape.strokeColor = color(for: inst)
      shape.lineWidth = width
    }
    for i in instances.count..<boxPool.count {
      boxPool[i].isHidden = true
    }
  }

  private func growPool(to count: Int) {
    while boxPool.count < count {
      let shape = CAShapeLayer()
      shape.fillColor = nil
      shape.lineJoin = .round
      boxLayer.addSublayer(shape)
      boxPool.append(shape)
    }
  }

  /// Cor determinística pela posição — R11.
  ///
  /// Cor por índice na lista pisca: a ordenação vem do escore e muda a cada
  /// frame. Pela posição, dois objetos vizinhos caem em células diferentes e
  /// recebem cores diferentes.
  ///
  /// **Limitação conhecida:** um objeto que cruza a fronteira de uma célula
  /// troca de cor. Sem rastreamento não há como evitar — e se isso incomodar na
  /// prática, é argumento a favor do marco 4.
  func color(for inst: Instance) -> CGColor {
    let cell: Float = 24
    let cx = Int((inst.x + inst.width / 2) / cell)
    let cy = Int((inst.y + inst.height / 2) / cell)
    let index = abs(cx &+ cy &* 3) % style.palette.count
    return style.palette[index]
  }
}

extension UIColor {
  /// "#RRGGBB" → cor. A paleta vem do TypeScript como texto.
  convenience init?(hex: String) {
    var s = hex.trimmingCharacters(in: .whitespaces)
    if s.hasPrefix("#") { s.removeFirst() }
    guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
    self.init(
      red: CGFloat((v >> 16) & 0xFF) / 255,
      green: CGFloat((v >> 8) & 0xFF) / 255,
      blue: CGFloat(v & 0xFF) / 255,
      alpha: 1)
  }
}
