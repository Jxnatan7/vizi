import AVFoundation
import CoreMedia
import CoreVideo
import ExpoModulesCore
import UIKit

/// Mostra **o buffer transformado**, não a câmera crua.
///
/// É decisão de engenharia, não de estética: se os frames chegarem
/// rotacionados, ou se a transformação não bater com a geometria do dataset, o
/// modelo degrada em silêncio. Vendo o que ele recebe, o erro aparece em um
/// segundo em vez de virar uma tarde de investigação (R9).
final class PreviewView: ExpoView {
  private let displayLayer = AVSampleBufferDisplayLayer()
  private var formatDescription: CMVideoFormatDescription?

  /// O overlay desenha no relógio do display, lendo o último resultado
  /// publicado — nunca esperando um novo (princípio I).
  let overlay = OverlayRenderer()

  /// A transição e o estado de resultado. A view não troca de tela: ela se
  /// transforma no resultado (plano, "Structure Decision").
  private(set) lazy var result = ResultRenderer(host: self)

  /// Durante a transição, o overlay vive dentro do cartão que se aproxima.
  private var overlayLent = false

  /// As divisões entre livros sobre o resultado (FR-008).
  ///
  /// Fica por baixo da transição, que é acrescentada depois e cobre a view
  /// inteira: as divisões só aparecem quando ela termina e se esconde.
  private let dividerLayer = CAShapeLayer()
  private var dividerShelves: [Rectify.Shelf] = []
  private var dividerImageSize = CGSize.zero

  /// Estilo das camadas do resultado. Chega pelo `PreviewSink`, como o do
  /// overlay.
  var resultStyle = OverlayStyle() { didSet { drawDividers() } }

  /// A faixa de interesse (spec 005): desenho e gesto moram aqui, como a
  /// transição — o que anda no ritmo do dedo não passa pelo React.
  let bandRenderer = BandRenderer()
  private lazy var bandGesture: BandGestureRecognizer = {
    let recognizer = BandGestureRecognizer()
    recognizer.host = self
    return recognizer
  }()
  /// Dois toques dentro da faixa: de volta ao centro e à espessura padrão
  /// (FR-013). O reconhecedor da faixa só começa quando o dedo anda, então os
  /// toques chegam aqui inteiros.
  private lazy var bandDoubleTap: UITapGestureRecognizer = {
    let recognizer = UITapGestureRecognizer(target: self, action: #selector(bandDoubleTapped(_:)))
    recognizer.numberOfTapsRequired = 2
    return recognizer
  }()
  /// A faixa para o VoiceOver (FR-021, R25).
  private lazy var bandAccessibility: BandAccessibilityElement = {
    let element = BandAccessibilityElement(accessibilityContainer: self)
    element.host = self
    return element
  }()

  /// O estado da faixa. Chega pelo `PreviewSink`, como o `store`.
  ///
  /// Só redesenha quando o modelo muda de fato: o `configure` do sink roda a
  /// cada troca de estilo, e reaplicar ali cortaria uma mola no meio.
  var bandModel: BandModel? {
    didSet { if bandModel !== oldValue { applyBand(animated: false) } }
  }
  /// Muda a cada troca de modo e a cada gesto. Uma mola só avisa o JavaScript
  /// ao chegar se ninguém a substituiu no caminho — como o `epoch` da
  /// `ResultRenderer`.
  private var bandTransition: UInt64 = 0

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    displayLayer.videoGravity = .resizeAspect
    layer.addSublayer(displayLayer)
    // O escurecimento fica abaixo do overlay: livro que conta aparece aceso,
    // mesmo onde passa da borda da faixa.
    layer.addSublayer(bandRenderer.dimLayer)
    overlay.attach(to: layer)
    dividerLayer.fillColor = nil
    dividerLayer.lineCap = .round
    layer.addSublayer(dividerLayer)
    // Bordas, alças e contagem por cima de tudo — menos da transição, que é
    // acrescentada depois.
    for control in [bandRenderer.edgeLayer, bandRenderer.handleLayer,
                    bandRenderer.countPill] as [CALayer] {
      layer.addSublayer(control)
    }
    overlay.onMembers = { [weak self] count in self?.bandRenderer.updateCount(count) }
    // Sem isto a view só recebe o primeiro dedo, e a pinça nunca começa.
    isMultipleTouchEnabled = true
    addGestureRecognizer(bandGesture)
    addGestureRecognizer(bandDoubleTap)
    backgroundColor = .black
    PreviewSink.shared.view = self
  }

