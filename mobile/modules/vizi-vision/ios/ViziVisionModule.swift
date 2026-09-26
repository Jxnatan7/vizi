import CoreImage
import ExpoModulesCore
import Foundation
import UIKit

/// Política da medição. Os valores vêm do TypeScript — princípio IV.
///
/// Os defaults existem só porque o protocolo `Record` exige um `init()`; o
/// TypeScript sempre envia todos os campos. Mantidos em sincronia com
/// `src/bench/runBenchmark.ts` para que uma divergência não passe despercebida
/// se algum dia um campo deixar de ser enviado.
struct BenchmarkOptions: Record {
  @Field var repetitions: Int = 100
  @Field var warmupDiscard: Int = 25
  @Field var confidenceThreshold: Double = 0.25
  @Field var iouThreshold: Double = 0.7
}

/// Política da sessão de câmera. Também vem do TypeScript — princípio IV.
/// Aparência do overlay. O nativo executa; o TypeScript decide (FR-010).
/// Política da captura. Vem do TypeScript — princípio IV.
struct CaptureOptions: Record {
  @Field var cropMargin: Double = 0.05
  @Field var minInstancesForGeometry: Int = 5
  @Field var minGeometryConfidence: Double = 0.6
  /// Aproximação no toque, antes de a foto existir (FR-009).
  @Field var approachMs: Int = 700
  /// Endireitamento, depois que o resultado existe — e a volta.
  @Field var transitionMs: Int = 600
  /// Mostra o que o algoritmo inferiu em vez do resultado. Política em TS.
  @Field var diagnostics: Bool = false
  /// O que decide em pé, fileira e confiança — ver `ShelfGeometry.Tuning`.
  @Field var geometry: GeometryTuningRecord = GeometryTuningRecord()
  /// Divisões mais perto que isto das bordas do recorte são descartadas.
  /// O 0,5 não deixa nenhuma passar: inválido de propósito, como abaixo.
  @Field var dividerEdgeMargin: Double = 0.5
}

/// Política da estimativa da estante. Vira `ShelfGeometry.Tuning`.
///
/// **Defaults inválidos de propósito**, como os limiares da sessão: o
/// TypeScript sempre envia todos os campos. Se um dia deixar de enviar, a
/// tolerância zero não deixa nenhum livro em pé e toda captura recusa o
/// endireitamento — o defeito aparece na primeira foto, em vez de a geometria
/// rodar com um valor plausível e defasado (o modo de falha da T037 do marco 1).
struct GeometryTuningRecord: Record {
  @Field var standingToleranceDegrees: Double = 0
  @Field var rowGapFactor: Double = 0
  @Field var minRowGap: Double = 0
  @Field var minBooksPerRow: Int = 0
  @Field var fullConfidenceCount: Double = 0
  @Field var maxBaseResidual: Double = 0
  @Field var maxAngleSpread: Double = 0
  @Field var maxRowSlopeSpread: Double = 0
  @Field var weightsWithGravity: ConfidenceWeightsRecord = ConfidenceWeightsRecord()
  @Field var weightsWithoutGravity: ConfidenceWeightsRecord = ConfidenceWeightsRecord()
}

/// Peso de cada sinal na confiança (R15). Zerados pelo mesmo motivo.
struct ConfidenceWeightsRecord: Record {
  @Field var count: Double = 0
  @Field var line: Double = 0
  @Field var spread: Double = 0
  @Field var rows: Double = 0
}

/// Política da gravação no histórico. Vem do TypeScript — princípio IV.
struct SaveResultOptions: Record {
  /// Qualidade do JPEG, de 0 a 1. Zero, inválido de propósito, estraga a
  /// imagem à vista em vez de passar despercebido.
  @Field var quality: Double = 0
}

