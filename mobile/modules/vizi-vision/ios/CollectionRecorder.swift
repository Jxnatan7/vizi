import Foundation
import UIKit

/// O dono da sessão de coleta (spec 007, R36).
///
/// Abre e fecha a sessão, recebe marcas e capturas, e escreve tudo numa fila
/// serial própria, de prioridade utilitária. Vive enquanto o módulo vive — a
/// sessão de coleta atravessa sessões de câmera: trocar de aba desliga a
/// câmera, não a coleta (FR-013).
///
/// O JavaScript espelha o estado pelo `onChange`, emitido só em mudança
/// discreta. Nenhum pixel sai daqui (princípio II).
final class CollectionRecorder {

  /// Política da coleta. Vem do TypeScript — princípio IV.
  struct Policy {
    var minScore: Float
    var minFreeBytes: Double
    var jpegQuality: Double
  }

  /// O código vai no começo da mensagem, para a tela dizer o que fazer
  /// (contrato, "Comportamento").
  enum RecorderError: LocalizedError {
    case closed, camera, busy, space, stale, open, missing
    case invalid(String)
    case export(String)

    var errorDescription: String? {
      switch self {
      case .closed: return "closed: o modo coleta está desligado."
      case .camera: return "camera: a câmera não está rodando."
      case .busy: return "busy: há uma captura, um resultado ou um quadro parado na tela."
      case .space: return "space: pouco espaço livre no aparelho."
      case .stale: return "stale: este item não espera mais resposta."
      case .open: return "open: a sessão ainda está aberta."
      case .missing: return "missing: a sessão não existe mais."
      case .invalid(let m): return "invalid: \(m)"
      case .export(let m): return "export: \(m)"
      }
    }
  }

  /// A sessão aberta. Classe, não struct: o trabalho dos itens e o fechamento
  /// a compartilham pela fila, e os contadores que um escreve o outro lê.
  private final class Open {
    let id: String
    let folder: URL
    let startedAt: Date
    let policy: Policy
    var manifest: [String: Any]
    var seq = 0
    var marks = 0
    var captures = 0
    var answered = 0
    var skipped = 0
    var bytes = 0

    init(id: String, folder: URL, startedAt: Date, policy: Policy, manifest: [String: Any]) {
      self.id = id
      self.folder = folder
      self.startedAt = startedAt
      self.policy = policy
      self.manifest = manifest
    }

    var items: URL { folder.appendingPathComponent("items", isDirectory: true) }
    var telemetry: URL { folder.appendingPathComponent("telemetry.jsonl") }
    var sessionFile: URL { folder.appendingPathComponent("session.json") }
  }

  /// Todo o disco passa por aqui, em ordem. É o que faz a resposta chegar
  /// depois do item, e o fechamento depois de todos os itens.
  private let queue = DispatchQueue(label: "com.jxnatan7.vizi.collection", qos: .utility)
  private let lock = NSLock()
  private var current: Open?
  /// O item à espera de resposta, e o número com que o pedido abriu (R43).
  private var awaiting: (id: String, prefill: Int)?
  private var lowSpace = false
  private var lastError: String?
  private var backgroundObserver: NSObjectProtocol?

  /// Emitido em abrir, fechar, item gravado, resposta gravada e espaço
  /// cruzando o limite. Nunca por quadro.
  var onChange: (([String: Any]) -> Void)?

  static var documents: URL {
    FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
  }

  /// `Documents/collection/` — exposta no app Arquivos, como o histórico.
  static var root: URL {
    documents.appendingPathComponent("collection", isDirectory: true)
  }

  /// O que a sessão é (spec 008): no topo do `session.json`, como o TypeScript
  /// enviou. `purpose` e `light` voltam no estado e na lista.
  static let sessionKeys = ["purpose", "light", "shelves"]

