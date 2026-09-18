import CoreMotion
import Foundation

/// Gravidade e horizonte, para retificar sem depender do conteúdo da cena.
///
/// O horizonte é a projeção da linha no infinito de qualquer plano ortogonal à
/// gravidade, e **depende só da rotação câmera-plano, não da altura da câmera**.
/// O ponto de fuga horizontal de uma estante tem obrigatoriamente que estar
/// sobre ele — o que tira um grau de liberdade da estimativa pelas bases.
final class DeviceAttitude {

  /// Gravidade no referencial da **imagem canônica**, que é sempre retrato.
  ///
  /// `x` para a direita, `y` para baixo, `z` para dentro da cena. Com o
  /// aparelho em pé, a gravidade é ~(0, 1, 0) e as verticais ficam paralelas.
  struct Gravity {
    var x: Double
    var y: Double
    var z: Double

    /// Direção da vertical na imagem, apontando para CIMA.
    var upInImage: (dx: Double, dy: Double) {
      let n = hypot(x, y)
      guard n > 1e-6 else { return (0, -1) }
      return (-x / n, -y / n)
    }
  }

  private let motion = CMMotionManager()
  private(set) var isAvailable = false

  func start() {
    guard motion.isDeviceMotionAvailable else { return }
    motion.deviceMotionUpdateInterval = 1.0 / 30.0
    motion.startDeviceMotionUpdates()
    isAvailable = true
  }

  func stop() {
    motion.stopDeviceMotionUpdates()
    isAvailable = false
  }

  /// A leitura do instante. Amostrada no disparo, não depois — senão mede a
  /// inclinação de outro momento.
  func snapshot() -> Gravity? {
    guard let g = motion.deviceMotion?.gravity else { return nil }
    // Referencial do aparelho: x direita, y para cima na tela, z saindo da
    // tela. A câmera traseira olha para -z, e a imagem tem y para baixo.
    return Gravity(x: g.x, y: -g.y, z: -g.z)
  }
}

/// Geometria projetiva mínima, em coordenadas homogêneas.
///
/// Uma reta por dois pontos e a interseção de duas retas são o mesmo produto
/// vetorial — é o que torna o código curto o bastante para conferir de olho.
enum Projective {
  typealias H = (x: Double, y: Double, w: Double)

  static func cross(_ a: H, _ b: H) -> H {
    (a.y * b.w - a.w * b.y, a.w * b.x - a.x * b.w, a.x * b.y - a.y * b.x)
  }

  static func point(_ p: CGPoint) -> H { (Double(p.x), Double(p.y), 1) }

  static func toPoint(_ h: H) -> CGPoint? {
    guard abs(h.w) > 1e-9 else { return nil }
    return CGPoint(x: h.x / h.w, y: h.y / h.w)
  }

  static func line(through a: CGPoint, and b: CGPoint) -> H {
    cross(point(a), point(b))
  }

  /// Distâncias focais em pixels, **separadas por eixo**.
  ///
  /// A imagem canônica é um esticamento NÃO uniforme do frame — 4:3 virando
  /// quadrado. Uma focal única só valeria se o esticamento fosse isotrópico.
  struct Focal {
    var x: Double
    var y: Double

    /// Da abertura do sensor e das dimensões da imagem normalizada.
    ///
    /// `fieldOfView` é a abertura horizontal do sensor, que depois da rotação
    /// para retrato vira a vertical — mas a focal em pixels é a mesma nos dois
    /// eixos antes do esticamento.
    static func from(fieldOfViewDegrees fov: Double, sensorLongSide: Double,
                     portraitWidth: Double, portraitHeight: Double,
                     canonicalSide: Double) -> Focal {
      let half = fov * .pi / 360
      guard half > 1e-6, portraitWidth > 0, portraitHeight > 0 else {
        return Focal(x: canonicalSide, y: canonicalSide)
      }
      let f = (sensorLongSide / 2) / tan(half)
      return Focal(x: f * canonicalSide / portraitWidth,
                   y: f * canonicalSide / portraitHeight)
    }
  }

  /// Horizonte em coordenadas da imagem.
  static func horizon(gravity g: DeviceAttitude.Gravity, focal f: Focal,
                      center c: CGPoint) -> H {
    let lx = g.x / f.x
    let ly = g.y / f.y
    return (lx, ly, g.z - lx * Double(c.x) - ly * Double(c.y))
  }

  /// Ponto de fuga vertical: para onde as verticais do mundo convergem.
  /// `nil` quando a gravidade é paralela ao plano da imagem — verticais
  /// paralelas, sem convergência.
  static func verticalVanishingPoint(gravity g: DeviceAttitude.Gravity,
                                     focal f: Focal, center c: CGPoint) -> CGPoint? {
    guard abs(g.z) > 1e-4 else { return nil }
    return CGPoint(x: Double(c.x) + f.x * g.x / g.z, y: Double(c.y) + f.y * g.y / g.z)
  }
}
