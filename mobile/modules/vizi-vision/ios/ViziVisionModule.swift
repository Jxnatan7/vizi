import CoreImage
import CoreML
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
  /// A releitura do recorte (spec 006). Desligada, o resultado é a leitura da
  /// foto, como na 005 — e é o que o default faz se o campo não chegar.
  @Field var reread: Bool = false
  /// Fração da área da caixa dentro do recorte sem a margem para contar. O 2
  /// não deixa nenhuma passar: inválido de propósito, como o de cima — a
  /// contagem zerada aparece na primeira foto.
  @Field var rereadMembership: Double = 2
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
  /// Faixa de interesse: escurecimento de 0 a 1; o resto em pontos de tela.
  @Field var bandDimOpacity: Double = 0.55
  /// "#RRGGBB".
  @Field var bandEdgeColor: String = "#FFFFFF"
  @Field var bandEdgeWidth: Double = 1.5
  @Field var bandHandleLength: Double = 28
  @Field var bandHandleThickness: Double = 5
  @Field var bandCountFontSize: Double = 13
}

struct SessionOptions: Record {
  @Field var sampleIntervalMs: Int = 500
  @Field var transform: String = "stretch"
  @Field var confidenceThreshold: Double = 0.25
  @Field var iouThreshold: Double = 0.7
  /// A faixa de interesse. A sessão começa por ela (spec 005, FR-002).
  @Field var band: BandPolicyRecord = BandPolicyRecord()
}

/// Política da coleta (spec 007). Vem do TypeScript — princípio IV.
///
/// **Defaults inválidos de propósito**, como os da faixa: o TypeScript sempre
/// envia todos os campos. Se um dia deixar de enviar, a qualidade zero estraga
/// as imagens à vista e o espaço infinito recusa a primeira marca — o defeito
/// aparece na primeira sessão.
struct CollectionOptionsRecord: Record {
  @Field var minScore: Double = 0
  @Field var minFreeBytes: Double = .infinity
  @Field var jpegQuality: Double = 0
  /// As políticas em vigor, gravadas sem interpretar.
  @Field var policies: [String: Any] = [:]
  /// O que a sessão é — tipo, luz, prateleiras (spec 008, R47). Também sem
  /// interpretar: quem sabe o que é uma prateleira é o TypeScript.
  @Field var session: [String: Any] = [:]
}

/// Comportamento da faixa de interesse. Vira `BandPolicy`.
///
/// **Defaults inválidos de propósito**, como os da T037 da 004: o TypeScript
/// sempre envia todos os campos. Zerada, a faixa nasce sem espessura — o
/// defeito aparece na primeira sessão, em vez de a faixa rodar com um valor
/// plausível e defasado.
struct BandPolicyRecord: Record {
  @Field var defaultThickness: Double = 0
  @Field var minThickness: Double = 0
  @Field var membership: Double = 0
  @Field var flipHysteresisDegrees: Double = 0
  @Field var offMargin: Double = 0
  @Field var rubberBand: Double = 0
  @Field var startSlopPoints: Double = 0
  @Field var edgeGrabPoints: Double = 0
  @Field var countWindowMs: Double = 0
  @Field var springResponse: Double = 0
  @Field var springDamping: Double = 0
  @Field var haptics: Bool = false
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
  /// Muda cada vez que o resultado deixa de valer: nova captura, volta, fim de
  /// sessão. O que uma captura agenda para a thread de interface só vale
  /// enquanto ela for a atual. O `imageId` não bastava: uma foto que chega
  /// depois do fim da sessão guardaria o resultado de novo e passaria pela
  /// guarda (spec 006, FR-011).
  private var resultEpoch = 0

  /// A coleta (spec 007). Vive com o módulo: a sessão de coleta atravessa
  /// sessões de câmera.
  private let collection = CollectionRecorder()
  /// A sessão de câmera rodando, para a telemetria de uma coleta aberta no
  /// meio dela começar com contexto.
  private var cameraInfo: [String: Any]?
  /// Um quadro de marca parado na tela. Guardado pelo `keptLock`.
  private var markFrozen = false