  init() {
    // Antes de qualquer outra coisa na fila: o que um encerramento forçado
    // deixou para trás (R41).
    queue.async { [weak self] in self?.recover() }

    // No nativo, e só no segundo plano de verdade. O `inactive` do JS dispara
    // ao puxar a Central de Controle, e fechar ali encerraria sessões por
    // acidente (R42).
    backgroundObserver = NotificationCenter.default.addObserver(
      forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
    ) { [weak self] _ in self?.enteredBackground() }
  }

  deinit {
    if let backgroundObserver { NotificationCenter.default.removeObserver(backgroundObserver) }
  }

  // MARK: - Abrir e fechar

  /// Abre uma sessão. Com uma aberta, devolve o estado dela — "uma aberta por
  /// vez".
  ///
  /// - Parameters:
  ///   - meta: app, aparelho e modelo, montados pelo módulo (R45)
  ///   - cameraInfo: a sessão de câmera que já estava rodando, se houver
  func start(policy: Policy, policies: [String: Any], meta: [String: Any],
             cameraInfo: [String: Any]?) throws -> [String: Any] {
    lock.lock()
    if current != nil {
      defer { lock.unlock() }
      return stateLocked()
    }
    let now = Date()
    let id = Self.uniqueId(for: now)
    let folder = Self.root.appendingPathComponent(id, isDirectory: true)
    do {
      try FileManager.default.createDirectory(
        at: folder.appendingPathComponent("items", isDirectory: true),
        withIntermediateDirectories: true)
    } catch {
      lock.unlock()
      throw CollectionWriter.WriteError.folder(error.localizedDescription)
    }

    var manifest: [String: Any] = [
      "format": 1,
      "id": id,
      "name": NSNull(),
      "startedAt": Self.ms(now),
      "endedAt": NSNull(),
      "endReason": NSNull(),
      "policies": policies,
      "counts": ["marks": 0, "captures": 0, "answered": 0, "skipped": 0],
    ]
    for (key, value) in meta { manifest[key] = value }

    let open = Open(id: id, folder: folder, startedAt: now, policy: policy, manifest: manifest)
    current = open
    awaiting = nil
    lastError = nil
    lock.unlock()

    queue.async {
      _ = try? CollectionWriter.writeJSON(manifest, to: open.sessionFile)
      if let cameraInfo {
        var line = cameraInfo
        line["type"] = "cameraStart"
        line["at"] = Self.ms(now)
        CollectionWriter.appendLine(line, to: open.telemetry)
      }
    }
    hasSpace()
    emit()
    return state()
  }

  /// Fecha: o fim é agora, mas o arquivo só é escrito depois de a fila
  /// terminar os itens que já entraram nela. Sem itens, a pasta sai (FR-019).
  @discardableResult
  func stop(reason: String, then done: (() -> Void)? = nil) -> [String: Any] {
    lock.lock()
    guard let open = current else {
      lock.unlock()
      done?()
      return state()
    }
    current = nil
    awaiting = nil
    lock.unlock()

    let endedAt = Date()
    queue.async {
      self.finalize(open, reason: reason, endedAt: endedAt)
      self.emit()
      done?()
    }
    emit()
    return state()
  }

  private func finalize(_ open: Open, reason: String, endedAt: Date) {
    lock.lock()
    let marks = open.marks, captures = open.captures
    let answered = open.answered, skipped = open.skipped
    lock.unlock()

    if marks + captures == 0 {
      remove(id: open.id)
      return
    }
    var manifest = open.manifest
    manifest["endedAt"] = Self.ms(endedAt)
    manifest["endReason"] = reason
    manifest["counts"] = ["marks": marks, "captures": captures, "answered": answered, "skipped": skipped]
    manifest["bytes"] = CollectionWriter.size(ofFolder: open.folder)
    _ = try? CollectionWriter.writeJSON(manifest, to: open.sessionFile)
  }

  /// Segundo plano fecha, como desligar, com uma tarefa de segundo plano para
  /// a fila terminar os itens pendentes.
  private func enteredBackground() {
    guard isOpen else { return }
    var task = UIBackgroundTaskIdentifier.invalid
    task = UIApplication.shared.beginBackgroundTask(withName: "vizi.collection") {
      UIApplication.shared.endBackgroundTask(task)
      task = .invalid
    }
    stop(reason: "background") {
      DispatchQueue.main.async {
        guard task != .invalid else { return }
        UIApplication.shared.endBackgroundTask(task)
        task = .invalid
      }
    }
  }

