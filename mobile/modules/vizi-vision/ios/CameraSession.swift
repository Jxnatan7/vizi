import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

protocol CameraSessionDelegate: AnyObject {
  func cameraSession(_ session: CameraSession, didOutput buffer: CVPixelBuffer, at time: CMTime)
}

/// Captura própria, em vez de biblioteca de terceiros.
///
/// A razão é o princípio II: aqui o frame nasce e morre em Swift. Um frame
/// processor de JavaScript marsharia o frame para um worklet, que é exatamente
/// a travessia que a constituição proíbe.
final class CameraSession: NSObject {
  enum CameraError: LocalizedError {
    case permissionDenied
    case noDevice
    case noSuitableFormat(minSide: Int)
    case cannotAddInput
    case cannotAddOutput

    var errorDescription: String? {
      switch self {
      case .permissionDenied:
        return "Permissão de câmera negada. Conceda em Ajustes → vizi → Câmera."
      case .noDevice:
        return "Câmera traseira não encontrada neste aparelho."
      case .noSuitableFormat(let s):
        return "Nenhum formato de captura com os dois lados ≥ \(s) px."
      case .cannotAddInput:
        return "Não foi possível adicionar a entrada de vídeo à sessão."
      case .cannotAddOutput:
        return "Não foi possível adicionar a saída de vídeo à sessão."
      }
    }
  }

  weak var delegate: CameraSessionDelegate?

  private let session = AVCaptureSession()
  private let output = AVCaptureVideoDataOutput()
  /// Fila dedicada: a entrega de frames nunca toca a thread de interface.
  private let queue = DispatchQueue(label: "com.jxnatan7.vizi.camera", qos: .userInitiated)

  private(set) var captureWidth = 0
  private(set) var captureHeight = 0
  private(set) var maxFrameRate: Double = 0

  // MARK: - Permissão

  static func hasPermission() -> Bool {
    AVCaptureDevice.authorizationStatus(for: .video) == .authorized
  }

  static func requestPermission() async -> Bool {
    await AVCaptureDevice.requestAccess(for: .video)
  }

  // MARK: - Configuração

  /// Escolhe o MENOR formato cujos dois lados passem de `minSide` — R6.
  ///
  /// Capturar em 4K para reduzir a 640×640 desperdiça banda de memória e
  /// energia, e energia é justamente o que este marco mede.
  func configure(minSide: Int = 640) throws {
    guard Self.hasPermission() else { throw CameraError.permissionDenied }
    guard let device = AVCaptureDevice.default(
      .builtInWideAngleCamera, for: .video, position: .back)
    else { throw CameraError.noDevice }

    let candidates = device.formats.filter { format in
      let d = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
      return Int(d.width) >= minSide && Int(d.height) >= minSide
    }
    guard let chosen = candidates.min(by: { a, b in
      let da = CMVideoFormatDescriptionGetDimensions(a.formatDescription)
      let db = CMVideoFormatDescriptionGetDimensions(b.formatDescription)
      return Int(da.width) * Int(da.height) < Int(db.width) * Int(db.height)
    }) else { throw CameraError.noSuitableFormat(minSide: minSide) }

    session.beginConfiguration()
    // inputPriority: mandamos no formato, a sessão não sobrepõe com um preset.
    session.sessionPreset = .inputPriority

    try device.lockForConfiguration()
    device.activeFormat = chosen
    device.unlockForConfiguration()

    let dims = CMVideoFormatDescriptionGetDimensions(chosen.formatDescription)
    captureWidth = Int(dims.width)
    captureHeight = Int(dims.height)
    maxFrameRate = chosen.videoSupportedFrameRateRanges.map(\.maxFrameRate).max() ?? 0

    let input = try AVCaptureDeviceInput(device: device)
    guard session.canAddInput(input) else {
      session.commitConfiguration()
      throw CameraError.cannotAddInput
    }
    session.addInput(input)

    output.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
    ]
    // Descarte no nível da AVFoundation. O FrameGate cuida do estágio seguinte.
    output.alwaysDiscardsLateVideoFrames = true
    output.setSampleBufferDelegate(self, queue: queue)

    guard session.canAddOutput(output) else {
      session.commitConfiguration()
      throw CameraError.cannotAddOutput
    }
    session.addOutput(output)

    // Orientação — R9. Sem isto o buffer chega deitado com o aparelho em
    // retrato, e o modelo vê a cena de lado: degradação silenciosa.
    if let connection = output.connection(with: .video) {
      if #available(iOS 17.0, *) {
        if connection.isVideoRotationAngleSupported(90) {
          connection.videoRotationAngle = 90
        }
      }
    }

    session.commitConfiguration()
  }

  func start() {
    queue.async { [weak self] in
      guard let self, !self.session.isRunning else { return }
      self.session.startRunning()
    }
  }

  func stop() {
    queue.async { [weak self] in
      guard let self, self.session.isRunning else { return }
      self.session.stopRunning()
    }
  }

  var isRunning: Bool { session.isRunning }
}

extension CameraSession: AVCaptureVideoDataOutputSampleBufferDelegate {
  func captureOutput(
    _ output: AVCaptureOutput,
    didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
    delegate?.cameraSession(
      self, didOutput: buffer,
      at: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
  }
}