struct OverlayStyleRecord: Record {
  @Field var showBoxes: Bool = true
  @Field var showMasks: Bool = true
  @Field var boxWidth: Double = 3
  @Field var maskOpacity: Double = 0.45
  @Field var minConfidence: Double = 0.3
  /// Cores em "#RRGGBB".
  @Field var palette: [String] = []
  @Field var showDividers: Bool = true
  /// "#RRGGBB".
  @Field var dividerColor: String = "#FFFFFF"
  /// Em pontos de tela.
  @Field var dividerWidth: Double = 2
}

struct SessionOptions: Record {
  @Field var sampleIntervalMs: Int = 500
  @Field var transform: String = "stretch"
  @Field var confidenceThreshold: Double = 0.25
  @Field var iouThreshold: Double = 0.7
}

public class ViziVisionModule: Module {
  private let engine = InferenceEngine()
  private let coordinator = SessionCoordinator()
  /// Usado só na captura, uma vez. Não está no caminho quente.
  private let ciContext = CIContext(options: [.cacheIntermediates: false])
  /// A volta usa a duração que a captura recebeu: `dismissResult` não tem
  /// opções, e a política continua vindo do TypeScript.
  private var transitionMs = 0

  /// O último resultado exibido, guardado para o `saveResult` (US4).
  ///
  /// O `imageId` que o JavaScript recebe é a chave dele, e o pixel nunca sai
  /// daqui (princípio II). Vive até o `dismissResult`, o fim da sessão ou a
  /// próxima captura.
  private let keptLock = NSLock()
  private var kept: (id: String, buffer: CVPixelBuffer)?

