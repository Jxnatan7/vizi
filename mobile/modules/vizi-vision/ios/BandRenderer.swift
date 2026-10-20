import QuartzCore
import UIKit

/// Desenha a faixa de interesse na `PreviewView` (spec 005, R20).
///
/// Três coisas: o escurecimento fora dela, as bordas com as alças, e a
/// contagem. Toda mudança de estado é uma mola levando um retângulo a outro;
/// durante o arrasto, as camadas vão exatamente aonde o dedo está.
final class BandRenderer {
  /// A moldura menos a faixa, com preenchimento par-ímpar. Fica **abaixo** do
  /// overlay: um livro que conta aparece aceso mesmo onde passa da borda.
  let dimLayer = CAShapeLayer()
  /// As duas bordas.
  let edgeLayer = CAShapeLayer()
  /// Uma linha curta e grossa de ponta redonda é uma cápsula: são as alças.
  let handleLayer = CAShapeLayer()
  /// A contagem, numa pílula presa à ponta de uma borda.
  let countPill = CALayer()
  private let countText = CATextLayer()

  let feedback = BandFeedback()

  var style = OverlayStyle() { didSet { restyle() } }
  private var policy = BandPolicy.unset
  private(set) var band = Band(mode: .off, center: 0.5, thickness: 0)
  /// A orientação em que a faixa desligada se desenha: a última que ela teve.
  /// Assim ela se abre até a moldura sem trocar de eixo no caminho.
  private var orientation = BandMode.horizontal
  private var image = CGRect.zero
  private var bounds = CGRect.zero
  private(set) var visible = true

  /// Contagens recentes, para a mediana (R23).
  private var samples: [(time: CFTimeInterval, count: Int)] = []
  private var shownCount: Int?

  /// A contagem que a pílula mostra agora, ou `nil` quando ela não aparece —
  /// faixa desligada ou fora de cena. É o que uma marca registra como "a
  /// contagem que a tela mostrava" (spec 007, R37).
  var displayedCount: Int? {
    visible && band.mode != .off ? shownCount : nil
  }

  init() {
    dimLayer.fillRule = .evenOdd
    edgeLayer.fillColor = nil
    handleLayer.fillColor = nil
    handleLayer.lineCap = .round
    countPill.masksToBounds = true
    countText.alignmentMode = .center
    countPill.addSublayer(countText)
    restyle()
  }

  func configure(policy next: BandPolicy) {
    policy = next
    feedback.enabled = next.haptics
  }

  /// - Parameters:
  ///   - image: o quadrado da imagem canônica na view, onde a faixa vive
  ///   - bounds: a view inteira, que o escurecimento cobre
  func layout(image nextImage: CGRect, bounds nextBounds: CGRect, scale: CGFloat) {
    image = nextImage
    bounds = nextBounds
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    for layer in [dimLayer, edgeLayer, handleLayer] { layer.frame = nextBounds }
    countText.contentsScale = scale
    CATransaction.commit()
    apply(band, animated: false)
  }

  // MARK: - Estado

