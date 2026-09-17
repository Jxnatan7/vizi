import AVFoundation
import CoreVideo
import Foundation

/// Foto em resolução máxima, com troca temporária de formato.
///
/// A sessão ao vivo roda em 1024×768 — o menor formato que serve, escolhido no
/// marco 2 para economizar energia. Mas a resolução da foto é **limitada pelo
/// formato ativo**, então tirar uma foto de 12 MP exige trocar de formato,
/// capturar, e voltar.
///
/// A troca interrompe a entrega de frames por alguns décimos de segundo. É o
/// custo aceito: a tela já está congelada e a animação já começou (FR-009).
final class PhotoCapture: NSObject {
  enum PhotoError: LocalizedError {
    case outputUnavailable
    case noUncompressedFormat
    case noPixelBuffer
    case failed(String)

    var errorDescription: String? {
      switch self {
      case .outputUnavailable: return "A saída de foto não pôde ser adicionada à sessão."
      case .noUncompressedFormat: return "A câmera não oferece foto sem compressão neste formato."
      case .noPixelBuffer: return "A foto chegou sem dados de imagem."
      case .failed(let m): return "Falha ao capturar a foto: \(m)"
      }
    }
  }

  private let output = AVCapturePhotoOutput()
  private var continuation: CheckedContinuation<CVPixelBuffer, Error>?

  /// Adicionada na configuração da sessão, não na captura: adicionar saída com
  /// a sessão rodando causa outra reconfiguração, e já há uma no caminho.
  func attach(to session: AVCaptureSession) throws {
    guard session.canAddOutput(output) else { throw PhotoError.outputUnavailable }
    session.addOutput(output)
    output.maxPhotoQualityPrioritization = .quality
  }

  /// O formato com a maior dimensão de foto que o dispositivo oferece.
  private func bestPhotoFormat(for device: AVCaptureDevice) -> AVCaptureDevice.Format? {
    device.formats.max { a, b in
      let da = a.supportedMaxPhotoDimensions.map { Int($0.width) * Int($0.height) }.max() ?? 0
      let db = b.supportedMaxPhotoDimensions.map { Int($0.width) * Int($0.height) }.max() ?? 0
      return da < db
    }
  }

  func capture(device: AVCaptureDevice) async throws -> (buffer: CVPixelBuffer, elapsedMs: Double) {
    let started = CFAbsoluteTimeGetCurrent()
    let originalFormat = device.activeFormat

    // Restaura o formato ao vivo aconteça o que acontecer: sair daqui com o
    // formato de foto ativo degradaria a sessão para sempre.
    defer {
      try? device.lockForConfiguration()
      device.activeFormat = originalFormat
      device.unlockForConfiguration()
    }

    if let photoFormat = bestPhotoFormat(for: device), photoFormat != originalFormat {
      try device.lockForConfiguration()
      device.activeFormat = photoFormat
      device.unlockForConfiguration()
    }

    // Sempre, e não só quando o formato troca: sem isto a captura sem
    // compressão sai no menor tamanho que o formato oferece — foi o que
    // produziu os 192×144.
    guard let dimensions = device.activeFormat.supportedMaxPhotoDimensions
      .max(by: { Int($0.width) * Int($0.height) < Int($1.width) * Int($1.height) })
    else { throw PhotoError.outputUnavailable }
    output.maxPhotoDimensions = dimensions

    // A conexão da foto é OUTRA, e não herda a rotação da conexão de vídeo.
    // Sem isto a foto chega deitada, o modelo vê os livros de lado, e as
    // caixas saem giradas 90° em relação à imagem.
    if let connection = output.connection(with: .video) {
      if #available(iOS 17.0, *), connection.isVideoRotationAngleSupported(90) {
        connection.videoRotationAngle = 90
      }
    }

    guard output.availablePhotoPixelFormatTypes.contains(kCVPixelFormatType_32BGRA) else {
      throw PhotoError.noUncompressedFormat
    }

    // As dimensões vão explícitas no pedido. Deixar implícito foi o que deu
    // errado antes.
    let settings = AVCapturePhotoSettings(format: [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
      kCVPixelBufferWidthKey as String: Int(dimensions.width),
      kCVPixelBufferHeightKey as String: Int(dimensions.height),
    ])
    settings.photoQualityPrioritization = .quality
    settings.maxPhotoDimensions = dimensions

    let buffer = try await withCheckedThrowingContinuation { (c: CheckedContinuation<CVPixelBuffer, Error>) in
      continuation = c
      output.capturePhoto(with: settings, delegate: self)
    }

    return (buffer, (CFAbsoluteTimeGetCurrent() - started) * 1000)
  }

extension PhotoCapture: AVCapturePhotoCaptureDelegate {
  func photoOutput(
    _ output: AVCapturePhotoOutput,
    didFinishProcessingPhoto photo: AVCapturePhoto,
    error: Error?
  ) {
    let c = continuation
    continuation = nil

    if let error {
      c?.resume(throwing: PhotoError.failed(error.localizedDescription))
      return
    }
    guard let buffer = photo.pixelBuffer else {
      c?.resume(throwing: PhotoError.noPixelBuffer)
      return
    }
    c?.resume(returning: buffer)
  }
}