  public func definition() -> ModuleDefinition {
    Name("ViziVision")

    // Emitido a ~2 Hz. Um evento por frame seriam 60 travessias por segundo e
    // 60 re-renders — princípios II e III violados de uma vez.
    Events("onTelemetry")

    Function("probe") { () -> [String: Any] in
      let info = ProcessInfo.processInfo
      return [
        "module": "ViziVision",
        "os": info.operatingSystemVersionString,
        "processorCount": info.processorCount,
        "physicalMemoryMB": Int(info.physicalMemory / 1_048_576),
        "lowPowerMode": info.isLowPowerModeEnabled,
      ]
    }

    // AsyncFunction roda fora da thread de interface — princípio I. Mesmo sem
    // loop de desenho neste marco, o precedente contrário custaria caro depois.
    AsyncFunction("loadModel") { () -> [String: Any] in
      try self.engine.load()
      return [
        "identifier": "vizi-seg",
        "inputWidth": self.engine.inputWidth,
        "inputHeight": self.engine.inputHeight,
        "classes": self.engine.classes.reduce(into: [String: String]()) { $0["\($1.key)"] = $1.value },
        "maskCoeffCount": self.engine.maskCoeffCount,
        "computeUnits": self.engine.requestedComputeUnits,
        "compiledAtRuntime": self.engine.compiledAtRuntime,
        "loadMs": self.engine.compileMs,
      ]
    }

    AsyncFunction("runBenchmark") { (options: BenchmarkOptions) -> [String: Any] in
      let threshold = Float(options.confidenceThreshold)
      let iou = Float(options.iouThreshold)
      let total = max(1, options.repetitions)

      var modelMs: [Double] = []
      var cycleMs: [Double] = []
      modelMs.reserveCapacity(total)
      cycleMs.reserveCapacity(total)

      var lastInstances: [Instance] = []
      for _ in 0..<total {
        let r = try self.engine.runOnce(confidenceThreshold: threshold, iouThreshold: iou)
        modelMs.append(r.modelMs)
        cycleMs.append(r.cycleMs)
        lastInstances = r.instances
      }

      // Latências INDIVIDUAIS, não agregados: é o que permite caracterizar o
      // aquecimento (T029) e manter a agregação como política do TypeScript.
      // ~100 valores por série; ordens de grandeza abaixo do limite de 64 KB.
      return [
        "modelMsAll": modelMs,
        "cycleMsAll": cycleMs,
        "thermalState": InferenceEngine.thermalStateLabel(),
        "executionUnit": self.engine.requestedComputeUnits,
        "instances": lastInstances.map {
          [
            "classIndex": $0.classIndex, "score": Double($0.score),
            "x": Double($0.x), "y": Double($0.y),
            "width": Double($0.width), "height": Double($0.height),
          ]
        },
      ]
    }

    AsyncFunction("unloadModel") {
      self.engine.unload()
    }

    // MARK: - Câmera (marco 2)

    AsyncFunction("hasCameraPermission") { () -> Bool in
      CameraSession.hasPermission()
    }

    AsyncFunction("requestCameraPermission") { () async -> Bool in
      await CameraSession.requestPermission()
    }

    AsyncFunction("startSession") { (options: SessionOptions) -> [String: Any] in
      // Uma sessão nova começa ao vivo, venha a anterior de onde vier.
      self.endResultState()

      // O modelo precisa estar carregado antes: carregar leva ~720 ms e faria
      // os primeiros segundos de telemetria medirem a carga, não a inferência.
      if !self.engine.isLoaded { try self.engine.load() }

      self.coordinator.engine = self.engine
      self.coordinator.onSample = { [weak self] sample in
        self?.sendEvent("onTelemetry", sample)
      }
      // Configuração vai para o sink, não para a view: ela ainda não existe
      // neste instante, e só nasce quando o JSX reage ao retorno desta função.
      PreviewSink.shared.store = self.coordinator.results
      PreviewSink.shared.imageSide = CGFloat(self.engine.inputWidth)
      PreviewSink.shared.active = true
      return try self.coordinator.start(
        sampleIntervalMs: options.sampleIntervalMs,
        mode: TransformMode(rawValue: options.transform) ?? .stretch,
        confidenceThreshold: Float(options.confidenceThreshold),
        iouThreshold: Float(options.iouThreshold))
    }

    AsyncFunction("setTransform") { (transform: String) in
      self.coordinator.mode = TransformMode(rawValue: transform) ?? .stretch
    }

    // MARK: - Captura (marco 4)

    AsyncFunction("capture") { (options: CaptureOptions) -> [String: Any] in
      let touchedAt = CFAbsoluteTimeGetCurrent()
      self.transitionMs = options.transitionMs

      // A chave do resultado para o `saveResult`. A captura nova descarta a
      // anterior mesmo que falhe: salvar depois disso gravaria a foto errada.
      let imageId = UUID().uuidString
      self.dropResult()

      // Congela ANTES de qualquer reconfiguração: a tela precisa segurar a
      // última imagem enquanto o formato é trocado (FR-009).
      // Congela imagem E overlay juntos. Separá-los mostraria caixas de um
      // frame sobre a imagem de outro.
      let frozen = PreviewSink.shared.freeze()
      self.coordinator.results.setPaused(true)

      // A transição começa AQUI, antes da foto (FR-009): o frame congelado se
      // aproxima dos objetos que estavam na tela. O destino exato só existe
      // depois do resultado, e a segunda metade parte de onde esta estiver.
      if let frozen {
        let still = CIImage(cvPixelBuffer: frozen)
        if let image = self.ciContext.createCGImage(still, from: still.extent) {
          let focus = ViziVisionModule.focus(
            of: self.coordinator.results.read().instances,
            side: Double(self.engine.inputWidth), margin: options.cropMargin)
          PreviewSink.shared.onView {
            $0.result.begin(frame: image, focus: focus, durationMs: options.approachMs)
          }
        }
      }

      do {
        let shot = try await self.coordinator.capturePhoto()
        let side = self.engine.inputWidth
        let square = try self.coordinator.squareFromPhoto(shot.buffer, side: side)
        // Os MESMOS limiares do ao vivo, que o TypeScript enviou na sessão.
        // Fixos aqui, o SC-004 compararia contagens feitas com réguas
        // diferentes assim que alguém mexesse no limiar — sem ninguém ver.
        let result = try self.engine.run(
          on: square,
          confidenceThreshold: self.coordinator.confidenceThreshold,
          iouThreshold: self.coordinator.iouThreshold)

        // As detecções da FOTO substituem as do último frame ao vivo. As
        // coordenadas são comparáveis: as duas passaram pela mesma
        // transformação para 640×640.
        // Geometria da estante, a partir das MÁSCARAS. Caixa alinhada aos
        // eixos não informa inclinação.
        var straightened = false
        var declineReason = "sem protótipos de máscara"
        /// A confiança da geometria (R15): a que o `minGeometryConfidence`
        /// compara, e a que o contrato chama de `geometryConfidence`.
        var confidence = 0.0
        /// A nitidez do cruzamento entre a reta das bases e o horizonte. É
        /// outra medida — e era ela que atravessava como `geometryConfidence`.
        var azimuth = 0.0
        var shelves: [Rectify.Shelf] = []
        var shelfCount = 0
        var lyingCount = 0
        var usedGravity = false
        /// O overlay precisa ser limpo sempre que a imagem exibida deixar de
        /// ser a canônica — não só quando houver endireitamento. Girada conta.
        var imageReplaced = false
        /// Declarada aqui, e não dentro do `if let protos`, porque é usada no
        /// `return`. Três erros de compilação seguidos vieram de variáveis de
        /// resultado nascendo em escopo mais interno do que onde são lidas.
        var azimuthScores: [Double] = []
        var rowsForShelves: [ShelfGeometry.Row] = []
        var displayBuffer = square
        /// Onde o recorte exibido estava no frame, normalizado. Vazio quando o
        /// que aparece é o frame inteiro — e a transição só se acomoda nele.
        var transitionQuad: [CGPoint] = []

        if let protos = result.protos {
          // A atitude é amostrada NO disparo, não depois: medir a inclinação
          // um instante mais tarde é medir outro momento.
          let gravity = self.coordinator.attitude.snapshot()
          let photoW = Double(CVPixelBufferGetWidth(shot.buffer))
          let photoH = Double(CVPixelBufferGetHeight(shot.buffer))
          let focal = Projective.Focal.from(
            fieldOfViewDegrees: self.coordinator.fieldOfView,
            sensorLongSide: max(photoW, photoH),
            portraitWidth: min(photoW, photoH),
            portraitHeight: max(photoW, photoH),
            canonicalSide: Double(side))

          let estimate = ShelfGeometry.estimate(
            instances: result.instances,
            protos: protos,
            imageSide: side,
            gravity: gravity,
            focal: focal,
            minInstances: options.minInstancesForGeometry,
            minConfidence: options.minGeometryConfidence,
            tuning: ShelfGeometry.Tuning(options.geometry))

          declineReason = estimate.declineReason ?? ""
          shelfCount = estimate.rows.count
          lyingCount = estimate.lying.count
          usedGravity = estimate.usedGravity
          rowsForShelves = estimate.rows

          // Contagem por fileira já vale por si; as divisões só existem quando
          // há retificação, e são preenchidas adiante. Atribuir aqui garante
          // que a ordem "usa antes de atribuir" não se repita.
          shelves = estimate.rows.map {
            Rectify.Shelf(count: $0.indices.count, dividers: [], top: 0, bottom: 0)
          }

          // ── Retificação pelo PLANO, não pelos objetos ──────────────────
          //
          // A gravidade dá a vertical; a busca de azimute dá a horizontal,
          // usando as bordas da foto inteira. Os livros só definem o recorte.
          var portrait = CIImage(cvPixelBuffer: shot.buffer)
          if portrait.extent.width > portrait.extent.height {
            portrait = portrait.oriented(.right)
          }
          portrait = portrait.transformed(by: CGAffineTransform(
            translationX: -portrait.extent.minX, y: -portrait.extent.minY))

          // Canônico (640×640) → retrato. Esticamento alinhado aos eixos.
          let kx = portrait.extent.width / CGFloat(side)
          let ky = portrait.extent.height / CGFloat(side)
          let region = result.instances.flatMap { inst -> [CGPoint] in
            [CGPoint(x: CGFloat(inst.x) * kx, y: CGFloat(inst.y) * ky),
             CGPoint(x: CGFloat(inst.x + inst.width) * kx,
                     y: CGFloat(inst.y + inst.height) * ky)]
          }

          var azimuthConfidence = 0.0
          var horizontalVP: Projective.H?
          let halfFov = self.coordinator.fieldOfView * .pi / 360
          let fPortrait = halfFov > 1e-6
            ? Double(max(portrait.extent.width, portrait.extent.height)) / 2 / tan(halfFov)
            : Double(max(portrait.extent.width, portrait.extent.height))

          if let g = gravity {
            let horizonPortrait = Projective.horizon(
              gravity: g,
              focal: Projective.Focal(x: fPortrait, y: fPortrait),
              center: CGPoint(x: portrait.extent.width / 2, y: portrait.extent.height / 2))

            // ── Horizontal: bases dos livros, PROJETADAS no horizonte ──────
            //
            // A primeira tentativa usou as bases sem horizonte confiável,
            // porque a vertical vinha do PCA. Agora a vertical vem da
            // gravidade e o horizonte está provado correto — o cruzamento das
            // duas informações é o que faltava.
            if let baseCanonical = estimate.bestBaseLine {
              // A reta está em coordenadas canônicas; converter para retrato.
              // Uma reta transforma pela INVERSA transposta da escala.
              let basePortrait: Projective.H = (baseCanonical.x / Double(kx),
                                                baseCanonical.y / Double(ky),
                                                baseCanonical.w)
              let vp = Projective.cross(basePortrait, horizonPortrait)
              let scale = max(abs(vp.x), abs(vp.y))
              if scale > 1e-9 {
                horizontalVP = vp
                // Confiança: o quanto a base e o horizonte se cruzam de forma
                // bem determinada. Quase paralelos dão um ponto instável.
                azimuthConfidence = min(1, abs(vp.w) / scale * 1000)
              }
            }

            // A busca por gradientes fica só como diagnóstico: o teste no
            // aparelho mostrou que ela erra em cenas frontais.
            if options.diagnostics,
               let found = AzimuthSearch.search(
                 portrait: portrait, gravity: g,
                 fieldOfViewDegrees: self.coordinator.fieldOfView,
                 context: self.ciContext) {
              azimuthScores = found.scores
            }

            if !region.isEmpty,
               let out = PlaneRectifier.rectify(
                 portrait: portrait, gravity: g, horizontalVP: horizontalVP,
                 region: region, fieldOfViewDegrees: self.coordinator.fieldOfView,
                 margin: options.cropMargin),
               let rendered = Rectify.render(out.image, context: self.ciContext) {
              straightened = out.fullyRectified
              // O motivo da estimativa vem antes do da retificação. "Poucos
              // livros" diz à pessoa o que fazer diferente; "sem ponto de
              // fuga" é só a consequência dele, e era o que aparecia.
              declineReason = out.fullyRectified
                ? ""
                : "só rotação — \(estimate.declineReason ?? out.fallbackReason ?? "motivo desconhecido")"

              if options.diagnostics {
                // Sobre a foto CRUA: horizonte, pontos de fuga, recorte e a
                // curva. Uma captura passa a dizer qual etapa falhou.
                if let diag = Diagnostics.draw(
                  portrait: portrait, context: self.ciContext,
                  horizon: horizonPortrait, verticalVP: out.verticalVP,
                  horizontalVP: horizontalVP, cropQuad: out.sourceQuad,
                  scores: azimuthScores) {
                  displayBuffer = diag
                  imageReplaced = true
                }
              } else {
                displayBuffer = rendered
                imageReplaced = true
                if out.sourceQuad.count == 4 {
                  let pw = portrait.extent.width, ph = portrait.extent.height
                  transitionQuad = out.sourceQuad.map { CGPoint(x: $0.x / pw, y: $0.y / ph) }
                }
              }

              // ── Divisões e bandas, no espaço do RESULTADO ────────────────
              //
              // Cada fronteira entre livros é mapeada pela mesma transformação
              // que produziu a imagem, e normalizada pelo retângulo do
              // recorte. Sem isso as divisões ficariam em coordenadas de outro
              // espaço — que foi o motivo de elas terem ficado zeradas desde a
              // reestruturação.
              if out.fullyRectified, !rowsForShelves.isEmpty {
                let toPhoto = { (x: Float, y: Float) in
                  CGPoint(x: CGFloat(x) * kx, y: CGFloat(y) * ky)
                }
                let edge = options.dividerEdgeMargin
                shelves = rowsForShelves.compactMap { row -> Rectify.Shelf? in
                  let members = row.indices.compactMap {
                    result.instances.indices.contains($0) ? result.instances[$0] : nil
                  }
                  guard !members.isEmpty else { return nil }
                  let ordered = members.sorted { $0.x < $1.x }

                  var cuts: [Double] = []
                  for i in 0..<max(0, ordered.count - 1) {
                    let a = ordered[i], b = ordered[i + 1]
                    let edgeX = (a.x + a.width + b.x) / 2
                    let baseY = max(a.y + a.height, b.y + b.height)
                    if let n = out.normalize(toPhoto(edgeX, baseY)),
                       Double(n.x) > edge, Double(n.x) < 1 - edge {
                      cuts.append(Double(n.x))
                    }
                  }

                  let topY = members.map(\.y).min() ?? 0
                  let bottomY = members.map { $0.y + $0.height }.max() ?? 0
                  let midX = members.map { $0.x + $0.width / 2 }.reduce(0, +) / Float(members.count)
                  let nTop = out.normalize(toPhoto(midX, topY))?.y ?? 0
                  let nBottom = out.normalize(toPhoto(midX, bottomY))?.y ?? 0

                  return Rectify.Shelf(count: members.count, dividers: cuts,
                                       top: min(Double(nTop), Double(nBottom)),
                                       bottom: max(Double(nTop), Double(nBottom)))
                }
              }
            }
          } else {
            declineReason = "sem leitura de gravidade"
          }

          confidence = estimate.confidence
          azimuth = azimuthConfidence
        }

        // Uma imagem na tela, e as detecções são dela. Endireitada quando deu
        // para endireitar; a canônica quando não deu.
        PreviewSink.shared.showStill(displayBuffer)
        // É esta imagem que o `saveResult` grava: a que a pessoa está vendo.
        self.keepResult(imageId, displayBuffer)

        // O overlay ao vivo não vale sobre a imagem endireitada — as
        // coordenadas são de outro espaço. Limpa em vez de desenhar errado.
        if imageReplaced {
          self.coordinator.results.publishOverriding(instances: [], protos: nil)
        } else {
          self.coordinator.results.publishOverriding(
            instances: result.instances, protos: result.protos)
        }

        // Segunda metade da transição. Ela termina exatamente sobre a imagem
        // que acabou de ir para a tela, por baixo dela (FR-010).
        let shown = CGSize(width: CVPixelBufferGetWidth(displayBuffer),
                           height: CVPixelBufferGetHeight(displayBuffer))
        // `let`, não `var`: ela é capturada por um bloco que roda em outra
        // thread.
        let destination: ResultRenderer.Destination
        if transitionQuad.count == 4,
           let image = self.screenImage(displayBuffer, fitting: PreviewSink.shared.stagePixels) {
          destination = .cutout(image, quad: transitionQuad, size: shown)
        } else {
          destination = .whole(size: shown)
        }
        // As divisões estão normalizadas no recorte ENDIREITADO. Sobre a
        // canônica ou o diagnóstico cairiam em outro espaço — lá, nenhuma.
        let drawn = straightened && !options.diagnostics ? shelves : []
        PreviewSink.shared.onView {
          // Por baixo da transição: aparecem quando ela termina (FR-008).
          $0.showDividers(drawn, imageSize: shown)
          $0.result.settle(destination, durationMs: options.transitionMs)
        }

        return [
          "count": result.instances.count,
          "straightened": straightened,
          "declineReason": declineReason,
          "geometryConfidence": confidence,
          "azimuthConfidence": azimuth,
          "shelves": shelves.map(\.dictionary),
          "shelfCount": shelfCount,
          "lyingCount": lyingCount,
          "usedGravity": usedGravity,
          "azimuthScores": azimuthScores,
          "imageId": imageId,
          "elapsedMs": shot.elapsedMs,
          "readyMs": (CFAbsoluteTimeGetCurrent() - touchedAt) * 1000,
          "photoWidth": CVPixelBufferGetWidth(shot.buffer),
          "photoHeight": CVPixelBufferGetHeight(shot.buffer),
          "instances": result.instances.count,
        ]
      } catch {
        PreviewSink.shared.onView {
          $0.result.teardown()
          $0.clearDividers()
        }
        PreviewSink.shared.frozen = false
        self.coordinator.results.setPaused(false)
        throw error
      }
    }

    AsyncFunction("dismissResult") {
      // A câmera volta por baixo; a transição se desfaz por cima (T029).
      //
      // Descongela na thread de interface, DEPOIS de a transição reaparecer.
      // Daqui, um frame ao vivo podia chegar à tela antes dela e piscar sobre
      // o resultado. Sem view, descongela do mesmo jeito.
      let duration = self.transitionMs
      self.dropResult()
      DispatchQueue.main.async {
        // As divisões saem neste mesmo quadro: a transição reaparece por cima
        // delas, e depois dela vem a câmera ao vivo.
        PreviewSink.shared.view?.clearDividers()
        PreviewSink.shared.view?.result.dismiss(durationMs: duration)
        self.coordinator.results.setPaused(false)
        PreviewSink.shared.frozen = false
      }
    }

    // Grava o resultado que está na tela (US4). O pixel vai do buffer ao
    // arquivo sem passar pelo JavaScript; o que volta é o caminho.
    AsyncFunction("saveResult") { (options: SaveResultOptions) -> [String: Any] in
      guard let current = self.keptResult() else {
        throw ResultArchive.ArchiveError.noResult
      }
      let saved = try ResultArchive.save(
        current.buffer, id: current.id, quality: options.quality, context: self.ciContext)
      return [
        "id": current.id,
        "file": saved.file,
        "width": saved.width,
        "height": saved.height,
        "bytes": saved.bytes,
      ]
    }

    AsyncFunction("setOverlayStyle") { (record: OverlayStyleRecord) in
      var style = OverlayStyle()
      style.showBoxes = record.showBoxes
      style.showMasks = record.showMasks
      style.boxWidth = CGFloat(record.boxWidth)
      style.maskOpacity = CGFloat(record.maskOpacity)
      style.minConfidence = Float(record.minConfidence)
      if !record.palette.isEmpty {
        style.palette = record.palette.compactMap { UIColor(hex: $0)?.cgColor }
      }
      style.showDividers = record.showDividers
      style.dividerWidth = CGFloat(record.dividerWidth)
      if let color = UIColor(hex: record.dividerColor)?.cgColor {
        style.dividerColor = color
      }
      // Trocar estilo não pode custar um frame nem depender da view existir.
      PreviewSink.shared.style = style
    }

    // Preview: mostra o buffer JÁ TRANSFORMADO, o mesmo que vai ao modelo.
    View(PreviewView.self) {}

    AsyncFunction("stopSession") { () -> [String: Any] in
      PreviewSink.shared.active = false
      self.endResultState()
      let summary = self.coordinator.stop()
      self.coordinator.onSample = nil
      return summary
    }

    // Se a view sumir sem stopSession, a câmera continuaria ligada gastando
    // bateria e aquecendo o aparelho — que é justamente o que o marco mede.
    OnDestroy {
      _ = self.coordinator.stop()
    }
  }