  /// Leva a faixa a `next`. Animado, é uma mola partindo de onde ela está na
  /// tela — também quando uma mola anterior ainda não terminou.
  ///
  /// Desligar é a faixa se abrindo até a moldura, com bordas, alças e contagem
  /// sumindo; ligar é a moldura se fechando até a faixa (FR-017).
  ///
  /// - Parameter completion: quando a mola chega — ou é cortada por outra, ou
  ///   por um gesto. Sem animação, logo depois de desenhar.
  func apply(_ next: Band, animated: Bool, completion: (() -> Void)? = nil) {
    // Desligada, a faixa é a moldura em qualquer orientação. Religando na
    // outra, ela parte da moldura já no eixo novo: a mola só fecha, não vira.
    let reorient = band.mode == .off && next.mode != .off && next.mode != orientation
    let oldDim = (dimLayer.presentation() ?? dimLayer).path
    let oldEdges = reorient
      ? edgePath(image, vertical: next.mode == .vertical)
      : (edgeLayer.presentation() ?? edgeLayer).path
    let oldHandles = reorient
      ? handlePath(image, vertical: next.mode == .vertical)
      : (handleLayer.presentation() ?? handleLayer).path
    let oldPill = (countPill.presentation() ?? countPill).position

    band = next
    if next.mode != .off { orientation = next.mode }
    let rect = next.rect(in: image)
    let vertical = orientation == .vertical
    let dim = dimPath(rect)
    let edges = edgePath(rect, vertical: vertical)
    let handles = handlePath(rect, vertical: vertical)
    let controls: Float = visible && next.mode != .off ? 1 : 0

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    CATransaction.setCompletionBlock(completion)
    dimLayer.path = dim
    edgeLayer.path = edges
    handleLayer.path = handles
    placePill(rect, vertical: vertical)
    if animated {
      spring(dimLayer, "path", from: oldDim, to: dim)
      spring(edgeLayer, "path", from: oldEdges, to: edges)
      spring(handleLayer, "path", from: oldHandles, to: handles)
      spring(countPill, "position",
             from: NSValue(cgPoint: oldPill), to: NSValue(cgPoint: countPill.position))
      for layer in [edgeLayer, handleLayer, countPill] as [CALayer] { fade(layer, to: controls) }
    } else {
      // No ritmo do dedo: nada de mola no meio (FR-017).
      for layer in [dimLayer, edgeLayer, handleLayer] { layer.removeAnimation(forKey: "path") }
      countPill.removeAnimation(forKey: "position")
      for layer in [edgeLayer, handleLayer, countPill] as [CALayer] { layer.opacity = controls }
    }
    CATransaction.commit()
  }

  /// A faixa que está na tela agora — no meio de uma mola, se houver uma — e
  /// as animações param ali. É de onde um gesto novo parte, sem salto.
  func freezeAtPresentation() -> Band {
    guard band.mode != .off, edgeLayer.animation(forKey: "path") != nil,
          let path = edgeLayer.presentation()?.path,
          image.width > 0, image.height > 0 else { return band }
    // As duas bordas delimitam exatamente a faixa.
    let r = path.boundingBoxOfPath
    let presented = band.mode == .vertical
      ? Band(mode: .vertical, center: Double((r.midX - image.minX) / image.width),
             thickness: Double(r.width / image.width))
      : Band(mode: .horizontal, center: Double((r.midY - image.minY) / image.height),
             thickness: Double(r.height / image.height))
    apply(presented, animated: false)
    return presented
  }

  /// Some durante a captura e o resultado (FR-020), e volta como estava.
  func setVisible(_ next: Bool, animated: Bool) {
    guard next != visible else { return }
    visible = next
    // Os zeros do resultado não entram na mediana de quando a faixa volta.
    if next { samples.removeAll(); shownCount = nil }
    let dimTo: Float = next ? 1 : 0
    let controlsTo: Float = next && band.mode != .off ? 1 : 0
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    if animated {
      fade(dimLayer, to: dimTo)
      for layer in [edgeLayer, handleLayer, countPill] as [CALayer] { fade(layer, to: controlsTo) }
    } else {
      dimLayer.opacity = dimTo
      for layer in [edgeLayer, handleLayer, countPill] as [CALayer] { layer.opacity = controlsTo }
    }
    CATransaction.commit()
  }

  // MARK: - Contagem

  /// A contagem da faixa pela mediana numa janela de tempo (FR-015, R23).
  ///
  /// A contagem crua oscila de quadro a quadro; a mediana mata o tremor sem
  /// esconder uma mudança real. O texto só troca quando a mediana troca.
  func updateCount(_ count: Int, now: CFTimeInterval = CACurrentMediaTime()) {
    let window = policy.countWindowMs / 1000
    samples.append((time: now, count: count))
    samples.removeAll { now - $0.time > window }
    let sorted = samples.map { $0.count }.sorted()
    guard !sorted.isEmpty else { return }
    let median = sorted[sorted.count / 2]
    guard median != shownCount else { return }
    shownCount = median

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    countText.string = "\(median)"
    sizePill()
    placePill(band.rect(in: image), vertical: orientation == .vertical)
    CATransaction.commit()
  }

  // MARK: - Geometria

  private func dimPath(_ band: CGRect) -> CGPath {
    let path = CGMutablePath()
    path.addRect(bounds)
    path.addRect(band)
    return path
  }

