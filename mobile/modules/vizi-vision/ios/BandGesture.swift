import UIKit
import UIKit.UIGestureRecognizerSubclass

/// Quem hospeda a faixa — a `PreviewView`. O reconhecedor só acompanha os
/// dedos; ler e escrever a faixa, desenhar e vibrar são do hospedeiro.
protocol BandGestureHost: AnyObject {
  /// O quadrado da imagem canônica na view: é nele que a faixa vive.
  var bandImageRect: CGRect { get }
  var bandPolicy: BandPolicy { get }
  /// Começo do gesto: prepara o retorno tátil e devolve a faixa que está na
  /// tela, parando qualquer mola no meio. `nil` quando não há faixa a mexer.
  func beginBandGesture() -> Band?
  /// Durante o gesto: escreve sem avisar o JavaScript e desenha sem animar.
  func moveBand(to band: Band)
  /// Fim do gesto: avisa quem espelha — uma vez, não a cada quadro.
  func endBandGesture()
}

/// Um reconhecedor para um e dois dedos (spec 005, R18).
///
/// Reconhecedores separados de arrasto e pinça trocariam de dono no instante
/// em que o segundo dedo pousa, e esse é o gesto principal da spec. Com um dono
/// só, a passagem é contínua.
///
/// Só começa depois que o dedo anda `startSlopPoints`: um toque simples não é
/// engolido, e os dois toques de voltar ao centro chegam a quem os reconhece.
final class BandGestureRecognizer: UIGestureRecognizer {
  weak var host: BandGestureHost?

  /// Os toques acompanhados, na ordem em que pousaram. No máximo dois.
  private var tracked: [UITouch] = []
  /// Onde o primeiro dedo pousou. É dali que a faixa passa a acompanhá-lo.
  private var touchDown = CGPoint.zero
  /// A referência do arrasto: a faixa e o dedo no instante em que ele começou
  /// a valer.
  private var anchorBand: Band?
  private var anchorFinger = 0.0
  /// A última faixa desenhada pelo gesto — de onde se recomeça quando um dedo
  /// sai e o outro fica.
  private var lastBand: Band?

  override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
    super.touchesBegan(touches, with: event)
    for touch in touches where tracked.count < 2 {
      tracked.append(touch)
    }
    if state == .possible, let first = tracked.first {
      touchDown = first.location(in: view)
    }
  }

  override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
    super.touchesMoved(touches, with: event)
    guard let host, let finger = tracked.first else { return }
    let point = finger.location(in: view)

    switch state {
    case .possible:
      let slop = CGFloat(host.bandPolicy.startSlopPoints)
      guard hypot(point.x - touchDown.x, point.y - touchDown.y) >= slop else { return }
      guard let band = host.beginBandGesture() else {
        state = .failed
        return
      }
      // A referência é o ponto do toque, não o de agora: a faixa fica colada
      // no dedo, e a folga não vira distância perdida.
      anchor(band, at: touchDown)
      state = .began
    case .began, .changed:
      state = .changed
    default:
      return
    }
    follow(point)
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
    anchorBand = nil
    lastBand = nil
  }

  // MARK: - Um dedo

  private func anchor(_ band: Band, at point: CGPoint) {
    anchorBand = band
    lastBand = band
    anchorFinger = coordinate(of: point, for: band.mode)
  }

  /// A faixa anda no eixo livre, junto com o dedo, sem sair da imagem (FR-007).
  private func follow(_ point: CGPoint) {
    guard let host, let base = anchorBand else { return }
    let delta = coordinate(of: point, for: base.mode) - anchorFinger
    let half = base.thickness / 2
    let center = min(max(base.center + delta, half), 1 - half)
    let next = Band(mode: base.mode, center: center, thickness: base.thickness)
    lastBand = next
    host.moveBand(to: next)
  }

  private func lift(_ lifted: Set<UITouch>, cancelled: Bool) {
    tracked.removeAll { lifted.contains($0) }
    let active = state == .began || state == .changed
    if tracked.isEmpty {
      if active {
        host?.endBandGesture()
        state = cancelled ? .cancelled : .ended
      } else {
        state = .failed
      }
    } else if active, let finger = tracked.first, let band = lastBand {
      // O dedo que ficou vira a referência: nada salta.
      anchor(band, at: finger.location(in: view))
    }
  }

  /// O ponto, normalizado no eixo em que a faixa anda.
  private func coordinate(of point: CGPoint, for mode: BandMode) -> Double {
    guard let rect = host?.bandImageRect, rect.width > 0, rect.height > 0 else { return 0 }
    return mode == .vertical
      ? Double((point.x - rect.minX) / rect.width)
      : Double((point.y - rect.minY) / rect.height)
  }
}