  deinit {
    overlay.stop()
    if PreviewSink.shared.view === self { PreviewSink.shared.view = nil }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    displayLayer.frame = bounds
    // Emprestado ao cartão, o overlay está no espaço dele, não no da view.
    if !overlayLent { overlay.layout(bounds) }
    dividerLayer.frame = bounds
    drawDividers()
    let scale = max(1, traitCollection.displayScale)
    bandRenderer.layout(image: bandImageRect, bounds: bounds, scale: scale)
    PreviewSink.shared.stagePixels = CGSize(
      width: bounds.width * scale, height: bounds.height * scale)
  }

  // MARK: - Faixa de interesse

  /// Leva o desenho ao estado do modelo: no começo da sessão, ou quando o modo
  /// muda por fora do gesto.
  func applyBand(animated: Bool) {
    guard let bandModel else { return }
    let snapshot = bandModel.read()
    bandRenderer.configure(policy: snapshot.policy)
    bandRenderer.apply(snapshot.band, animated: animated)
  }

  /// Uma troca que não vem do arrasto — a cápsula, dois toques, o VoiceOver:
  /// a faixa vai numa mola, com retorno tátil, e quem espelha só fica sabendo
  /// quando ela chega — nunca no meio do caminho (contrato da 005).
  ///
  /// O modelo já está no destino; isto só anima e avisa.
  func transitionBand(to band: Band) {
    bandTransition &+= 1
    let token = bandTransition
    bandRenderer.feedback.changed()
    bandRenderer.apply(band, animated: true) { [weak self] in
      guard let self, self.bandTransition == token else { return }
      self.bandModel?.commit()
    }
  }

  /// Um gesto em curso termina aqui, com a faixa dentro dos limites. Quem
  /// muda a faixa por fora chama antes de ler o estado: senão o gesto
  /// escreveria por cima da troca no quadro seguinte.
  func finishBandGesture() {
    bandGesture.finish()
  }

  /// Some na captura e no resultado (FR-020), e os gestos desligam junto:
  /// mexer na faixa ali mudaria um estado que a captura já leu.
  func setBandVisible(_ visible: Bool, animated: Bool) {
    if !visible { bandGesture.finish() }
    bandRenderer.setVisible(visible, animated: animated)
    bandGesture.isEnabled = visible
    bandDoubleTap.isEnabled = visible
  }

  @objc private func bandDoubleTapped(_ recognizer: UITapGestureRecognizer) {
    guard recognizer.state == .ended, let bandModel else { return }
    let (band, policy, _) = bandModel.read()
    guard band.mode != .off,
          band.rect(in: bandImageRect).contains(recognizer.location(in: self)) else { return }
    setBand(Band(mode: band.mode, center: 0.5, thickness: policy.defaultThickness))
  }

  /// Uma faixa nova, de uma vez: escreve e anima como uma troca de modo.
  private func setBand(_ band: Band) {
    bandModel?.write(band)
    transitionBand(to: band)
  }

  /// Só a faixa ligada e em cena é um elemento. Desligada, quem a religa é a
  /// cápsula.
  override var accessibilityElements: [Any]? {
    get {
      guard bandGesture.isEnabled, let band = bandModel?.read().band,
            band.mode != .off else { return [] }
      return [bandAccessibility]
    }
    set {}
  }

  /// A volta do resultado terminou: a faixa reaparece como estava (R27).
  func resultDidEnd() {
    setBandVisible(true, animated: true)
  }