  /// As duas bordas. Horizontal e vertical têm a mesma estrutura — duas linhas —,
  /// e é isso que deixa a mola levar uma à outra sem torcer.
  private func edgePath(_ r: CGRect, vertical: Bool) -> CGPath {
    let path = CGMutablePath()
    if vertical {
      path.move(to: CGPoint(x: r.minX, y: r.minY))
      path.addLine(to: CGPoint(x: r.minX, y: r.maxY))
      path.move(to: CGPoint(x: r.maxX, y: r.minY))
      path.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
    } else {
      path.move(to: CGPoint(x: r.minX, y: r.minY))
      path.addLine(to: CGPoint(x: r.maxX, y: r.minY))
      path.move(to: CGPoint(x: r.minX, y: r.maxY))
      path.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
    }
    return path
  }

  /// Uma alça no meio de cada borda: o convite para puxar.
  private func handlePath(_ r: CGRect, vertical: Bool) -> CGPath {
    let half = style.bandHandleLength / 2
    let path = CGMutablePath()
    if vertical {
      path.move(to: CGPoint(x: r.minX, y: r.midY - half))
      path.addLine(to: CGPoint(x: r.minX, y: r.midY + half))
      path.move(to: CGPoint(x: r.maxX, y: r.midY - half))
      path.addLine(to: CGPoint(x: r.maxX, y: r.midY + half))
    } else {
      path.move(to: CGPoint(x: r.midX - half, y: r.minY))
      path.addLine(to: CGPoint(x: r.midX + half, y: r.minY))
      path.move(to: CGPoint(x: r.midX - half, y: r.maxY))
      path.addLine(to: CGPoint(x: r.midX + half, y: r.maxY))
    }
    return path
  }

  /// Na borda de cima, perto do fim — ou na da direita, perto do topo —,
  /// afastada da quina pela própria altura: sem cobrir livros da faixa.
  private func placePill(_ r: CGRect, vertical: Bool) {
    let size = countPill.bounds.size
    countPill.position = vertical
      ? CGPoint(x: r.maxX, y: r.minY + size.height * 1.5)
      : CGPoint(x: r.maxX - size.height - size.width / 2, y: r.minY)
  }

  private func sizePill() {
    let font = countFont
    let text = (countText.string as? String) ?? ""
    let textWidth = ceil((text as NSString).size(withAttributes: [.font: font]).width)
    let lineHeight = ceil(font.lineHeight)
    let height = lineHeight + style.bandCountFontSize / 2
    let width = max(height, textWidth + style.bandCountFontSize)
    countPill.bounds = CGRect(x: 0, y: 0, width: width, height: height)
    countPill.cornerRadius = height / 2
    countText.frame = CGRect(x: 0, y: (height - lineHeight) / 2, width: width, height: lineHeight)
  }

  private var countFont: UIFont {
    UIFont.monospacedDigitSystemFont(ofSize: style.bandCountFontSize, weight: .semibold)
  }

  // MARK: - Aparência e animação

  private func restyle() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    dimLayer.fillColor = UIColor.black.withAlphaComponent(style.bandDimOpacity).cgColor
    edgeLayer.strokeColor = style.bandEdgeColor
    edgeLayer.lineWidth = style.bandEdgeWidth
    handleLayer.strokeColor = style.bandEdgeColor
    handleLayer.lineWidth = style.bandHandleThickness
    countPill.backgroundColor = UIColor.black.withAlphaComponent(style.bandDimOpacity).cgColor
    countText.foregroundColor = style.bandEdgeColor
    countText.font = countFont
    countText.fontSize = style.bandCountFontSize
    sizePill()
    CATransaction.commit()
    apply(band, animated: false)
  }

  /// A mola de `springResponse` e `springDamping`, em termos de massa, rigidez
  /// e amortecimento — o que o `CASpringAnimation` do iOS 16 entende.
  private func spring(_ layer: CALayer, _ keyPath: String, from: Any?, to: Any?) {
    guard policy.springResponse > 0 else { return }
    let animation = CASpringAnimation(keyPath: keyPath)
    animation.mass = 1
    animation.stiffness = CGFloat(pow(2 * Double.pi / policy.springResponse, 2))
    animation.damping = CGFloat(4 * Double.pi * policy.springDamping / policy.springResponse)
    animation.fromValue = from
    animation.toValue = to
    animation.duration = animation.settlingDuration
    layer.add(animation, forKey: keyPath)
  }

  /// Opacidade não usa mola: passar de 1 e voltar não significa nada.
  private func fade(_ layer: CALayer, to value: Float) {
    let current = layer.presentation()?.opacity ?? layer.opacity
    layer.removeAnimation(forKey: "opacity")
    layer.opacity = value
    guard policy.springResponse > 0, current != value else { return }
    let animation = CABasicAnimation(keyPath: "opacity")
    animation.fromValue = current
    animation.toValue = value
    animation.duration = policy.springResponse
    animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    layer.add(animation, forKey: "opacity")
  }
}