  public func definition() -> ModuleDefinition {
    Name("ViziVision")

    // Emitido a ~2 Hz. Um evento por frame seriam 60 travessias por segundo e
    // 60 re-renders — princípios II e III violados de uma vez.
    // `onBandChange` só em mudança discreta da faixa — nunca durante o
    // arrasto (spec 005, princípio III). `onCollectionChange` também: abrir,
    // fechar, item gravado, resposta gravada (spec 007).
    Events("onTelemetry", "onBandChange", "onCollectionChange")

    OnCreate {
      self.collection.onChange = { [weak self] state in
        self?.sendEvent("onCollectionChange", state)
      }
    }

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
        // Com a coleta aberta, a mesma amostra vira uma linha da sessão (R45).
        self?.collection.appendTelemetry(sample)
      }
      // Configuração vai para o sink, não para a view: ela ainda não existe
      // neste instante, e só nasce quando o JSX reage ao retorno desta função.
      PreviewSink.shared.store = self.coordinator.results
      PreviewSink.shared.band = self.coordinator.band
      PreviewSink.shared.imageSide = CGFloat(self.engine.inputWidth)
      PreviewSink.shared.active = true
      self.coordinator.band.onChange = { [weak self] band in
        self?.sendEvent("onBandChange", band.dictionary)
      }
      let info = try self.coordinator.start(
        sampleIntervalMs: options.sampleIntervalMs,
        mode: TransformMode(rawValue: options.transform) ?? .stretch,
        confidenceThreshold: Float(options.confidenceThreshold),
        iouThreshold: Float(options.iouThreshold),
        bandPolicy: BandPolicy(options.band))
      // O JavaScript espelha a faixa desde o primeiro frame. Se a view já
      // existir, ela recomeça no centro junto.
      self.coordinator.band.commit()
      PreviewSink.shared.onView {
        $0.applyBand(animated: false)
        $0.setBandVisible(true, animated: false)
      }
      self.cameraInfo = info
      self.collection.cameraEvent("cameraStart", info: info)
      return info
    }

    AsyncFunction("setTransform") { (transform: String) in
      self.coordinator.mode = TransformMode(rawValue: transform) ?? .stretch
    }

    // A cápsula (spec 005). Na thread de interface, onde a faixa se desenha:
    // o modelo muda na hora, a mola e o retorno tátil saem daqui, e
    // `onBandChange` só quando a faixa chega (tabela do `setBandMode` no
    // contrato).
    AsyncFunction("setBandMode") { (raw: String) in
      guard let mode = BandMode(rawValue: raw) else { return }
      // Um dedo ainda na faixa termina aqui, dentro dos limites: a troca parte
      // do estado assentado, e o gesto não escreve mais nada por cima dela.
      PreviewSink.shared.view?.finishBandGesture()
      guard let change = self.coordinator.band.setMode(mode) else { return }
      guard let view = PreviewSink.shared.view else {
        // Sem view, não há mola a esperar.
        self.coordinator.band.commit()
        return
      }
      view.transitionBand(to: change.to)
    }.runOnQueue(.main)

    // MARK: - Captura (marco 4)

    // `tags` é a escolha da câmera no toque (spec 008, R47): argumento, e não
    // estado guardado aqui, para o item gravar exatamente o que valia no toque.
    AsyncFunction("capture") { (options: CaptureOptions, tags: [String: Any]?) -> [String: Any] in
      let touchedAt = CFAbsoluteTimeGetCurrent()
      self.transitionMs = options.transitionMs

      // A chave do resultado para o `saveResult`. A captura nova descarta a
      // anterior mesmo que falhe: salvar depois disso gravaria a foto errada.
      let imageId = UUID().uuidString
      let captureEpoch = self.dropResult()

      // A coleta (spec 007) decide no toque, como a faixa. Sem espaço, a
      // captura acontece igual e só não é gravada (FR-020). Nada do que ela
      // guarda muda um valor calculado aqui, nem acontece antes do `readyMs`
      // (FR-003): o rastro só junta referências, e a gravação vai para a fila
      // da coleta depois do retorno montado.
      let collecting = self.collection.isOpen
      let recording = collecting && self.collection.hasSpace()

      // A faixa do instante do toque vale para a captura inteira: mexer nela
      // durante a foto não muda o que já foi decidido (spec 005). A faixa sai
      // de cena, e o gesto desliga junto (FR-020).
      let bandAtTouch = self.coordinator.band.read()
      let bandSide = Float(self.engine.inputWidth)
      let membership = bandAtTouch.policy.membership
      PreviewSink.shared.onView { $0.setBandVisible(false, animated: true) }

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
            of: bandAtTouch.band.members(
              of: self.coordinator.results.read().instances,
              imageSide: bandSide, membership: membership),
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

        // Só os objetos da faixa daqui em diante — contagem, geometria, recorte
        // e overlay (FR-006). A faixa vale para a foto como para o ao vivo: as
        // duas passaram pela mesma transformação para o espaço canônico.
        let instances = bandAtTouch.band.members(
          of: result.instances, imageSide: bandSide, membership: membership)
        let outsideBandCount = result.instances.count - instances.count

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
        /// O recorte, endireitado ou só girado, como vai para a tela. É o que a
        /// releitura lê (spec 006). Guardado também no diagnóstico, que mostra
        /// outra coisa: a contagem não pode mudar com o modo (FR-010).
        var cutout: (buffer: CVPixelBuffer, books: CGRect)?
        /// O que a coleta guarda da geometria (spec 007), com as chaves do
        /// formato, preenchido onde cada valor nasce. Só leitura: nenhum
        /// valor de cima muda por causa dele.
        var traceGeometry: [String: Any] = [:]
        var traceGravity: DeviceAttitude.Gravity?

        if let protos = result.protos {
          // A atitude é amostrada NO disparo, não depois: medir a inclinação
          // um instante mais tarde é medir outro momento.
          let gravity = self.coordinator.attitude.snapshot()
          traceGravity = gravity
          let photoW = Double(CVPixelBufferGetWidth(shot.buffer))
          let photoH = Double(CVPixelBufferGetHeight(shot.buffer))
          let focal = Projective.Focal.from(
            fieldOfViewDegrees: self.coordinator.fieldOfView,
            sensorLongSide: max(photoW, photoH),
            portraitWidth: min(photoW, photoH),
            portraitHeight: max(photoW, photoH),
            canonicalSide: Double(side))
          traceGeometry["focal"] = ["x": focal.x, "y": focal.y]

          let estimate = ShelfGeometry.estimate(
            instances: instances,
            protos: protos,
            imageSide: side,
            gravity: gravity,
            focal: focal,
            minInstances: options.minInstancesForGeometry,
            minConfidence: options.minGeometryConfidence,
            tuning: ShelfGeometry.Tuning(options.geometry))

          // Fileiras e deitados em âncoras, a chave das junções no zip (R38).
          let anchor = { (i: Int) -> Int? in
            instances.indices.contains(i) ? instances[i].anchorIndex : nil
          }
          traceGeometry["rows"] = estimate.rows.map { $0.indices.compactMap(anchor) }
          traceGeometry["lying"] = estimate.lying.compactMap(anchor)

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
          let region = instances.flatMap { inst -> [CGPoint] in
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
            traceGeometry["horizon"] = CollectionTrace.homogeneous(horizonPortrait)

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
            traceGeometry["horizontalVP"] = CollectionTrace.homogeneous(horizontalVP)

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
              cutout = (rendered, out.books)
              traceGeometry["verticalVP"] = CollectionTrace.homogeneous(out.verticalVP)
              traceGeometry["sourceQuad"] = out.sourceQuad.map { [Double($0.x), Double($0.y)] }
              traceGeometry["books"] = CollectionTrace.rect(out.books)
              traceGeometry["fullyRectified"] = out.fullyRectified
              // O motivo da estimativa vem antes do da retificação. "Poucos
              // livros" diz à pessoa o que fazer diferente; "sem ponto de
              // fuga" é só a consequência dele, e era o que aparecia.
              declineReason = out.fullyRectified
                ? ""
                : "só rotação — \(estimate.declineReason ?? out.fallbackReason ?? "motivo desconhecido")"

              if options.diagnostics {
                // Os livros que a faixa descartou, no espaço do retrato: sem
                // eles, "contou errado" e "a faixa cortou" parecem iguais
                // (FR-022).
                let discarded = result.instances
                  .filter { !bandAtTouch.band.contains($0, imageSide: bandSide, membership: membership) }
                  .map { CGRect(x: CGFloat($0.x) * kx, y: CGFloat($0.y) * ky,
                                width: CGFloat($0.width) * kx, height: CGFloat($0.height) * ky) }
                // Sobre a foto CRUA: horizonte, pontos de fuga, recorte e a
                // curva. Uma captura passa a dizer qual etapa falhou.
                if let diag = Diagnostics.draw(
                  portrait: portrait, context: self.ciContext,
                  horizon: horizonPortrait, verticalVP: out.verticalVP,
                  horizontalVP: horizontalVP, cropQuad: out.sourceQuad,
                  scores: azimuthScores, band: bandAtTouch.band, discarded: discarded) {
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
                    instances.indices.contains($0) ? instances[$0] : nil
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
        self.keepResult(imageId, displayBuffer, epoch: captureEpoch)

        // O overlay ao vivo não vale sobre a imagem endireitada — as
        // coordenadas são de outro espaço. Limpa em vez de desenhar errado; as
        // caixas do recorte vêm da releitura, adiante.
        if imageReplaced {
          self.coordinator.results.publishOverriding(instances: [], protos: nil)
        } else {
          self.coordinator.results.publishOverriding(
            instances: instances, protos: result.protos)
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
        PreviewSink.shared.onView {
          $0.result.settle(destination, durationMs: options.transitionMs)
        }
        // O resultado está na tela e a transição começou: é aqui que o SC-001
        // da 004 para de contar. A releitura corre por baixo dela (R29).
        let readyMs = (CFAbsoluteTimeGetCurrent() - touchedAt) * 1000

        // ── A releitura (spec 006) ────────────────────────────────────────
        //
        // Por último, o modelo lê o recorte como a tela o mostra, e só o que
        // ele encontra é o resultado (FR-002). Sem recorte na tela, com a
        // releitura desligada ou se ela falhar, vale a leitura da foto — que,
        // sem recorte, já é a da imagem exibida (FR-008, FR-012).
        var reading = Reread.Outcome(
          instances: instances, protos: result.protos, shelves: shelves,
          rowCount: shelfCount, lyingCount: lyingCount)
        var countSource = "photo"
        var rereadMs = 0.0
        // As divisões da foto estão normalizadas no recorte ENDIREITADO. Sobre
        // a canônica ou o diagnóstico cairiam em outro espaço — lá, nenhuma.
        var drawn = straightened && !options.diagnostics ? shelves : []
        /// O que a releitura põe no overlay. Nada quando ela não valeu: a
        /// leitura da foto já foi publicada acima.
        var republish: (instances: [Instance], protos: MLMultiArray?)?

        if options.reread, let cutout {
          let started = CFAbsoluteTimeGetCurrent()
          if let outcome = try? self.reread(cutout.buffer, books: cutout.books, options: options) {
            rereadMs = (CFAbsoluteTimeGetCurrent() - started) * 1000
            reading = outcome
            countSource = "reread"
            // As da releitura estão no recorte que está na tela, endireitado
            // ou só girado (FR-007). No diagnóstico, nada dela aparece (FR-010).
            if options.diagnostics {
              drawn = []
              republish = (instances: [], protos: nil)
            } else {
              drawn = outcome.shelves
              republish = (instances: outcome.instances, protos: outcome.protos)
            }
          }
        }

        // Um bloco só, e só enquanto esta captura for a atual: a volta e o fim
        // da sessão invalidam o que ela agendou (FR-011, R29).
        let dividers = drawn
        let boxes = republish
        DispatchQueue.main.async { [weak self] in
          guard let self, self.isCurrent(captureEpoch) else { return }
          if let boxes {
            self.coordinator.results.publishOverriding(instances: boxes.instances,
                                                       protos: boxes.protos)
          }
          // Por baixo da transição: aparecem quando ela termina (FR-008 da 004).
          PreviewSink.shared.view?.showDividers(dividers, imageSize: shown)
        }

        /// O que a tela recebe — e o que a coleta grava como `result`.
        let shownResult: [String: Any] = [
          "count": reading.instances.count,
          "countSource": countSource,
          "straightened": straightened,
          "declineReason": declineReason,
          "geometryConfidence": confidence,
          "azimuthConfidence": azimuth,
          "shelves": reading.shelves.map(\.dictionary),
          "shelfCount": reading.rowCount,
          "lyingCount": reading.lyingCount,
          "usedGravity": usedGravity,
          "outsideBandCount": outsideBandCount,
        ]

        // ── A coleta (spec 007) ───────────────────────────────────────────
        //
        // O resultado já está montado; daqui só saem referências para a fila
        // da coleta, que decodifica a 0,05, codifica e escreve em segundo
        // plano (R38, R40). Nada aqui lança: um rastro torto não derruba a
        // captura.
        var itemId: String?
        if recording {
          var geometry: [String: Any] = [
            "fieldOfViewDegrees": self.coordinator.fieldOfView,
            "focal": NSNull(), "horizon": NSNull(), "verticalVP": NSNull(),
            "horizontalVP": NSNull(), "sourceQuad": [Any](), "books": NSNull(),
            "fullyRectified": false, "rows": [Any](), "lying": [Any](),
            "azimuthScores": azimuthScores,
          ]
          for (key, value) in traceGeometry { geometry[key] = value }

          let trace = CollectionTrace.Capture(
            thresholds: self.currentThresholds(),
            transform: self.coordinator.mode.rawValue,
            side: side,
            maskCoeffCount: self.engine.maskCoeffCount,
            options: options.collectionDictionary,
            photo: shot.buffer,
            photoSquare: square,
            photoRun: result,
            band: bandAtTouch.band,
            membership: membership,
            gravity: traceGravity,
            geometry: geometry,
            crop: cutout?.buffer,
            reread: countSource == "reread" ? reading.trace : nil,
            result: shownResult,
            timings: ["elapsedMs": shot.elapsedMs, "readyMs": readyMs, "rereadMs": rereadMs],
            tags: tags)
          itemId = self.collection.record(capture: trace, prefill: reading.instances.count)
        }

        var response = shownResult
        response["rereadMs"] = rereadMs
        response["azimuthScores"] = azimuthScores
        response["imageId"] = imageId
        response["elapsedMs"] = shot.elapsedMs
        response["readyMs"] = readyMs
        response["photoWidth"] = CVPixelBufferGetWidth(shot.buffer)
        response["photoHeight"] = CVPixelBufferGetHeight(shot.buffer)
        response["instances"] = reading.instances.count
        response["collectionItemId"] = itemId.map { $0 as Any } ?? NSNull()
        response["collectionSkipped"] = collecting && !recording ? "space" as Any : NSNull()
        return response
      } catch {
        PreviewSink.shared.onView {
          $0.result.teardown()
          $0.clearDividers()
          // Sem resultado, a faixa volta como estava.
          $0.setBandVisible(true, animated: true)
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
      // A captura que esperava resposta fica sem ela (spec 007, R43).
      self.collection.releaseAwaiting()
      DispatchQueue.main.async {
        // As divisões saem neste mesmo quadro: a transição reaparece por cima
        // delas, e depois dela vem a câmera ao vivo.
        PreviewSink.shared.view?.clearDividers()
        PreviewSink.shared.view?.result.dismiss(durationMs: duration)
        // Esvaziar antes de soltar a pausa: as caixas do resultado ficariam
        // sobre o ao vivo até o primeiro frame novo (spec 006, FR-011).
        self.coordinator.results.clear()
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
      style.bandDimOpacity = CGFloat(record.bandDimOpacity)
      if let color = UIColor(hex: record.bandEdgeColor)?.cgColor {
        style.bandEdgeColor = color
      }
      style.bandEdgeWidth = CGFloat(record.bandEdgeWidth)
      style.bandHandleLength = CGFloat(record.bandHandleLength)
      style.bandHandleThickness = CGFloat(record.bandHandleThickness)
      style.bandCountFontSize = CGFloat(record.bandCountFontSize)
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
      self.collection.cameraEvent("cameraStop")
      self.cameraInfo = nil
      return summary
    }

    // MARK: - Coleta (spec 007)

    Function("getCollectionState") { () -> [String: Any] in
      self.collection.state()
    }

    AsyncFunction("startCollection") { (options: CollectionOptionsRecord) -> [String: Any] in
      // O modelo vai identificado no `session.json`: carregar antes, como a
      // sessão de câmera faz.
      if !self.engine.isLoaded { try self.engine.load() }
      // O que a sessão é vai para o topo do `session.json`, ao lado do app e do
      // modelo (spec 008). Só estas chaves: o resto do topo é do formato.
      var meta = self.collectionMeta()
      for key in CollectionRecorder.sessionKeys {
        meta[key] = options.session[key] ?? NSNull()
      }
      return try self.collection.start(
        policy: CollectionRecorder.Policy(
          minScore: Float(options.minScore),
          minFreeBytes: options.minFreeBytes,
          jpegQuality: options.jpegQuality),
        policies: options.policies,
        meta: meta,
        cameraInfo: self.coordinator.isRunning ? self.cameraInfo : nil)
    }

    AsyncFunction("stopCollection") { () -> [String: Any] in
      self.collection.stop(reason: "stopped")
    }

    AsyncFunction("answerItem") { (itemId: String, count: Int?) in
      try self.collection.answer(itemId, count: count)
    }

    AsyncFunction("listCollections") { () -> [[String: Any]] in
      self.collection.list()
    }

    AsyncFunction("renameCollection") { (id: String, name: String) in
      try self.collection.rename(id, name: name)
    }

    AsyncFunction("deleteCollection") { (id: String) in
      try self.collection.delete(id)
    }

    // O zip sai pela fila da coleta; o menu, pela thread de interface. A
    // promessa resolve quando o menu fecha (R44).
    AsyncFunction("exportCollection") { (id: String) async throws -> [String: Any] in
      let exported = try await self.collection.exportZip(id)
      let shared = await self.share(exported)
      return ["file": exported.relative, "bytes": exported.bytes, "shared": shared]
    }

    // Marcar (R37): o próximo quadro processado, com a tela parada nele.
    AsyncFunction("markFrame") { (tags: [String: Any]?) async throws -> [String: Any] in
      guard self.collection.isOpen else { throw CollectionRecorder.RecorderError.closed }
      guard self.coordinator.isRunning else { throw CollectionRecorder.RecorderError.camera }
      // Congelado é captura em andamento, resultado ou outro quadro parado.
      guard !PreviewSink.shared.frozen else { throw CollectionRecorder.RecorderError.busy }
      guard self.collection.hasSpace() else { throw CollectionRecorder.RecorderError.space }

      // A contagem que a tela mostrava no toque, e a faixa travada: mexer nela
      // com o quadro parado mudaria o que aparece.
      let displayed = await MainActor.run { () -> Int? in
        let view = PreviewSink.shared.view
        view?.setBandLocked(true)
        return view?.bandRenderer.displayedCount
      }

      let frame: CollectionTrace.LiveFrame
      do {
        frame = try await self.coordinator.nextFrame()
      } catch CollectionRecorder.RecorderError.busy {
        // Outra marca já espera ou está parada: a faixa é dela, e continua
        // travada.
        throw CollectionRecorder.RecorderError.busy
      } catch {
        await MainActor.run { PreviewSink.shared.view?.setBandLocked(false) }
        throw error
      }
      self.setMarkFrozen(true)
      // O preview já mostra este quadrado: ele foi empurrado antes da
      // inferência, e o congelamento veio logo depois dela, na mesma fila.
      // Reenviar só garante.
      PreviewSink.shared.showStill(frame.square)

      let side = self.engine.inputWidth
      let frameCount = frame.band.members(
        of: frame.run.instances, imageSide: Float(side), membership: frame.membership).count
      let mark = CollectionTrace.Mark(
        frame: frame, displayedCount: displayed, frameCount: frameCount,
        thresholds: self.currentThresholds(), transform: self.coordinator.mode.rawValue,
        side: side, maskCoeffCount: self.engine.maskCoeffCount, tags: tags)
      guard let itemId = self.collection.record(mark: mark, prefill: displayed ?? frameCount) else {
        // A sessão fechou no meio do caminho.
        self.resumeFromMark()
        throw CollectionRecorder.RecorderError.closed
      }
      return [
        "itemId": itemId,
        "displayedCount": displayed.map { $0 as Any } ?? NSNull(),
        "frameCount": frameCount,
      ]
    }

    AsyncFunction("resumeLive") {
      self.collection.releaseAwaiting()
      self.resumeFromMark()
    }

    // Se a view sumir sem stopSession, a câmera continuaria ligada gastando
    // bateria e aquecendo o aparelho — que é justamente o que o marco mede.
    OnDestroy {
      _ = self.coordinator.stop()
    }
  }

  // MARK: - Releitura (spec 006)

  /// O recorte, encaixado no quadrado como a tela o mostra, lido pelo modelo.
  ///
  /// O que sai daqui é o resultado (FR-002): as caixas e as máscaras que
  /// passaram pela regra das bordas, e as fileiras e divisões delas no espaço
  /// do recorte.
  ///
  /// - Parameter books: onde os livros ficam no recorte, de 0 a 1 — o recorte
  ///   sem a margem, medido pelo `PlaneRectifier`.
  private func reread(
    _ cutout: CVPixelBuffer, books: CGRect, options: CaptureOptions
  ) throws -> Reread.Outcome {
    let side = engine.inputWidth
    let square = try coordinator.squareFromCutout(cutout, side: side)
    // Os mesmos limiares do ao vivo e da foto (FR-003).
    let run = try engine.run(
      on: square.buffer,
      confidenceThreshold: coordinator.confidenceThreshold,
      iouThreshold: coordinator.iouThreshold)

    let core = Reread.core(of: square.content, books: books)
    let inside = Reread.inside(run.instances, core: core, membership: options.rereadMembership)

    // Fileiras e deitados pela mesma `ShelfGeometry` da foto, sem gravidade:
    // numa imagem reta, o eixo médio das lombadas é a vertical (R33). Sem
    // gravidade, a focal não entra na conta.
    var rows: [ShelfGeometry.Row] = []
    var lying: [Int] = []
    var lyingCount = 0
    if let protos = run.protos {
      let estimate = ShelfGeometry.estimate(
        instances: inside,
        protos: protos,
        imageSide: side,
        gravity: nil,
        focal: Projective.Focal(x: Double(side), y: Double(side)),
        // Fileira não precisa de quadrilátero: um livro já é uma. O mínimo da
        // geometria deixaria uma prateleira de três livros sem divisões.
        minInstances: 1,
        minConfidence: options.minGeometryConfidence,
        tuning: ShelfGeometry.Tuning(options.geometry))
      rows = estimate.rows
      lying = estimate.lying
      lyingCount = estimate.lying.count
    }

    // Fileiras e deitados em âncoras, que é a chave das junções no zip (R38).
    let anchor = { (i: Int) -> Int? in inside.indices.contains(i) ? inside[i].anchorIndex : nil }
    return Reread.Outcome(
      instances: inside,
      protos: run.protos,
      shelves: Reread.shelves(rows, of: inside, content: square.content,
                              edge: options.dividerEdgeMargin),
      rowCount: rows.count,
      lyingCount: lyingCount,
      trace: CollectionTrace.RereadTrace(
        square: square.buffer, content: square.content, core: core,
        membership: options.rereadMembership, run: run,
        rows: rows.map { $0.indices.compactMap(anchor) },
        lying: lying.compactMap(anchor)))
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

  /// Uma captura que já não é a atual não guarda nada: a sessão acabou, ou a
  /// pessoa voltou, enquanto ela terminava.
  private func keepResult(_ id: String, _ buffer: CVPixelBuffer, epoch: Int) {
    keptLock.lock()
    if resultEpoch == epoch { kept = (id: id, buffer: buffer) }
    keptLock.unlock()
  }

  private func isCurrent(_ epoch: Int) -> Bool {
    keptLock.lock()
    defer { keptLock.unlock() }
    return resultEpoch == epoch
  }

  private func keptResult() -> (id: String, buffer: CVPixelBuffer)? {
    keptLock.lock()
    defer { keptLock.unlock() }
    return kept
  }

  /// Descarta o resultado guardado e invalida o que a captura dele ainda
  /// tiver agendado. Devolve a época nova.
  @discardableResult
  private func dropResult() -> Int {
    keptLock.lock()
    defer { keptLock.unlock() }
    kept = nil
    resultEpoch &+= 1
    return resultEpoch
  }

  /// Desfaz o estado de resultado sem animar: congelamento, pausa, o
  /// resultado guardado e as camadas dele.
  ///
  /// Uma sessão encerrada no resultado — a aba trocada sem "voltar" — deixaria
  /// congelamento e pausa presos, e a câmera da sessão seguinte nunca
  /// apareceria. (Achado na leitura, não no aparelho.)
  private func endResultState() {
    // Primeiro invalidar: o que a captura agendou deixa de valer antes de a
    // limpeza acontecer (spec 006, FR-011).
    dropResult()
    // Um quadro de marca parado sai junto, e o item dele fica sem resposta
    // (spec 007).
    setMarkFrozen(false)
    collection.releaseAwaiting()
    PreviewSink.shared.frozen = false
    // A sessão seguinte não herda as caixas do resultado.
    coordinator.results.clear()
    coordinator.results.setPaused(false)
    PreviewSink.shared.onView {
      $0.result.teardown()
      $0.clearDividers()
      $0.setBandLocked(false)
    }
  }

  // MARK: - Coleta (spec 007)

  /// App, aparelho e modelo, para o `session.json` (R45).
  private func collectionMeta() -> [String: Any] {
    let info = Bundle.main.infoDictionary ?? [:]
    var system = utsname()
    uname(&system)
    let machine = withUnsafeBytes(of: &system.machine) { raw in
      String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
    }
    let os = ProcessInfo.processInfo.operatingSystemVersion
    return [
      "app": [
        "version": info["CFBundleShortVersionString"] ?? NSNull(),
        "build": info["CFBundleVersion"] ?? NSNull(),
      ] as [String: Any],
      "device": [
        "model": machine,
        "os": "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
      ] as [String: Any],
      "model": [
        "identifier": "vizi-seg",
        "inputWidth": engine.inputWidth,
        "inputHeight": engine.inputHeight,
        "weightsSha256": engine.weightsDigest.map { $0.sha256 as Any } ?? NSNull(),
        "weightsSource": engine.weightsDigest.map { $0.source as Any } ?? NSNull(),
        "metadata": engine.modelMetadata,
      ] as [String: Any],
    ]
  }

  /// Os limiares em vigor agora: os da sessão e o de aparência do overlay.
  private func currentThresholds() -> CollectionTrace.Thresholds {
    CollectionTrace.Thresholds(
      confidence: coordinator.confidenceThreshold,
      iou: coordinator.iouThreshold,
      appearance: PreviewSink.shared.style.minConfidence)
  }

  /// O menu de compartilhar, a partir do controlador atual do Expo.
  @MainActor
  private func share(_ exported: CollectionRecorder.Exported) async -> Bool {
    guard let presenter = appContext?.utilities?.currentViewController() else { return false }
    return await CollectionExport.share(exported.zip, named: exported.shareName, from: presenter)
  }

  private func setMarkFrozen(_ value: Bool) {
    keptLock.lock()
    markFrozen = value
    keptLock.unlock()
  }

  /// Solta o quadro parado de uma marca: esvazia o overlay antes de soltar a
  /// pausa — as caixas do quadro ficariam sobre o ao vivo até o primeiro frame
  /// novo, como na volta do resultado —, descongela e destrava a faixa.
  private func resumeFromMark() {
    keptLock.lock()
    let wasFrozen = markFrozen
    markFrozen = false
    keptLock.unlock()
    guard wasFrozen else { return }
    DispatchQueue.main.async {
      self.coordinator.results.clear()
      self.coordinator.results.setPaused(false)
      PreviewSink.shared.frozen = false
      PreviewSink.shared.view?.setBandLocked(false)
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

private extension BandPolicy {
  init(_ r: BandPolicyRecord) {
    self.init(
      defaultThickness: r.defaultThickness,
      minThickness: r.minThickness,
      membership: r.membership,
      flipHysteresisDegrees: r.flipHysteresisDegrees,
      offMargin: r.offMargin,
      rubberBand: r.rubberBand,
      startSlopPoints: r.startSlopPoints,
      edgeGrabPoints: r.edgeGrabPoints,
      countWindowMs: r.countWindowMs,
      springResponse: r.springResponse,
      springDamping: r.springDamping,
      haptics: r.haptics)
  }
}

private extension CaptureOptions {
  /// As opções como chegaram, para o `item.json` da coleta (spec 007, R45).
  /// Campo a campo: o que a captura usou fica registrado com ela, porque muda
  /// no meio de uma sessão — o diagnóstico, por exemplo.
  var collectionDictionary: [String: Any] {
    let g = geometry
    let weights = { (w: ConfidenceWeightsRecord) -> [String: Any] in
      ["count": w.count, "line": w.line, "spread": w.spread, "rows": w.rows]
    }
    return [
      "cropMargin": cropMargin,
      "minInstancesForGeometry": minInstancesForGeometry,
      "minGeometryConfidence": minGeometryConfidence,
      "approachMs": approachMs,
      "transitionMs": transitionMs,
      "diagnostics": diagnostics,
      "geometry": [
        "standingToleranceDegrees": g.standingToleranceDegrees,
        "rowGapFactor": g.rowGapFactor,
        "minRowGap": g.minRowGap,
        "minBooksPerRow": g.minBooksPerRow,
        "fullConfidenceCount": g.fullConfidenceCount,
        "maxBaseResidual": g.maxBaseResidual,
        "maxAngleSpread": g.maxAngleSpread,
        "maxRowSlopeSpread": g.maxRowSlopeSpread,
        "weightsWithGravity": weights(g.weightsWithGravity),
        "weightsWithoutGravity": weights(g.weightsWithoutGravity),
      ] as [String: Any],
      "dividerEdgeMargin": dividerEdgeMargin,
      "reread": reread,
      "rereadMembership": rereadMembership,
    ]
  }
}

private extension Rectify.Shelf {
  /// Números, nunca pixels: é o que atravessa a fronteira.
  var dictionary: [String: Any] {
    ["count": count, "dividers": dividers, "top": top, "bottom": bottom]
  }
}
