import Accelerate
import CoreGraphics
import CoreML
import CoreVideo
import Foundation
import ImageIO
import VideoToolbox

/// A escrita da coleta (spec 007): imagens, protótipos, JSON e o item inteiro
/// ou nada.
///
/// Tudo aqui roda na fila da coleta, de prioridade utilitária, e **pela CPU**:
/// a gravação começa enquanto a transição do resultado anima, e um JPEG de
/// 12 MP pela GPU disputaria a animação (R40).
enum CollectionWriter {

  enum WriteError: LocalizedError {
    case image(String)
    case protos(String)
    case json(String)
    case folder(String)

    var errorDescription: String? {
      switch self {
      case .image(let m): return "Não foi possível gravar a imagem: \(m)"
      case .protos(let m): return "Não foi possível gravar os protótipos: \(m)"
      case .json(let m): return "Não foi possível gravar o JSON: \(m)"
      case .folder(let m): return "Não foi possível montar a pasta do item: \(m)"
      }
    }
  }

  struct Written {
    var file: String
    var width: Int
    var height: Int
    var bytes: Int

    var dictionary: [String: Any] {
      ["file": file, "width": width, "height": height]
    }
  }

  // MARK: - Imagens

  /// JPEG pela CPU: `CGImage` pelo VideoToolbox, escrito pelo ImageIO.
  ///
  /// - Parameter upright: gira 90° no sentido horário a imagem mais larga que
  ///   alta — a mesma regra do `FrameTransform`, que a leva ao retrato com
  ///   `.oriented(.right)`. A imagem sai em retrato **nos próprios pixels**,
  ///   sem EXIF de orientação, que nem todo leitor respeita.
  static func writeJPEG(
    _ buffer: CVPixelBuffer, named name: String, in folder: URL,
    quality: Double, upright: Bool
  ) throws -> Written {
    var source = buffer
    if upright, CVPixelBufferGetWidth(buffer) > CVPixelBufferGetHeight(buffer) {
      source = try rotatedClockwise(buffer)
    }

    var image: CGImage?
    let status = VTCreateCGImageFromCVPixelBuffer(source, options: nil, imageOut: &image)
    guard status == noErr, let image else {
      throw WriteError.image("\(name): VideoToolbox \(status)")
    }

    let url = folder.appendingPathComponent(name)
    guard let destination = CGImageDestinationCreateWithURL(
      url as CFURL, "public.jpeg" as CFString, 1, nil) else {
      throw WriteError.image("\(name): destino")
    }
    let options = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
    CGImageDestinationAddImage(destination, image, options)
    guard CGImageDestinationFinalize(destination) else {
      throw WriteError.image("\(name): o aparelho pode estar sem espaço")
    }
    return Written(file: name, width: image.width, height: image.height, bytes: size(of: url))
  }

  /// 90° no sentido horário, com o vImage.
  private static func rotatedClockwise(_ source: CVPixelBuffer) throws -> CVPixelBuffer {
    guard CVPixelBufferGetPixelFormatType(source) == kCVPixelFormatType_32BGRA else {
      throw WriteError.image("só BGRA gira")
    }
    let w = CVPixelBufferGetWidth(source), h = CVPixelBufferGetHeight(source)
    var created: CVPixelBuffer?
    let attrs: [String: Any] = [kCVPixelBufferIOSurfacePropertiesKey as String: [:]]
    guard CVPixelBufferCreate(kCFAllocatorDefault, h, w, kCVPixelFormatType_32BGRA,
                              attrs as CFDictionary, &created) == kCVReturnSuccess,
          let rotated = created else {
      throw WriteError.image("sem memória para girar \(w)×\(h)")
    }

    CVPixelBufferLockBaseAddress(source, .readOnly)
    CVPixelBufferLockBaseAddress(rotated, [])
    defer {
      CVPixelBufferUnlockBaseAddress(rotated, [])
      CVPixelBufferUnlockBaseAddress(source, .readOnly)
    }
    guard let from = CVPixelBufferGetBaseAddress(source),
          let to = CVPixelBufferGetBaseAddress(rotated) else {
      throw WriteError.image("buffer sem endereço")
    }

    var src = vImage_Buffer(
      data: from, height: vImagePixelCount(h), width: vImagePixelCount(w),
      rowBytes: CVPixelBufferGetBytesPerRow(source))
    var dst = vImage_Buffer(
      data: to, height: vImagePixelCount(w), width: vImagePixelCount(h),
      rowBytes: CVPixelBufferGetBytesPerRow(rotated))
    // Exigido pela assinatura; num giro de 90° nenhum pixel fica sem origem.
    var background: [UInt8] = [0, 0, 0, 255]
    let error = vImageRotate90_ARGB8888(
      &src, &dst, UInt8(kRotate90DegreesClockwise), &background, vImage_Flags(kvImageNoFlags))
    guard error == kvImageNoError else { throw WriteError.image("vImage \(error)") }
    return rotated
  }