  // MARK: - Divisões

  /// - Parameters:
  ///   - shelves: fileiras com divisões e bandas normalizadas no resultado
  ///   - imageSize: a imagem exibida, de onde sai o retângulo em que ela cabe
  func showDividers(_ shelves: [Rectify.Shelf], imageSize: CGSize) {
    dividerShelves = shelves
    dividerImageSize = imageSize
    drawDividers()
  }

  func clearDividers() {
    dividerShelves = []
    drawDividers()
  }

  /// Linhas verticais, cada uma na banda da sua fileira.
  ///
  /// O retângulo é o mesmo do `resizeAspect` da camada de vídeo: é ali que a
  /// imagem endireitada aparece, e as divisões estão normalizadas nela.
  private func drawDividers() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    defer { CATransaction.commit() }

    guard resultStyle.showDividers, !dividerShelves.isEmpty,
          dividerImageSize.width > 0, dividerImageSize.height > 0 else {
      dividerLayer.path = nil
      return
    }

    let rect = AVMakeRect(aspectRatio: dividerImageSize, insideRect: bounds)
    let path = CGMutablePath()
    for shelf in dividerShelves {
      let top = rect.minY + CGFloat(shelf.top) * rect.height
      let bottom = rect.minY + CGFloat(shelf.bottom) * rect.height
      guard bottom > top else { continue }
      for divider in shelf.dividers {
        let x = rect.minX + CGFloat(divider) * rect.width
        path.move(to: CGPoint(x: x, y: top))
        path.addLine(to: CGPoint(x: x, y: bottom))
      }
    }
    dividerLayer.path = path
    dividerLayer.strokeColor = resultStyle.dividerColor
    dividerLayer.lineWidth = resultStyle.dividerWidth
  }

  /// O overlay entra no cartão da transição e se aproxima junto com a imagem.
  func lendOverlay(to card: CALayer, origin: CGPoint) {
    guard !overlayLent else { return }
    overlayLent = true
    overlay.isHeld = true
    for layer in [overlay.maskLayer, overlay.boxLayer] {
      let frame = layer.frame.offsetBy(dx: -origin.x, dy: -origin.y)
      card.addSublayer(layer)
      layer.frame = frame
    }
  }

  /// Devolve o overlay à view, por baixo da transição, e redesenha na hora.
  ///
  /// Acima do escurecimento da faixa, não do vídeo: por baixo dele, as caixas
  /// dos livros que contam voltariam apagadas depois da primeira captura.
  func reclaimOverlay() {
    guard overlayLent else { return }
    overlayLent = false
    overlay.attach(to: layer, above: bandRenderer.dimLayer)
    overlay.layout(bounds)
    overlay.resumeDrawing()
  }

  /// Chamado da fila da câmera, não da thread de interface.
  func enqueue(_ pixelBuffer: CVPixelBuffer) {
    if formatDescription == nil
        || !CMVideoFormatDescriptionMatchesImageBuffer(formatDescription!, imageBuffer: pixelBuffer) {
      var created: CMVideoFormatDescription?
      CMVideoFormatDescriptionCreateForImageBuffer(
        allocator: kCFAllocatorDefault, imageBuffer: pixelBuffer, formatDescriptionOut: &created)
      formatDescription = created
    }
    guard let formatDescription else { return }

    var timing = CMSampleTimingInfo(
      duration: .invalid, presentationTimeStamp: .zero, decodeTimeStamp: .invalid)
    var sample: CMSampleBuffer?
    guard CMSampleBufferCreateReadyWithImageBuffer(
      allocator: kCFAllocatorDefault,
      imageBuffer: pixelBuffer,
      formatDescription: formatDescription,
      sampleTiming: &timing,
      sampleBufferOut: &sample) == noErr, let sample else { return }

    // Sem timebase configurado, exibir imediatamente é o comportamento certo:
    // o preview é ao vivo, não uma reprodução com relógio próprio.
    if let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: true),
       CFArrayGetCount(attachments) > 0 {
      let dict = unsafeBitCast(CFArrayGetValueAtIndex(attachments, 0), to: CFMutableDictionary.self)
      CFDictionarySetValue(
        dict,
        Unmanaged.passUnretained(kCMSampleAttachmentKey_DisplayImmediately).toOpaque(),
        Unmanaged.passUnretained(kCFBooleanTrue).toOpaque())
    }

    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      if self.displayLayer.status == .failed { self.displayLayer.flush() }
      self.displayLayer.enqueue(sample)
    }
  }
}