/// O que dá para fazer com a faixa sem gesto nenhum (FR-021).
enum BandAction {
  /// Um passo no eixo livre: +1 para baixo, ou para a direita.
  case move(Int)
  case thicken
  case thin
  case flip
  case center
  case switchOff
}

/// Quem executa o que o VoiceOver pede à faixa — a `PreviewView`.
protocol BandAccessibilityHost: AnyObject {
  var currentBand: Band? { get }
  var bandImageRect: CGRect { get }
  func performBandAction(_ action: BandAction)
}

/// A faixa para o VoiceOver (FR-021, R25): um elemento ajustável — deslizar
/// para cima ou para baixo a move um passo de `minThickness` — com as ações
/// virar, engrossar, afinar, voltar ao centro e desligar.
///
/// Tudo é lido na hora, do estado da faixa: o elemento não guarda nada que um
/// gesto possa deixar para trás.
final class BandAccessibilityElement: UIAccessibilityElement {
  weak var host: BandAccessibilityHost?

  override var accessibilityLabel: String? {
    get { host?.currentBand?.mode == .vertical ? "Faixa vertical" : "Faixa horizontal" }
    set {}
  }

  override var accessibilityValue: String? {
    get {
      guard let band = host?.currentBand, band.mode != .off else { return nil }
      let from = band.mode == .vertical ? "da esquerda" : "do topo"
      return "\(Self.percent(band.center)) \(from), espessura \(Self.percent(band.thickness))"
    }
    set {}
  }

  override var accessibilityTraits: UIAccessibilityTraits {
    get { .adjustable }
    set {}
  }

  override var accessibilityFrameInContainerSpace: CGRect {
    get {
      guard let host, let band = host.currentBand, band.mode != .off else { return .zero }
      return band.rect(in: host.bandImageRect)
    }
    set {}
  }

  override var accessibilityCustomActions: [UIAccessibilityCustomAction]? {
    get {
      let actions: [(name: String, action: BandAction)] = [
        ("Virar", .flip), ("Engrossar", .thicken), ("Afinar", .thin),
        ("Voltar ao centro", .center), ("Desligar", .switchOff),
      ]
      return actions.map { entry in
        UIAccessibilityCustomAction(name: entry.name) { [weak self] _ in
          self?.host?.performBandAction(entry.action)
          return true
        }
      }
    }
    set {}
  }

  override func accessibilityIncrement() {
    host?.performBandAction(.move(1))
  }

  override func accessibilityDecrement() {
    host?.performBandAction(.move(-1))
  }

  private static func percent(_ value: Double) -> String {
    "\(Int((value * 100).rounded()))%"
  }
}

/// Retorno tátil nos encaixes (FR-016, R24).
///
/// Disparado no nativo, onde o evento nasce: sem ida e volta pela ponte, o
/// toque na mão cai no mesmo quadro do evento.
final class BandFeedback {
  var enabled = false
  private let selection = UISelectionFeedbackGenerator()
  private let impact = UIImpactFeedbackGenerator(style: .light)

  /// No começo do gesto, para o primeiro toque não atrasar.
  func prepare() {
    guard enabled else { return }
    selection.prepare()
    impact.prepare()
  }

  /// Virar, ligar, desligar, voltar ao centro.
  func changed() {
    guard enabled else { return }
    selection.selectionChanged()
  }

  /// Encostar num limite.
  func limit() {
    guard enabled else { return }
    impact.impactOccurred()
  }
}
