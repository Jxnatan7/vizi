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

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    displayLayer.videoGravity = .resizeAspect
    layer.addSublayer(displayLayer)
    overlay.attach(to: layer)
    dividerLayer.fillColor = nil
    dividerLayer.lineCap = .round
    layer.addSublayer(dividerLayer)
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
    PreviewSink.shared.stagePixels = CGSize(
      width: bounds.width * scale, height: bounds.height * scale)
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
  func reclaimOverlay() {
    guard overlayLent else { return }
    overlayLent = false
    overlay.attach(to: layer, above: displayLayer)
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
    view.resultStyle = style
    if active { view.overlay.start() } else { view.overlay.stop() }
  }
}