extension PreviewView: BandGestureHost {
  /// O quadrado da imagem canônica dentro da view — o mesmo que o
  /// `resizeAspect` da camada de vídeo mostra, e onde a faixa vive.
  var bandImageRect: CGRect {
    AVMakeRect(aspectRatio: CGSize(width: 1, height: 1), insideRect: bounds)
  }

  var bandPolicy: BandPolicy { bandModel?.read().policy ?? .unset }

  var currentBand: Band? { bandModel?.read().band }

  func beginBandGesture() -> Band? {
    guard bandModel != nil else { return nil }
    // O gesto corta a mola de uma troca de modo: quem avisa agora é o fim dele.
    bandTransition &+= 1
    bandRenderer.feedback.prepare()
    return bandRenderer.freezeAtPresentation()
  }

  func presentedBand() -> Band {
    bandRenderer.freezeAtPresentation()
  }

  func moveBand(to band: Band) {
    bandModel?.write(band)
    bandRenderer.apply(band, animated: false)
  }

  func springBand(to band: Band) {
    bandModel?.write(band)
    bandRenderer.feedback.changed()
    bandRenderer.apply(band, animated: true)
  }

  func switchOffBand(remembering previous: Band) {
    guard let off = bandModel?.switchOff(remembering: previous) else { return }
    bandRenderer.feedback.changed()
    bandRenderer.apply(off, animated: true)
  }

  func bandTouchedLimit() {
    bandRenderer.feedback.limit()
  }

  func endBandGesture(settleTo final: Band?) {
    // Além de um limite, a faixa volta numa mola (FR-014). Quem espelha fica
    // sabendo do destino já: é uma mudança discreta, não um quadro.
    if let final, final != bandRenderer.band {
      bandModel?.write(final)
      bandRenderer.apply(final, animated: true)
    }
    bandModel?.commit()
  }
}

extension PreviewView: BandAccessibilityHost {
  func performBandAction(_ action: BandAction) {
    guard let bandModel else { return }
    bandGesture.finish()
    let (band, policy, _) = bandModel.read()
    guard band.mode != .off else { return }
    // Um passo é a espessura mínima: pequeno o bastante para acertar uma
    // prateleira, grande o bastante para não precisar de vinte.
    let step = policy.minThickness
    switch action {
    case .move(let direction):
      setBand(Band(mode: band.mode, center: band.center + Double(direction) * step,
                   thickness: band.thickness).limited(minThickness: step))
    case .thicken:
      setBand(Band(mode: band.mode, center: band.center, thickness: band.thickness + step)
        .limited(minThickness: step))
    case .thin:
      setBand(Band(mode: band.mode, center: band.center, thickness: band.thickness - step)
        .limited(minThickness: step))
    case .center:
      setBand(Band(mode: band.mode, center: 0.5, thickness: policy.defaultThickness))
    case .flip:
      if let change = bandModel.setMode(band.mode == .horizontal ? .vertical : .horizontal) {
        transitionBand(to: change.to)
      }
    case .switchOff:
      if let change = bandModel.setMode(.off) { transitionBand(to: change.to) }
    }
    // Ao ajustar, o VoiceOver já relê o valor sozinho. Depois de uma ação, ele
    // relê a faixa onde ela foi parar — ou solta o foco, se ela saiu de cena.
    if case .move = action { return }
    let focus: Any? = bandModel.read().band.mode == .off ? nil : bandAccessibility
    UIAccessibility.post(notification: .layoutChanged, argument: focus)
  }
}

