import QuartzCore
import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Quem hospeda a faixa — a `PreviewView`. O reconhecedor só acompanha os
/// dedos; ler e escrever a faixa, desenhar e vibrar são do hospedeiro.
protocol BandGestureHost: AnyObject {
  /// O quadrado da imagem canônica na view: é nele que a faixa vive.
  var bandImageRect: CGRect { get }
  var bandPolicy: BandPolicy { get }
  /// A faixa do modelo, sem efeito nenhum. `nil` antes da primeira sessão.
  var currentBand: Band? { get }
  /// Começo do gesto: prepara o retorno tátil e devolve a faixa que está na
  /// tela — desligada inclusive —, parando qualquer mola no meio. `nil`
  /// quando não há faixa.
  func beginBandGesture() -> Band?
  /// A faixa que está na tela agora, parando a mola que houver.
  func presentedBand() -> Band
  /// No ritmo do dedo: escreve sem avisar o JavaScript e desenha sem animar.
  func moveBand(to band: Band)
  /// Uma mudança de estado no meio do gesto — criar, renascer, virar —: uma
  /// mola com retorno tátil, também sem avisar o JavaScript.
  func springBand(to band: Band)
  /// Os dedos abriram a faixa além da imagem: ela se desliga, com retorno
  /// tátil, e religar pela cápsula volta a `previous`.
  func switchOffBand(remembering previous: Band)
  /// A faixa encostou num limite pela primeira vez neste gesto.
  func bandTouchedLimit()
  /// Fim do gesto: leva a faixa a `final` — numa mola, se o elástico a deixou
  /// além de um limite — e avisa quem espelha, uma vez só.
  func endBandGesture(settleTo final: Band?)
}

/// Um reconhecedor para um e dois dedos (spec 005, R18).
///
/// Reconhecedores separados de arrasto e pinça trocariam de dono no instante
/// em que o segundo dedo pousa, e esse é o gesto principal da spec. Com um dono
/// só, a passagem é contínua.
///
/// Só começa depois que o dedo anda `startSlopPoints`, ou quando pousa o
/// segundo dedo: um toque simples não é engolido, e os dois toques de voltar ao
/// centro chegam a quem os reconhece.
///
/// Os estados são os do data-model: um dedo move a faixa inteira ou só uma
/// borda; dois seguram a faixa, e o eixo deles decide a orientação; abertos
/// além da imagem, desligam; numa faixa desligada, criam.
final class BandGestureRecognizer: UIGestureRecognizer {
  weak var host: BandGestureHost?

  /// Por onde um dedo segura a faixa (FR-007, FR-008). Dois dedos seguram a
  /// faixa inteira.
  private enum Grip { case whole, lowerEdge, upperEdge }

  /// Os toques acompanhados, na ordem em que pousaram. No máximo dois.
  private var tracked: [UITouch] = []
  /// Onde o primeiro dedo pousou. É dali que a faixa passa a acompanhá-lo.
  private var touchDown = CGPoint.zero
  private var grip = Grip.whole

  /// A referência: a faixa que os dedos ditavam quando ela foi tomada — antes
  /// do elástico — e onde eles estavam.
  private var anchorRaw: Band?
  /// Com um dedo, onde ele está; com dois, o meio deles — no eixo da faixa.
  private var anchorFinger = 0.0
  /// A distância entre os dois dedos quando a pinça começou a valer.
  private var anchorSpan: CGFloat = 1

