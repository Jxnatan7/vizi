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

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    displayLayer.videoGravity = .resizeAspect
    layer.addSublayer(displayLayer)
    overlay.attach(to: layer)
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
    overlay.layout(bounds)
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

  /// Diagnóstico: sem console no aparelho, saber se o overlay está ligado e
  /// quantas instâncias ele desenhou é a diferença entre ver e adivinhar.
  var isAttached: Bool { view != nil }
  var lastDrawMs: Double { view?.overlay.lastDrawMs ?? -1 }
  var lastDrawnCount: Int { view?.overlay.lastDrawnCount ?? -1 }

  func push(_ buffer: CVPixelBuffer) {
    guard !frozen else { return }
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
    if active { view.overlay.start() } else { view.overlay.stop() }
  }
}
