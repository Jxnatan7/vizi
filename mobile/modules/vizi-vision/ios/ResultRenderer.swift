import AVFoundation
import QuartzCore
import UIKit

/// Estado de resultado da `PreviewView`, e a transição até ele (US3).
///
/// A animação tem duas metades porque o destino só existe depois da foto.
///
/// **No toque** (FR-009), o frame congelado se aproxima da região dos objetos
/// vistos ao vivo — o que já se sabe sem esperar nada.
///
/// **Quando o resultado chega**, a imagem endireitada nasce exatamente sobre o
/// recorte, deformada de volta ao quadrilátero que ele ocupa no frame, e se
/// desfaz até o retângulo final. O contexto em volta some. É o "recorta,
/// aproxima e endireita" da spec, nessa ordem.
///
/// Tudo roda no servidor de renderização, não na thread principal: o React
/// troca de estado no meio do caminho, e isso não pode engasgar a transição
/// (princípio III, SC-002).
final class ResultRenderer {

  /// Onde a segunda metade termina.
  enum Destination {
    /// O resultado tem recorte próprio. `quad` é onde ele estava no frame,
    /// normalizado de 0 a 1, na ordem dos cantos da imagem: topo-esquerdo,
    /// topo-direito, base-direita, base-esquerda. `size` é o do buffer exibido,
    /// de onde sai o retângulo final.
    case cutout(CGImage, quad: [CGPoint], size: CGSize)
    /// A imagem exibida é o frame inteiro (canônica, diagnóstico): o frame
    /// congelado só se acomoda no retângulo dela.
    case whole(size: CGSize)
  }

  private weak var host: PreviewView?

  private var stage: CALayer?
  /// O frame congelado. É ele que se aproxima, e o overlay vai junto.
  private var card: CALayer?
  /// O resultado, deformado de volta ao recorte e depois endireitado.
  private var cutout: CALayer?
  /// Onde o cartão fica sem aproximação. É o ponto de chegada da volta.
  private var cardOrigin = CGPoint.zero
  /// O recorte em coordenadas do cartão, guardado para a volta.
  private var quadInCard: [CGPoint] = []

  /// Invalida as conclusões pendentes. `setCompletionBlock` dispara também
  /// quando a animação é substituída — sem isto, a ida interrompida pela volta
  /// esconderia a transição no meio dela.
  private var epoch = 0

  init(host: PreviewView) {
    self.host = host
  }

  // MARK: - Ida

  /// Primeira metade, no toque: o frame congelado se aproxima de `focus`.
  ///
  /// - Parameters:
  ///   - frame: o frame que estava na tela
  ///   - focus: região dos objetos vistos ao vivo, normalizada de 0 a 1;
  ///     `nil` quando não havia nenhum, e então nada se aproxima
  func begin(frame: CGImage, focus: CGRect?, durationMs: Int) {
    guard let host else { return }
    teardown()

    let bounds = host.bounds
    let rect = AVMakeRect(
      aspectRatio: CGSize(width: frame.width, height: frame.height), insideRect: bounds)
    cardOrigin = rect.origin

    CATransaction.begin()
    CATransaction.setDisableActions(true)

    let stage = CALayer()
    stage.frame = bounds
    stage.masksToBounds = true

    // Por baixo do cartão. Ao aproximar, a borda dele pode entrar na tela, e o
    // que aparece ali tem de ser fundo — não o frame congelado sem zoom, que
    // continua na camada de vídeo.
    let backdrop = CALayer()
    backdrop.frame = stage.bounds
    backdrop.backgroundColor = UIColor.black.cgColor
    stage.addSublayer(backdrop)

    let card = CALayer()
    card.contents = frame
    card.contentsGravity = .resize
    Self.place(card, size: rect.size)
    card.transform = CATransform3DMakeTranslation(rect.origin.x, rect.origin.y, 0)
    stage.addSublayer(card)

    host.layer.addSublayer(stage)
    // As caixas se aproximam com a imagem. Deixadas na view, ficariam paradas
    // sobre um frame que se move.
    host.lendOverlay(to: card, origin: rect.origin)

    if let focus, let target = Self.zoom(onto: focus, card: rect.size, stage: bounds) {
      let duration = Self.seconds(durationMs)
      // Duração zero, para o Core Animation, quer dizer "a padrão" — 0,25 s.
      if duration > 0 {
        let animation = CABasicAnimation(keyPath: "transform")
        animation.fromValue = NSValue(caTransform3D: card.transform)
        animation.toValue = NSValue(caTransform3D: target)
        animation.duration = duration
        animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
        card.add(animation, forKey: "transform")
      }
      card.transform = target
    }

    CATransaction.commit()
    self.stage = stage
    self.card = card
  }