/// Ponte entre a fila da câmera e a view, que o React monta e desmonta quando
/// quiser.
///
/// **Guarda a configuração, em vez de empurrá-la.** A view nasce depois de
/// `startSession` — o JSX só a monta quando a sessão responde. Empurrar
/// configuração no start encontrava `view == nil` e falhava em silêncio.
/// Agora quem se configura é a view, ao nascer, e o sink é a fonte da verdade.
final class PreviewSink {
  static let shared = PreviewSink()
  private init() {}

  weak var view: PreviewView? { didSet { configure() } }
  var store: ResultStore? { didSet { configure() } }
  /// A faixa de interesse. Guardada como o `store`: a view nasce depois da
  /// sessão e se configura com ela ao nascer.
  var band: BandModel? { didSet { configure() } }
  var imageSide: CGFloat = 640 { didSet { configure() } }
  var style = OverlayStyle() { didSet { configure() } }
  var active = false { didSet { configure() } }

  /// Congela a tela no instante do toque, antes de qualquer reconfiguração.
  ///
  /// Não limpa nada: a última imagem enfileirada continua visível. É o que
  /// permite a animação começar imediatamente, sem esperar a foto (FR-009).
  var frozen = false

  private let frameLock = NSLock()
  /// O último frame exibido. É dele que a transição parte.
  private var lastFrame: CVPixelBuffer?
  private var _stagePixels = CGSize.zero

  /// Tamanho da view em pixels. A imagem que a transição anima é reduzida a
  /// isto: o resultado inteiro seriam dezenas de megabytes numa camada, para
  /// desenhar algo do tamanho da tela.
  var stagePixels: CGSize {
    get { frameLock.lock(); defer { frameLock.unlock() }; return _stagePixels }
    set { frameLock.lock(); _stagePixels = newValue; frameLock.unlock() }
  }

  /// Diagnóstico: sem console no aparelho, saber se o overlay está ligado e
  /// quantas instâncias ele desenhou é a diferença entre ver e adivinhar.
  var isAttached: Bool { view != nil }
  var lastDrawMs: Double { view?.overlay.lastDrawMs ?? -1 }
  var lastDrawnCount: Int { view?.overlay.lastDrawnCount ?? -1 }

  func push(_ buffer: CVPixelBuffer) {
    guard !frozen else { return }
    frameLock.lock()
    lastFrame = buffer
    frameLock.unlock()
    view?.enqueue(buffer)
  }

  /// Congela e devolve o frame que ficou na tela.
  func freeze() -> CVPixelBuffer? {
    frozen = true
    frameLock.lock(); defer { frameLock.unlock() }
    return lastFrame
  }

  /// Executa na view, na thread de interface, se ela existir.
  ///
  /// A captura roda fora da thread de interface e a view pode nem ter
  /// nascido; quem chama não precisa saber de nenhuma das duas coisas.
  func onView(_ body: @escaping (PreviewView) -> Void) {
    DispatchQueue.main.async { [weak self] in
      guard let view = self?.view else { return }
      body(view)
    }
  }

  /// Exibe uma imagem parada, ignorando o congelamento.
  ///
  /// É como a imagem canônica da foto substitui o frame de vídeo congelado.
  /// Sem isto, as detecções da foto ficavam desenhadas sobre a imagem de outro
  /// momento — duas imagens na tela ao mesmo tempo.
  func showStill(_ buffer: CVPixelBuffer) {
    view?.enqueue(buffer)
  }

  private func configure() {
    guard Thread.isMainThread else {
      DispatchQueue.main.async { [weak self] in self?.configure() }
      return
    }
    guard let view else { return }
    view.overlay.store = store
    view.overlay.imageSide = imageSide
    view.overlay.style = style
    view.overlay.band = band
    view.resultStyle = style
    view.bandRenderer.style = style
    view.bandModel = band
    if active { view.overlay.start() } else { view.overlay.stop() }
  }
}