  // MARK: - Protótipos

  /// `[1, 32, 160, 160]` → `float16` little-endian, sem cabeçalho (R39).
  ///
  /// Respeita os `strides` do `MLMultiArray`: um tensor com preenchimento entre
  /// linhas é copiado elemento a elemento, em vez de sair embaralhado.
  static func writeProtos(_ protos: MLMultiArray, named name: String, in folder: URL) throws -> Int {
    let shape = protos.shape.map(\.intValue)
    let count = shape.reduce(1, *)
    guard count > 0 else { throw WriteError.protos("\(name): tensor vazio") }

    var half = [UInt16](repeating: 0, count: count)

    switch protos.dataType {
    case .float32:
      var floats = [Float](repeating: 0, count: count)
      protos.withUnsafeMutableBufferPointer(ofType: Float32.self) { buf, strides in
        guard let base = buf.baseAddress else { return }
        gather(UnsafePointer(base), shape: shape, strides: strides, into: &floats)
      }
      floats.withUnsafeMutableBufferPointer { f in
        half.withUnsafeMutableBufferPointer { h in
          var src = vImage_Buffer(
            data: f.baseAddress, height: 1, width: vImagePixelCount(count), rowBytes: count * 4)
          var dst = vImage_Buffer(
            data: h.baseAddress, height: 1, width: vImagePixelCount(count), rowBytes: count * 2)
          _ = vImageConvert_PlanarFtoPlanar16F(&src, &dst, vImage_Flags(kvImageNoFlags))
        }
      }
    case .float16:
      // Já em meia precisão: só copiar os bits, na ordem certa. Pelos bytes
      // crus — o acesso tipado exigiria `Float16`, que não existe em todo alvo
      // de compilação —, com o `withUnsafeBytes`, que trava o tensor quando
      // ele mora num buffer de pixel. Hoje não acontece: os protótipos saem em
      // fp32, e o `Decode` e o `MaskCompose` dependem disso.
      let strides = protos.strides.map(\.intValue)
      protos.withUnsafeBytes { raw in
        guard let base = raw.bindMemory(to: UInt16.self).baseAddress else { return }
        gather(base, shape: shape, strides: strides, into: &half)
      }
    default:
      throw WriteError.protos("\(name): tipo \(protos.dataType.rawValue) inesperado")
    }

    let url = folder.appendingPathComponent(name)
    let data = half.withUnsafeBufferPointer { Data(buffer: $0) }
    do {
      try data.write(to: url)
    } catch {
      throw WriteError.protos("\(name): \(error.localizedDescription)")
    }
    return data.count
  }

  /// Copia um tensor de quatro dimensões, com `strides` quaisquer, para a
  /// ordem C.
  private static func gather<T>(
    _ base: UnsafePointer<T>, shape: [Int], strides: [Int], into out: inout [T]
  ) {
    guard shape.count == 4, strides.count == 4 else {
      // Outra forma: só a cópia contígua faz sentido.
      for i in out.indices { out[i] = base[i] }
      return
    }
    let contiguous = [shape[1] * shape[2] * shape[3], shape[2] * shape[3], shape[3], 1]
    if strides == contiguous {
      for i in out.indices { out[i] = base[i] }
      return
    }
    var i = 0
    for a in 0..<shape[0] {
      for b in 0..<shape[1] {
        for c in 0..<shape[2] {
          let row = a * strides[0] + b * strides[1] + c * strides[2]
          for d in 0..<shape[3] {
            out[i] = base[row + d * strides[3]]
            i += 1
          }
        }
      }
    }
  }