  // MARK: - Transição

  /// A região dos objetos ao vivo, normalizada, com a mesma margem do recorte.
  ///
  /// É a melhor previsão do destino que existe no instante do toque. Errar
  /// um pouco não custa nada: a segunda metade parte de onde esta parar.
  private static func focus(of instances: [Instance], side: Double, margin: Double) -> CGRect? {
    guard side > 0, !instances.isEmpty else { return nil }
    let minX = Double(instances.map(\.x).min()!)
    let minY = Double(instances.map(\.y).min()!)
    let maxX = Double(instances.map { $0.x + $0.width }.max()!)
    let maxY = Double(instances.map { $0.y + $0.height }.max()!)
    let mx = (maxX - minX) * margin, my = (maxY - minY) * margin
    let r = CGRect(x: (minX - mx) / side, y: (minY - my) / side,
                   width: (maxX - minX + 2 * mx) / side, height: (maxY - minY + 2 * my) / side)
    return r.width > 0 && r.height > 0 ? r : nil
  }

  /// O resultado no tamanho em que ele vai aparecer, não no da foto.
  private func screenImage(_ buffer: CVPixelBuffer, fitting pixels: CGSize) -> CGImage? {
    let image = CIImage(cvPixelBuffer: buffer)
    let w = image.extent.width, h = image.extent.height
    guard w > 0, h > 0 else { return nil }
    let scale = pixels.width > 0 && pixels.height > 0
      ? min(1, pixels.width / w, pixels.height / h) : 1
    let scaled = scale < 1
      ? image.applyingFilter("CILanczosScaleTransform", parameters: [
          kCIInputScaleKey: scale, kCIInputAspectRatioKey: 1,
        ])
      : image
    return ciContext.createCGImage(scaled, from: scaled.extent.integral)
  }