  var isOpen: Bool {
    lock.lock()
    defer { lock.unlock() }
    return current != nil
  }

  private func isOpen(_ id: String) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return current?.id == id
  }

  // MARK: - Espaço

  /// Confere o espaço livre contra o limite da política (R46). Sem sessão
  /// aberta, não há limite a respeitar.
  @discardableResult
  func hasSpace() -> Bool {
    lock.lock()
    let minFree = current?.policy.minFreeBytes
    lock.unlock()
    guard let minFree else { return true }

    let ok = Self.freeBytes().map { Double($0) >= minFree } ?? true
    lock.lock()
    let changed = lowSpace == ok
    lowSpace = !ok
    lock.unlock()
    if changed { emit() }
    return ok
  }

  static func freeBytes() -> Int64? {
    let values = try? documents.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    return values?.volumeAvailableCapacityForImportantUsage
  }

  // MARK: - Itens

  /// Grava uma marca em segundo plano e a torna o item à espera de resposta.
  /// Devolve o id, ou `nil` sem sessão aberta.
  func record(mark: CollectionTrace.Mark, prefill: Int) -> String? {
    guard let next = nextItem(prefix: "m", prefill: prefill) else { return nil }
    let (open, header) = next
    queue.async {
      self.writeItem(open, id: header.id, isMark: true) { folder in
        try CollectionTrace.write(mark, header: header, quality: open.policy.jpegQuality,
                                  minScore: open.policy.minScore, into: folder)
      }
    }
    return header.id
  }

  /// Grava uma captura em segundo plano e a torna o item à espera de resposta.
  func record(capture: CollectionTrace.Capture, prefill: Int) -> String? {
    guard let next = nextItem(prefix: "c", prefill: prefill) else { return nil }
    let (open, header) = next
    queue.async {
      self.writeItem(open, id: header.id, isMark: false) { folder in
        try CollectionTrace.write(capture, header: header, quality: open.policy.jpegQuality,
                                  minScore: open.policy.minScore, into: folder)
      }
    }
    return header.id
  }

  /// O número do item é a ordem na sessão, comum a marcas e capturas.
  private func nextItem(prefix: String, prefill: Int) -> (Open, CollectionTrace.Header)? {
    lock.lock()
    defer { lock.unlock() }
    guard let open = current else { return nil }
    open.seq += 1
    let now = Date()
    let id = String(format: "%@%04d", prefix, open.seq)
    awaiting = (id: id, prefill: prefill)
    return (open, CollectionTrace.Header(
      id: id, seq: open.seq,
      t: now.timeIntervalSince(open.startedAt) * 1000, at: Self.ms(now)))
  }

  /// Item inteiro ou nada (R41): escreve em `.tmp-<id>/` e troca o nome no
  /// fim. Qualquer falha apaga a pasta temporária e fica em `lastError`.
  private func writeItem(_ open: Open, id: String, isMark: Bool, body: (URL) throws -> Int) {
    do {
      let tmp = try CollectionWriter.beginItem(id: id, in: open.items)
      do {
        let bytes = try body(tmp)
        _ = try CollectionWriter.commitItem(tmp, id: id, in: open.items)
        lock.lock()
        if isMark { open.marks += 1 } else { open.captures += 1 }
        open.bytes += bytes
        lock.unlock()
      } catch {
        try? FileManager.default.removeItem(at: tmp)
        throw error
      }
    } catch {
      lock.lock()
      lastError = "\(id): \(error.localizedDescription)"
      if awaiting?.id == id { awaiting = nil }
      lock.unlock()
    }
    emit()
  }

  // MARK: - A contagem real

  /// Só o item à espera aceita resposta, e uma vez (FR-011). `nil` = pulou.
  func answer(_ id: String, count: Int?) throws {
    if let count, count < 0 { throw RecorderError.invalid("contagem negativa") }
    lock.lock()
    guard let open = current, let waiting = awaiting, waiting.id == id else {
      lock.unlock()
      throw RecorderError.stale
    }
    awaiting = nil
    lock.unlock()

    let truth: [String: Any] = [
      "count": count.map { $0 as Any } ?? NSNull(),
      "skipped": count == nil,
      "prefill": waiting.prefill,
      "answeredAt": Self.ms(Date()),
    ]
    // Na fila, depois do item: a pessoa pode responder antes de o JPEG de
    // 12 MP terminar, e a resposta chega ao disco depois dele mesmo assim.
    queue.async {
      let folder = open.items.appendingPathComponent(id, isDirectory: true)
      // O item falhou ao gravar: não há onde pôr a resposta.
      guard FileManager.default.fileExists(atPath: folder.path) else { return }
      do {
        _ = try CollectionWriter.writeJSON(truth, to: folder.appendingPathComponent("truth.json"))
        self.lock.lock()
        if count == nil { open.skipped += 1 } else { open.answered += 1 }
        self.lock.unlock()
      } catch {
        self.lock.lock()
        self.lastError = "\(id): \(error.localizedDescription)"
        self.lock.unlock()
      }
      self.emit()
    }
  }

  /// Voltar à câmera, retomar o ao vivo ou encerrar a câmera: o item que
  /// esperava fica sem resposta.
  func releaseAwaiting() {
    lock.lock()
    awaiting = nil
    lock.unlock()
  }

  // MARK: - Telemetria

  /// A mesma amostra do evento `onTelemetry`, uma linha por amostra (R45).
  func appendTelemetry(_ sample: [String: Any]) {
    lock.lock()
    let open = current
    lock.unlock()
    guard let open else { return }
    var line = sample
    line["type"] = "sample"
    line["at"] = Self.ms(Date())
    queue.async { CollectionWriter.appendLine(line, to: open.telemetry) }
  }

  /// Início e fim de cada sessão de câmera, para a telemetria ter contexto.
  func cameraEvent(_ type: String, info: [String: Any] = [:]) {
    lock.lock()
    let open = current
    lock.unlock()
    guard let open else { return }
    var line = info
    line["type"] = type
    line["at"] = Self.ms(Date())
    queue.async { CollectionWriter.appendLine(line, to: open.telemetry) }
  }

  // MARK: - Estado

  func state() -> [String: Any] {
    lock.lock()
    defer { lock.unlock() }
    return stateLocked()
  }

  private func stateLocked() -> [String: Any] {
    var s: [String: Any] = [
      "open": current != nil,
      "marks": current?.marks ?? 0,
      "captures": current?.captures ?? 0,
      "answered": current?.answered ?? 0,
      "bytes": current?.bytes ?? 0,
      "lowSpace": lowSpace,
    ]
    if let current {
      s["id"] = current.id
      s["startedAt"] = Self.ms(current.startedAt)
      s["purpose"] = current.manifest["purpose"] ?? NSNull()
      s["light"] = current.manifest["light"] ?? NSNull()
    }
    if let lastError { s["lastError"] = lastError }
    return s
  }

  private func emit() {
    onChange?(state())
  }

  // MARK: - Sessões

  /// As sessões, mais recente primeiro. A aberta vem da memória — o
  /// `session.json` dela pode nem ter chegado ao disco.
  func list() -> [[String: Any]] {
    lock.lock()
    let open = current
    let openSummary: [String: Any]? = open.map {
      [
        "id": $0.id, "name": NSNull(), "startedAt": Self.ms($0.startedAt), "endedAt": NSNull(),
        "open": true, "endReason": NSNull(), "marks": $0.marks, "captures": $0.captures,
        "answered": $0.answered, "bytes": $0.bytes, "exportedAt": NSNull(),
        "purpose": $0.manifest["purpose"] ?? NSNull(), "light": $0.manifest["light"] ?? NSNull(),
      ]
    }
    lock.unlock()

    var out: [[String: Any]] = openSummary.map { [$0] } ?? []
    let entries = (try? FileManager.default.contentsOfDirectory(
      at: Self.root, includingPropertiesForKeys: nil)) ?? []
    for folder in entries where folder.hasDirectoryPath && folder.lastPathComponent != open?.id {
      guard let m = CollectionWriter.readJSON(folder.appendingPathComponent("session.json"))
      else { continue }
      let counts = m["counts"] as? [String: Any] ?? [:]
      let export = m["export"] as? [String: Any]
      out.append([
        "id": m["id"] as? String ?? folder.lastPathComponent,
        "name": m["name"] ?? NSNull(),
        "startedAt": m["startedAt"] ?? 0,
        "endedAt": m["endedAt"] ?? NSNull(),
        "open": false,
        "endReason": m["endReason"] ?? NSNull(),
        "marks": counts["marks"] ?? 0,
        "captures": counts["captures"] ?? 0,
        "answered": counts["answered"] ?? 0,
        "bytes": m["bytes"] ?? 0,
        "exportedAt": export?["at"] ?? NSNull(),
        // Ausentes nas sessões anteriores à spec 008.
        "purpose": m["purpose"] ?? NSNull(),
        "light": m["light"] ?? NSNull(),
      ])
    }
    return out.sorted {
      (($0["startedAt"] as? NSNumber)?.doubleValue ?? 0) > (($1["startedAt"] as? NSNumber)?.doubleValue ?? 0)
    }
  }

  /// Só a fechada recebe nome. Vazio apaga o nome.
  func rename(_ id: String, name: String) throws {
    try Self.validate(id)
    guard !isOpen(id) else { throw RecorderError.open }
    try queue.sync {
      let file = Self.root.appendingPathComponent(id).appendingPathComponent("session.json")
      guard var m = CollectionWriter.readJSON(file) else { throw RecorderError.missing }
      let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
      m["name"] = trimmed.isEmpty ? NSNull() : trimmed
      _ = try CollectionWriter.writeJSON(m, to: file)
    }
    emit()
  }

  /// Só a fechada é apagada; leva a pasta e o zip.
  func delete(_ id: String) throws {
    try Self.validate(id)
    guard !isOpen(id) else { throw RecorderError.open }
    try queue.sync {
      let folder = Self.root.appendingPathComponent(id, isDirectory: true)
      guard FileManager.default.fileExists(atPath: folder.path) else { throw RecorderError.missing }
      remove(id: id)
    }
    emit()
  }

  private func remove(id: String) {
    let fm = FileManager.default
    try? fm.removeItem(at: Self.root.appendingPathComponent(id, isDirectory: true))
    try? fm.removeItem(at: Self.root.appendingPathComponent("\(id).zip"))
  }

  // MARK: - Exportar

  struct Exported {
    var zip: URL
    /// Relativo à pasta de documentos — o absoluto muda a cada reinstalação.
    var relative: String
    var bytes: Int
    var shareName: String
  }

  /// O zip da sessão, em `collection/<id>.zip`, com o `FORMAT.md` dentro
  /// (R44). Só a fechada exporta.
  func exportZip(_ id: String) async throws -> Exported {
    try Self.validate(id)
    guard !isOpen(id) else { throw RecorderError.open }
    return try await withCheckedThrowingContinuation { continuation in
      queue.async {
        do {
          let folder = Self.root.appendingPathComponent(id, isDirectory: true)
          let file = folder.appendingPathComponent("session.json")
          guard var m = CollectionWriter.readJSON(file) else { throw RecorderError.missing }

          // O zip é da ordem da pasta — JPEG não comprime —, e depois dele o
          // aparelho ainda precisa da folga da política, a que a sessão gravou
          // (princípio IV: nenhuma folga fixa aqui).
          let policies = m["policies"] as? [String: Any]
          let minFree = ((policies?["collection"] as? [String: Any])?["minFreeBytes"]
                         as? NSNumber)?.doubleValue ?? 0
          let need = Double(CollectionWriter.size(ofFolder: folder)) + minFree
          if let free = Self.freeBytes(), Double(free) < need { throw RecorderError.space }

          try CollectionExport.copyFormat(into: folder)
          let zip = Self.root.appendingPathComponent("\(id).zip")
          try CollectionExport.zip(folder, to: zip)
          let bytes = CollectionWriter.size(of: zip)

          m["export"] = ["at": Self.ms(Date()), "bytes": bytes] as [String: Any]
          _ = try? CollectionWriter.writeJSON(m, to: file)
          continuation.resume(returning: Exported(
            zip: zip, relative: "collection/\(id).zip", bytes: bytes,
            shareName: CollectionExport.shareName(id: id, name: m["name"] as? String)))
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  // MARK: - Recuperação

  /// O que um encerramento forçado deixou para trás (R41): apaga as `.tmp-*`,
  /// fecha as sessões órfãs com `endReason: "recovered"` e apaga as vazias.
  private func recover() {
    let fm = FileManager.default
    guard let entries = try? fm.contentsOfDirectory(at: Self.root, includingPropertiesForKeys: nil)
    else { return }
    lock.lock()
    let openId = current?.id
    lock.unlock()

    for folder in entries where folder.hasDirectoryPath && folder.lastPathComponent != openId {
      let items = folder.appendingPathComponent("items", isDirectory: true)
      let children = (try? fm.contentsOfDirectory(at: items, includingPropertiesForKeys: nil)) ?? []
      for child in children where child.lastPathComponent.hasPrefix(".tmp-") {
        try? fm.removeItem(at: child)
      }
      let found = children.filter { !$0.lastPathComponent.hasPrefix(".") }

      let file = folder.appendingPathComponent("session.json")
      guard var m = CollectionWriter.readJSON(file) else {
        // Sem manifesto, só sai se também não tiver item.
        if found.isEmpty { remove(id: folder.lastPathComponent) }
        continue
      }
      // Fechada: nada a fazer.
      guard (m["endedAt"] as? NSNumber) == nil else { continue }
      if found.isEmpty {
        remove(id: folder.lastPathComponent)
        continue
      }

      var marks = 0, captures = 0, answered = 0, skipped = 0
      var last = (m["startedAt"] as? NSNumber)?.doubleValue ?? 0
      for item in found {
        if item.lastPathComponent.hasPrefix("m") { marks += 1 } else { captures += 1 }
        if let at = (CollectionWriter.readJSON(item.appendingPathComponent("item.json"))?["at"]
                       as? NSNumber)?.doubleValue {
          last = max(last, at)
        }
        if let truth = CollectionWriter.readJSON(item.appendingPathComponent("truth.json")) {
          if truth["skipped"] as? Bool == true { skipped += 1 } else { answered += 1 }
        }
      }
      m["endedAt"] = last
      m["endReason"] = "recovered"
      m["counts"] = ["marks": marks, "captures": captures, "answered": answered, "skipped": skipped]
      m["bytes"] = CollectionWriter.size(ofFolder: folder)
      _ = try? CollectionWriter.writeJSON(m, to: file)
    }
  }

  // MARK: - Auxiliares

  static func ms(_ date: Date) -> Double { date.timeIntervalSince1970 * 1000 }

  /// O instante de abertura, legível e ordenável: `2026-10-19T14-03-22`.
  private static func uniqueId(for date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
    let base = formatter.string(from: date)
    var id = base
    var n = 2
    while FileManager.default.fileExists(atPath: root.appendingPathComponent(id).path) {
      id = "\(base)-\(n)"
      n += 1
    }
    return id
  }

  /// O id vem do JavaScript e vira caminho: só dígitos, `T` e hífen.
  private static func validate(_ id: String) throws {
    let allowed = CharacterSet(charactersIn: "0123456789T-")
    guard !id.isEmpty, id.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
      throw RecorderError.missing
    }
  }
}