  // MARK: - JSON

  /// Escrito com `.atomic`: arquivo temporário e troca. Um `session.json` lido
  /// no meio de uma escrita nunca sai pela metade.
  static func writeJSON(_ object: [String: Any], to url: URL) throws -> Int {
    let clean = sanitize(object)
    guard JSONSerialization.isValidJSONObject(clean) else {
      throw WriteError.json("\(url.lastPathComponent): objeto inválido")
    }
    do {
      let data = try JSONSerialization.data(
        withJSONObject: clean, options: [.prettyPrinted, .withoutEscapingSlashes])
      try data.write(to: url, options: .atomic)
      return data.count
    } catch {
      throw WriteError.json("\(url.lastPathComponent): \(error.localizedDescription)")
    }
  }

  /// Uma linha de JSON, anexada. Para a telemetria, que cresce a ~2 Hz.
  static func appendLine(_ object: [String: Any], to url: URL) {
    let clean = sanitize(object)
    guard JSONSerialization.isValidJSONObject(clean),
          var data = try? JSONSerialization.data(withJSONObject: clean, options: [.withoutEscapingSlashes])
    else { return }
    data.append(0x0A)
    if let handle = try? FileHandle(forWritingTo: url) {
      defer { try? handle.close() }
      _ = try? handle.seekToEnd()
      try? handle.write(contentsOf: data)
    } else {
      try? data.write(to: url)
    }
  }

  static func readJSON(_ url: URL) -> [String: Any]? {
    guard let data = try? Data(contentsOf: url),
          let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    else { return nil }
    return object
  }

  /// O `JSONSerialization` lança exceção do Objective-C — não erro do Swift —
  /// diante de NaN ou infinito, e derrubaria o app. Viram `null` antes.
  /// `Float` vira o `Double` mais curto que volta ao mesmo `Float`: `0.412`, e
  /// não `0.41200000047683716`.
  ///
  /// Pelo **tipo dinâmico**, e não por `as? Float`: um `NSNumber` — o que o
  /// Expo entrega nas políticas — passaria nesse teste, e `true` viraria `1.0`.
  static func sanitize(_ value: Any) -> Any {
    if let d = value as? [String: Any] { return d.mapValues { sanitize($0) } }
    if let a = value as? [Any] { return a.map { sanitize($0) } }
    let kind = type(of: value)
    if kind == Float.self, let f = value as? Float {
      guard f.isFinite else { return NSNull() }
      return Double("\(f)") ?? Double(f)
    }
    if kind == Double.self || kind == CGFloat.self, let d = value as? Double {
      return d.isFinite ? d : NSNull()
    }
    if let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
       !n.doubleValue.isFinite {
      return NSNull()
    }
    return value
  }

  // MARK: - Item inteiro ou nada

  /// `items/.tmp-<id>/`, vazia. Uma sobra de uma tentativa anterior sai antes.
  static func beginItem(id: String, in items: URL) throws -> URL {
    let fm = FileManager.default
    let tmp = items.appendingPathComponent(".tmp-\(id)", isDirectory: true)
    try? fm.removeItem(at: tmp)
    do {
      try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    } catch {
      throw WriteError.folder(error.localizedDescription)
    }
    return tmp
  }

  /// A troca de nome que faz o item existir. No mesmo volume, é atômica (R41).
  static func commitItem(_ tmp: URL, id: String, in items: URL) throws -> URL {
    let final = items.appendingPathComponent(id, isDirectory: true)
    do {
      try FileManager.default.moveItem(at: tmp, to: final)
    } catch {
      throw WriteError.folder(error.localizedDescription)
    }
    return final
  }

  // MARK: - Tamanhos

  static func size(of url: URL) -> Int {
    ((try? FileManager.default.attributesOfItem(atPath: url.path))?[.size] as? NSNumber)?.intValue ?? 0
  }

  /// Soma dos arquivos de uma pasta, recursiva.
  static func size(ofFolder url: URL) -> Int {
    guard let walker = FileManager.default.enumerator(
      at: url, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey]) else { return 0 }
    var total = 0
    for case let file as URL in walker {
      let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
      if values?.isRegularFile == true { total += values?.fileSize ?? 0 }
    }
    return total
  }
}