  // MARK: - Resultado guardado

  private func keepResult(_ id: String, _ buffer: CVPixelBuffer) {
    keptLock.lock()
    kept = (id: id, buffer: buffer)
    keptLock.unlock()
  }

  private func keptResult() -> (id: String, buffer: CVPixelBuffer)? {
    keptLock.lock()
    defer { keptLock.unlock() }
    return kept
  }

  private func dropResult() {
    keptLock.lock()
    kept = nil
    keptLock.unlock()
  }

  /// Desfaz o estado de resultado sem animar: congelamento, pausa, o
  /// resultado guardado e as camadas dele.
  ///
  /// Uma sessão encerrada no resultado — a aba trocada sem "voltar" — deixaria
  /// congelamento e pausa presos, e a câmera da sessão seguinte nunca
  /// apareceria. (Achado na leitura, não no aparelho.)
  private func endResultState() {
    PreviewSink.shared.frozen = false
    coordinator.results.setPaused(false)
    dropResult()
    PreviewSink.shared.onView {
      $0.result.teardown()
      $0.clearDividers()
    }
  }
}

// MARK: - Da fronteira para os tipos do nativo

private extension ShelfGeometry.Tuning {
  init(_ r: GeometryTuningRecord) {
    self.init(
      standingToleranceRadians: r.standingToleranceDegrees * .pi / 180,
      rowGapFactor: r.rowGapFactor,
      minRowGap: r.minRowGap,
      minBooksPerRow: r.minBooksPerRow,
      fullConfidenceCount: r.fullConfidenceCount,
      maxBaseResidual: r.maxBaseResidual,
      maxAngleSpread: r.maxAngleSpread,
      maxRowSlopeSpread: r.maxRowSlopeSpread,
      withGravity: ShelfGeometry.Weights(r.weightsWithGravity),
      withoutGravity: ShelfGeometry.Weights(r.weightsWithoutGravity))
  }
}

private extension ShelfGeometry.Weights {
  init(_ r: ConfidenceWeightsRecord) {
    self.init(count: r.count, line: r.line, spread: r.spread, rows: r.rows)
  }
}

private extension Rectify.Shelf {
  /// Números, nunca pixels: é o que atravessa a fronteira.
  var dictionary: [String: Any] {
    ["count": count, "dividers": dividers, "top": top, "bottom": bottom]
  }
}
