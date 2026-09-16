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

  required init(appContext: AppContext? = nil) {
    super.init(appContext: appContext)
    displayLayer.videoGravity = .resizeAspect
    layer.addSublayer(displayLayer)
    backgroundColor = .black
    PreviewSink.shared.view = self
  }

  deinit {
    if PreviewSink.shared.view === self { PreviewSink.shared.view = nil }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    displayLayer.frame = bounds
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
/// quiser. Referência fraca: a view manda no próprio ciclo de vida.
final class PreviewSink {
  static let shared = PreviewSink()
  weak var view: PreviewView?
  private init() {}

  func push(_ buffer: CVPixelBuffer) {
    view?.enqueue(buffer)
  }
}