  /// Segunda metade, quando o resultado existe.
  ///
  /// A imagem nítida já está na camada de vídeo, por baixo. A transição só
  /// precisa terminar exatamente em cima dela para que a troca não se veja
  /// (FR-010).
  func settle(_ destination: Destination, durationMs: Int) {
    guard let host, let stage, let card else { return }
    epoch &+= 1
    let token = epoch
    let duration = Self.seconds(durationMs)
    let fps = host.window?.screen.maximumFramesPerSecond ?? 60

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    CATransaction.setCompletionBlock { [weak self] in
      guard let self, self.epoch == token else { return }
      self.rest()
    }

    // O cartão para onde estiver: a aproximação pode não ter terminado.
    let cardNow = Self.freeze(card)

    switch destination {
    case let .cutout(image, quad, size):
      let final = AVMakeRect(aspectRatio: size, insideRect: stage.bounds)
      quadInCard = quad.map {
        CGPoint(x: $0.x * card.bounds.width, y: $0.y * card.bounds.height)
      }

      let layer = CALayer()
      layer.contents = image
      layer.contentsGravity = .resize
      Self.place(layer, size: final.size)
      stage.addSublayer(layer)
      cutout = layer

      // Nasce sobre o recorte, onde o cartão o mostra agora.
      let from = quadInCard.compactMap { PlaneRectifier.apply(cardNow, $0) }
      Self.morph(layer, from: from, to: Self.corners(of: final), duration: duration, fps: fps)
      Self.fade(card, to: 0, duration: duration)

    case let .whole(size):
      let final = AVMakeRect(aspectRatio: size, insideRect: stage.bounds)
      let from = Self.corners(of: card.bounds).compactMap { PlaneRectifier.apply(cardNow, $0) }
      Self.morph(card, from: from, to: Self.corners(of: final), duration: duration, fps: fps)
    }

    CATransaction.commit()
  }