  /// O que os dedos ditam agora, sem limite nenhum.
  private var rawBand: Band?
  /// O que está na tela: `rawBand` depois do elástico.
  private var shownBand: Band?
  /// A faixa quando o gesto começou. Se ele a desligar, é a ela que a cápsula
  /// religa.
  private var startBand = Band(mode: .off, center: 0.5, thickness: 0)
  /// Desligada pelos dedos. Eles continuam acompanhados: voltar no mesmo gesto
  /// faz a faixa renascer (FR-012).
  private var switchedOff = false
  /// Depois de uma mola no meio do gesto, os dedos esperam até este instante;
  /// então o gesto recomeça de onde a faixa chegou (R22).
  private var settleUntil: CFTimeInterval?
  /// Os dedos pousaram já do lado de lá da diagonal: a faixa não vira no toque
  /// (FR-009). Vira quando eles saírem dali e voltarem.
  private var flipHeld = false
  /// Limites já sentidos neste gesto: o toque leve vem uma vez de cada.
  private var feltEdge = false
  private var feltMinimum = false

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    super.touchesBegan(touches, with: event)
    for touch in touches where tracked.count < 2 {
      tracked.append(touch)
    }
    if state == .possible, let first = tracked.first {
      touchDown = first.location(in: view)
    }
    guard tracked.count == 2, let host else { return }
    switch state {
    case .possible:
      // Dois dedos nunca são um toque: o gesto começa na hora, sem folga.
      guard let band = host.beginBandGesture() else {
        state = .failed
        return
      }
      startBand = band
      state = .began
      if band.mode == .off {
        create()
      } else {
        reanchor(from: band)
      }
    case .began, .changed:
      if switchedOff {
        create()
      } else if settleUntil == nil, let shown = shownBand {
        // De um dedo para dois: a pinça parte do que está na tela.
        reanchor(from: shown)
      }
    default:
      break
    }
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
    super.touchesMoved(touches, with: event)
    guard let host else { return }
    switch state {
    case .possible:
      beginDragIfMoved(host)
    case .began, .changed:
      state = .changed
      if let until = settleUntil {
        // A mola ainda está no caminho: os dedos esperam ela chegar.
        guard CACurrentMediaTime() >= until else { return }
        settleUntil = nil
        reanchor(from: host.presentedBand())
      }
      step()
    default:
      break
    }
  }

  override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
    super.touchesEnded(touches, with: event)
    lift(touches, cancelled: false)
  }

  override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
    super.touchesCancelled(touches, with: event)
    lift(touches, cancelled: true)
  }

  override func reset() {
    super.reset()
    tracked.removeAll()
    grip = .whole
    anchorRaw = nil
    rawBand = nil
    shownBand = nil
    startBand = Band(mode: .off, center: 0.5, thickness: 0)
    switchedOff = false
    settleUntil = nil
    flipHeld = false
    feltEdge = false
    feltMinimum = false
  }

  /// Termina o gesto por fora — a cápsula, a captura —, como se os dedos
  /// tivessem saído: a faixa volta para dentro dos limites, e o gesto não
  /// escreve mais nada por cima de quem o interrompeu.
  func finish() {
    guard state == .began || state == .changed else { return }
    complete(cancelled: true)
  }

  // MARK: - Um quadro

  /// Um dedo só começa depois da folga, e só se houver faixa para mexer.
  /// Desligada, o reconhecedor espera: o segundo dedo ainda pode vir criá-la.
  private func beginDragIfMoved(_ host: BandGestureHost) {
    guard let finger = tracked.first else { return }
    let point = finger.location(in: view)
    let slop = CGFloat(host.bandPolicy.startSlopPoints)
    guard hypot(point.x - touchDown.x, point.y - touchDown.y) >= slop,
          let current = host.currentBand, current.mode != .off else { return }
    guard let band = host.beginBandGesture(), band.mode != .off else {
      state = .failed
      return
    }
    startBand = band
    grip = pickGrip(at: touchDown, on: band, policy: host.bandPolicy)
    // A referência é o ponto do toque, não o de agora: a faixa fica colada no
    // dedo, e a folga não vira distância perdida.
    reanchor(from: band, finger: touchDown)
    state = .began
    step()
  }

  /// O que os dedos ditam neste quadro, e o que a faixa faz com isso.
  private func step() {
    guard let host, let base = anchorRaw else { return }
    let policy = host.bandPolicy
    let raw: Band
    if case let (a, b)? = fingers {
      if !switchedOff, flipIfCrossed(a, b, policy: policy) { return }
      raw = pinched(base, a, b)
    } else if !switchedOff, let finger = tracked.first {
      raw = dragged(base, to: finger.location(in: view))
    } else {
      // Um dedo numa faixa desligada não tem o que mexer.
      return
    }
    rawBand = raw

    if switchedOff {
      // Voltar os dedos até uma borda entrar na imagem faz a faixa renascer.
      // Desligar pede passar `offMargin` além dela; a diferença é a folga que
      // não deixa a faixa ligar e desligar tremulando.
      if raw.lower >= 0 || raw.upper <= 1 { revive(raw, policy: policy) }
      return
    }
    if tracked.count == 2, raw.lower < -policy.offMargin, raw.upper > 1 + policy.offMargin {
      // As duas bordas além da imagem: a faixa se desliga (FR-012).
      switchedOff = true
      host.switchOffBand(remembering: startBand)
      return
    }
    feel(raw, policy: policy)
    let shown = elastic(raw, limit: limit(raw, policy: policy), policy: policy)
    shownBand = shown
    host.moveBand(to: shown)
  }

  /// Toma a referência a partir do que está na tela: a faixa que os dedos
  /// passam a ditar é exatamente a que já estava lá, e nada salta. Com dois
  /// dedos, a pinça; com um, o arrasto pela pegada atual.
  private func reanchor(from shown: Band, finger point: CGPoint? = nil) {
    guard let host else { return }
    let policy = host.bandPolicy
    if case let (a, b)? = fingers {
      grip = .whole
      anchorFinger = coordinate(of: midpoint(a, b), for: shown.mode)
      anchorSpan = max(hypot(b.x - a.x, b.y - a.y), 1)
      flipHeld = inFlipZone(axisAngle(a, b), of: shown.mode, policy: policy)
    } else if let finger = point ?? tracked.first?.location(in: view) {
      anchorFinger = coordinate(of: finger, for: shown.mode)
    } else {
      return
    }
    let raw = unstretched(shown, policy: policy)
    anchorRaw = raw
    rawBand = raw
    shownBand = shown
  }

  /// Uma mudança de estado no meio do gesto: a faixa vai numa mola, e os dedos
  /// esperam ela chegar para voltar a mandar. Seguir o dedo no meio da mola a
  /// cortaria — um salto, que a FR-017 proíbe.
  private func snap(to band: Band) {
    guard let host else { return }
    rawBand = band
    shownBand = band
    host.springBand(to: band)
    settleUntil = CACurrentMediaTime() + host.bandPolicy.springResponse
  }

  // MARK: - Um dedo

  /// A pegada pelo ponto onde o dedo pousou (FR-008): a até `edgeGrabPoints`
  /// de uma borda, aquela borda; no resto, a faixa inteira. Numa faixa fina as
  /// duas zonas se encontram, e dentro dela o dedo mais perto do meio do que
  /// de uma borda move a faixa inteira.
  private func pickGrip(at point: CGPoint, on band: Band, policy: BandPolicy) -> Grip {
    guard let rect = host?.bandImageRect, rect.width > 0, rect.height > 0 else { return .whole }
    let side = Double(band.mode == .vertical ? rect.width : rect.height)
    let p = coordinate(of: point, for: band.mode)
    let toLower = abs(p - band.lower) * side
    let toUpper = abs(p - band.upper) * side
    let toCenter = abs(p - band.center) * side
    let nearest = min(toLower, toUpper)
    guard nearest <= policy.edgeGrabPoints, nearest <= toCenter else { return .whole }
    return toLower <= toUpper ? .lowerEdge : .upperEdge
  }

  /// No meio, a faixa inteira anda no eixo livre (FR-007); numa borda, só
  /// aquela borda anda, e a oposta fica parada (FR-008).
  private func dragged(_ base: Band, to point: CGPoint) -> Band {
    let delta = coordinate(of: point, for: base.mode) - anchorFinger
    switch grip {
    case .whole:
      return Band(mode: base.mode, center: base.center + delta, thickness: base.thickness)
    case .lowerEdge:
      return Band(mode: base.mode, lower: base.lower + delta, upper: base.upper)
    case .upperEdge:
      return Band(mode: base.mode, lower: base.lower, upper: base.upper + delta)
    }
  }

  // MARK: - Dois dedos

  /// Uma pinça em torno do meio dos dedos (FR-009, R22).
  ///
  /// A faixa escala com a distância entre eles, e cada ponto dela guarda a
  /// posição relativa ao meio: um dedo pousado numa borda continua sobre ela,
  /// e o centro acompanha o meio. No instante em que a referência é tomada a
  /// escala é 1 e o meio não andou — nada salta.
  ///
  /// A distância é a dos dois pontos, não a projetada no eixo: com os dedos
  /// quase lado a lado, a projetada tenderia a zero e a escala explodiria.
  private func pinched(_ base: Band, _ a: CGPoint, _ b: CGPoint) -> Band {
    let scale = Double(hypot(b.x - a.x, b.y - a.y) / anchorSpan)
    let mid = coordinate(of: midpoint(a, b), for: base.mode)
    return Band(mode: base.mode, center: mid + (base.center - anchorFinger) * scale,
                thickness: base.thickness * scale)
  }

  /// A orientação segue o eixo dos dedos (FR-010, R22): um acima do outro,
  /// horizontal; lado a lado, vertical. Troca só depois de passar da diagonal
  /// com `flipHysteresisDegrees` de folga — perto dela, não tremula.
  private func flipIfCrossed(_ a: CGPoint, _ b: CGPoint, policy: BandPolicy) -> Bool {
    guard let current = shownBand?.mode, current != .off else { return false }
    let crossed = inFlipZone(axisAngle(a, b), of: current, policy: policy)
    if flipHeld {
      if !crossed { flipHeld = false }
      return false
    }
    guard crossed else { return false }
    // A faixa se refaz exatamente entre os dedos, no eixo novo, numa mola; a
    // pinça recomeça dali quando ela chegar.
    let next: BandMode = current == .horizontal ? .vertical : .horizontal
    snap(to: between(a, b, mode: next, policy: policy))
    return true
  }

  /// Dois dedos numa faixa desligada a criam entre eles, orientada pelo eixo
  /// (FR-012).
  private func create() {
    guard let host, case let (a, b)? = fingers else { return }
    let mode: BandMode = axisAngle(a, b) >= 45 ? .horizontal : .vertical
    switchedOff = false
    snap(to: between(a, b, mode: mode, policy: host.bandPolicy))
  }

  /// Os dedos voltaram: a faixa renasce onde eles a deixariam.
  private func revive(_ raw: Band, policy: BandPolicy) {
    switchedOff = false
    snap(to: raw.limited(minThickness: policy.minThickness))
  }

  /// Do lado de lá da diagonal para a orientação `mode`, além da folga.
  private func inFlipZone(_ angle: Double, of mode: BandMode, policy: BandPolicy) -> Bool {
    switch mode {
    case .horizontal: return angle < 45 - policy.flipHysteresisDegrees
    case .vertical: return angle > 45 + policy.flipHysteresisDegrees
    case .off: return false
    }
  }

  /// O ângulo do segmento entre os dedos com a horizontal, de 0° a 90°.
  private func axisAngle(_ a: CGPoint, _ b: CGPoint) -> Double {
    Double(atan2(abs(b.y - a.y), abs(b.x - a.x))) * 180 / .pi
  }

  /// A faixa com as bordas nos dois dedos, no eixo de `mode`, dentro dos
  /// limites.
  private func between(_ a: CGPoint, _ b: CGPoint, mode: BandMode, policy: BandPolicy) -> Band {
    let p = coordinate(of: a, for: mode)
    let q = coordinate(of: b, for: mode)
    return Band(mode: mode, lower: min(p, q), upper: max(p, q))
      .limited(minThickness: policy.minThickness)
  }

  // MARK: - Limites

  /// Onde a faixa pode ficar (FR-014): inteira dentro da imagem, e nunca mais
  /// fina que o mínimo. Puxando uma borda, a oposta não se mexe.
  private func limit(_ raw: Band, policy: BandPolicy) -> Band {
    let minimum = policy.minThickness
    switch grip {
    case .whole:
      return raw.limited(minThickness: minimum)
    case .lowerEdge:
      return Band(mode: raw.mode, lower: min(max(raw.lower, 0), raw.upper - minimum),
                  upper: raw.upper)
    case .upperEdge:
      return Band(mode: raw.mode, lower: raw.lower,
                  upper: max(min(raw.upper, 1), raw.lower + minimum))
    }
  }

  /// O elástico (FR-014): além do limite, só `rubberBand` do excesso aparece,
  /// borda a borda. Ao soltar, a mola traz a faixa de volta ao limite.
  private func elastic(_ raw: Band, limit: Band, policy: BandPolicy) -> Band {
    let k = policy.rubberBand
    let lower = limit.lower + (raw.lower - limit.lower) * k
    let upper = limit.upper + (raw.upper - limit.upper) * k
    // Uma borda puxada além da outra encosta nela, sem atravessar.
    guard upper >= lower else {
      let middle = (lower + upper) / 2
      return Band(mode: raw.mode, lower: middle, upper: middle)
    }
    return Band(mode: raw.mode, lower: lower, upper: upper)
  }

  /// O inverso do elástico: o que os dedos precisariam ditar para a tela
  /// mostrar `shown`. Uma referência tomada no meio da mola de volta parte
  /// daí, e a faixa não salta para o limite.
  private func unstretched(_ shown: Band, policy: BandPolicy) -> Band {
    let k = policy.rubberBand
    guard k > 0 else { return shown }
    let bound = limit(shown, policy: policy)
    return Band(mode: shown.mode,
                lower: bound.lower + (shown.lower - bound.lower) / k,
                upper: bound.upper + (shown.upper - bound.upper) / k)
  }

  /// O toque leve na primeira vez que a faixa encosta num limite — a borda da
  /// imagem ou a espessura mínima (FR-016). Uma vez de cada por gesto: um dedo
  /// parado bem no limite não faz o aparelho zumbir.
  private func feel(_ raw: Band, policy: BandPolicy) {
    // Tolerância de arredondamento: a faixa parada exatamente no limite, onde
    // a mola a deixou, não está encostando.
    let tolerance = 1e-9
    let atEdge = raw.lower < -tolerance || raw.upper > 1 + tolerance
    let atMinimum = raw.thickness < policy.minThickness - tolerance
    if atEdge, !feltEdge {
      feltEdge = true
      host?.bandTouchedLimit()
    }
    if atMinimum, !feltMinimum {
      feltMinimum = true
      host?.bandTouchedLimit()
    }
  }

  // MARK: - Fim

  private func lift(_ lifted: Set<UITouch>, cancelled: Bool) {
    tracked.removeAll { lifted.contains($0) }
    let active = state == .began || state == .changed
    if tracked.isEmpty {
      if active { complete(cancelled: cancelled) } else { state = .failed }
    } else if active, !switchedOff, settleUntil == nil, let shown = shownBand {
      // De dois dedos para um: o que ficou arrasta a faixa inteira, e nada
      // salta.
      grip = .whole
      reanchor(from: shown)
    }
  }

  /// A faixa vai para dentro dos limites, e quem espelha fica sabendo — uma
  /// vez, no fim.
  private func complete(cancelled: Bool) {
    if let host, !switchedOff, let raw = rawBand {
      host.endBandGesture(settleTo: limit(raw, policy: host.bandPolicy))
    } else {
      host?.endBandGesture(settleTo: nil)
    }
    state = cancelled ? .cancelled : .ended
  }

  // MARK: - Geometria

  private var fingers: (CGPoint, CGPoint)? {
    guard tracked.count == 2 else { return nil }
    return (tracked[0].location(in: view), tracked[1].location(in: view))
  }

  private func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint {
    CGPoint(x: (a.x + b.x) / 2, y: (a.y + b.y) / 2)
  }

  /// O ponto, normalizado no eixo em que a faixa anda.
  private func coordinate(of point: CGPoint, for mode: BandMode) -> Double {
    guard let rect = host?.bandImageRect, rect.width > 0, rect.height > 0 else { return 0 }
    return mode == .vertical
      ? Double((point.x - rect.minX) / rect.width)
      : Double((point.y - rect.minY) / rect.height)
  }
}