  /// Fim da ida. A transição se esconde, mas fica: é dela que a volta parte.
  private func rest() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    stage?.isHidden = true
    host?.reclaimOverlay()
    CATransaction.commit()
  }

  // MARK: - Volta

  /// A volta (T029): o caminho da ida ao contrário, até o frame congelado.
  ///
  /// Parte de onde a transição estiver — inclusive do meio da ida, se a
  /// pessoa voltar antes de ela terminar.
  func dismiss(durationMs: Int) {
    guard let host, let stage, let card else { return }
    epoch &+= 1
    let token = epoch
    let duration = Self.seconds(durationMs)
    let fps = host.window?.screen.maximumFramesPerSecond ?? 60

    CATransaction.begin()
    CATransaction.setDisableActions(true)
    CATransaction.setCompletionBlock { [weak self] in
      guard let self, self.epoch == token else { return }
      self.teardown()
    }

    stage.isHidden = false
    let home = CGRect(origin: cardOrigin, size: card.bounds.size)

    if let cutout {
      let cutoutNow = Self.freeze(cutout)
      let from = Self.corners(of: cutout.bounds).compactMap { PlaneRectifier.apply(cutoutNow, $0) }
      let to = quadInCard.map { CGPoint(x: $0.x + cardOrigin.x, y: $0.y + cardOrigin.y) }
      Self.morph(cutout, from: from, to: to, duration: duration, fps: fps)
      Self.fade(card, to: 1, duration: duration)
    }

    let cardNow = Self.freeze(card)
    let from = Self.corners(of: card.bounds).compactMap { PlaneRectifier.apply(cardNow, $0) }
    Self.morph(card, from: from, to: Self.corners(of: home), duration: duration, fps: fps)

    CATransaction.commit()
  }

  /// Desfaz tudo, sem animar. Também é o caminho do erro de captura.
  func teardown() {
    epoch &+= 1
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    host?.reclaimOverlay()
    stage?.removeFromSuperlayer()
    CATransaction.commit()
    stage = nil
    card = nil
    cutout = nil
    quadInCard = []
  }

  // MARK: - Geometria

  /// Leva os cantos de `layer` de `from` a `to`, cada um em linha reta.
  ///
  /// É a resposta à armadilha do R16. Interpolar os elementos de uma matriz
  /// projetiva não produz movimento linear, e a decomposição que o Core
  /// Animation faz não foi pensada para perspectiva. Os cantos, sim, se movem
  /// como o olho espera — e a homografia de cada instante sai deles.
  ///
  /// Um quadro-chave por quadro de tela. Entre dois vizinhos a diferença é
  /// pequena demais para a interpolação do Core Animation importar.
  ///
  /// Sem caminho válido, a camada vai direto ao fim: recusar a animação é
  /// melhor que desenhar uma deformação errada.
  private static func morph(
    _ layer: CALayer, from: [CGPoint], to: [CGPoint],
    duration: CFTimeInterval, fps: Int
  ) {
    let local = corners(of: layer.bounds)
    guard to.count == 4, let last = transform(mapping: local, to: to) else { return }
    layer.removeAnimation(forKey: "transform")
    layer.transform = last
    guard duration > 0, from.count == 4 else { return }

    let steps = max(1, Int((duration * Double(fps)).rounded(.up)))
    var values: [NSValue] = []
    values.reserveCapacity(steps + 1)
    for k in 0...steps {
      let s = CGFloat(k) / CGFloat(steps)
      let quad = zip(from, to).map { a, b in
        CGPoint(x: a.x + (b.x - a.x) * s, y: a.y + (b.y - a.y) * s)
      }
      guard let t = transform(mapping: local, to: quad) else { return }
      values.append(NSValue(caTransform3D: t))
    }

    let animation = CAKeyframeAnimation(keyPath: "transform")
    animation.values = values
    animation.duration = duration
    animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    layer.add(animation, forKey: "transform")
  }

  /// A homografia que leva os cantos de uma camada a um quadrilátero, como
  /// `CATransform3D`.
  ///
  /// Não há decomposição: a 3×3 cabe inteira na 4×4. A terceira linha da
  /// homografia vira a perspectiva (`m14`, `m24`, `m44`), e o eixo z fica
  /// intocado. O Core Animation faz a divisão, e a GPU, o mapeamento.
  static func transform(mapping src: [CGPoint], to dst: [CGPoint]) -> CATransform3D? {
    guard let h = Rectify.homography(from: src, to: dst) else { return nil }
    // `w` precisa ser positivo em toda a camada. Se não for, o quadrilátero
    // de destino dobrou sobre si, e a camada passaria por trás do olho.
    for p in src where h[6] * Double(p.x) + h[7] * Double(p.y) + h[8] <= 1e-9 {
      return nil
    }
    var t = CATransform3DIdentity
    t.m11 = CGFloat(h[0]); t.m21 = CGFloat(h[1]); t.m41 = CGFloat(h[2])
    t.m12 = CGFloat(h[3]); t.m22 = CGFloat(h[4]); t.m42 = CGFloat(h[5])
    t.m14 = CGFloat(h[6]); t.m24 = CGFloat(h[7]); t.m44 = CGFloat(h[8])
    return t
  }

  /// O inverso de `transform(mapping:to:)`: a 3×3 dentro de uma `CATransform3D`.
  static func homography(_ t: CATransform3D) -> [Double] {
    [t.m11, t.m21, t.m41, t.m12, t.m22, t.m42, t.m14, t.m24, t.m44].map { Double($0) }
  }

  /// Para a camada onde ela está agora e devolve essa posição.
  private static func freeze(_ layer: CALayer) -> [Double] {
    let current = layer.presentation()?.transform ?? layer.transform
    layer.removeAnimation(forKey: "transform")
    layer.transform = current
    return homography(current)
  }

  private static func fade(_ layer: CALayer, to value: Float, duration: CFTimeInterval) {
    let current = layer.presentation()?.opacity ?? layer.opacity
    layer.removeAnimation(forKey: "opacity")
    layer.opacity = value
    guard duration > 0 else { return }
    let animation = CABasicAnimation(keyPath: "opacity")
    animation.fromValue = current
    animation.toValue = value
    animation.duration = duration
    animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    layer.add(animation, forKey: "opacity")
  }

  /// Âncora e posição na origem: a `transform` passa a ser, sozinha, o mapa
  /// das coordenadas da camada para as do palco. É o que deixa uma homografia
  /// entrar nela sem compensação.
  private static func place(_ layer: CALayer, size: CGSize) {
    layer.anchorPoint = .zero
    layer.position = .zero
    layer.bounds = CGRect(origin: .zero, size: size)
  }

  /// Aproximação que enquadra `focus` no palco, sem distorcer.
  private static func zoom(onto focus: CGRect, card: CGSize, stage: CGRect) -> CATransform3D? {
    let region = CGRect(
      x: focus.minX * card.width, y: focus.minY * card.height,
      width: focus.width * card.width, height: focus.height * card.height)
    guard region.width > 0, region.height > 0 else { return nil }
    let scale = max(1, min(stage.width / region.width, stage.height / region.height))
    guard scale.isFinite else { return nil }
    let tx = stage.midX - scale * region.midX
    let ty = stage.midY - scale * region.midY
    return CATransform3DConcat(
      CATransform3DMakeScale(scale, scale, 1), CATransform3DMakeTranslation(tx, ty, 0))
  }

  /// Topo-esquerdo, topo-direito, base-direita, base-esquerda — a ordem dos
  /// quadriláteros de recorte.
  private static func corners(of r: CGRect) -> [CGPoint] {
    [CGPoint(x: r.minX, y: r.minY), CGPoint(x: r.maxX, y: r.minY),
     CGPoint(x: r.maxX, y: r.maxY), CGPoint(x: r.minX, y: r.maxY)]
  }

  private static func seconds(_ ms: Int) -> CFTimeInterval {
    Double(max(0, ms)) / 1000
  }
}
