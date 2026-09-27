import CoreGraphics
import CoreML
import Foundation

/// A releitura do recorte (spec 006): as contas entre o quadrado que o modelo
/// leu e o recorte que está na tela.
///
/// O quadrado é o recorte encaixado, centrado, com preto no resto — o mesmo
/// enquadramento da tela. As detecções saem no espaço do quadrado, que é o
/// espaço em que o overlay já desenha. As divisões, não: a `PreviewView` as
/// desenha normalizadas no recorte.
enum Reread {

  /// O que a releitura encontrou. É o resultado (FR-002).
  struct Outcome {
    /// Só as que passaram pela regra das bordas: as que contam e as que
    /// aparecem, que são as mesmas (FR-005).
    var instances: [Instance]
    /// As máscaras dessas instâncias. **Nunca atravessa a fronteira.**
    var protos: MLMultiArray?
    var shelves: [Rectify.Shelf]
    var rowCount: Int
    var lyingCount: Int
  }

  /// O recorte sem a margem, no espaço do quadrado: a extensão dos livros que
  /// o `PlaneRectifier` mediu no resultado, levada ao retângulo que o recorte
  /// ocupa no quadrado (R32).
  ///
  /// Medida, e não deduzida da margem: no recuo de só rotação a borda da foto
  /// pode cortar o recorte, e aquele lado fica com menos margem que os outros.
  static func core(of content: CGRect, books: CGRect) -> CGRect {
    CGRect(x: content.minX + books.minX * content.width,
           y: content.minY + books.minY * content.height,
           width: books.width * content.width,
           height: books.height * content.height)
  }

  /// A regra das bordas (FR-004): conta quem tem `membership` da área da
  /// caixa dentro do recorte sem a margem.
  ///
  /// Área, e não um eixo como na faixa: o recorte é limitado nos dois. Uma
  /// fatia de vizinho sai pelo lado tanto quanto um pedaço da prateleira de
  /// cima sai pelo alto.
  static func inside(_ instances: [Instance], core: CGRect, membership: Double) -> [Instance] {
    instances.filter { inst in
      let box = CGRect(x: CGFloat(inst.x), y: CGFloat(inst.y),
                       width: CGFloat(inst.width), height: CGFloat(inst.height))
      let area = Double(box.width * box.height)
      guard area > 0 else { return false }
      let overlap = box.intersection(core)
      guard !overlap.isNull else { return false }
      return Double(overlap.width * overlap.height) >= membership * area
    }
  }

  /// As fileiras da `ShelfGeometry`, com as divisões no espaço do recorte.
  static func shelves(
    _ rows: [ShelfGeometry.Row], of instances: [Instance], content: CGRect, edge: Double
  ) -> [Rectify.Shelf] {
    rows.compactMap { row in
      shelf(row.indices.compactMap { instances.indices.contains($0) ? instances[$0] : nil },
            content: content, edge: edge)
    }
  }

  /// Uma fileira, normalizada no recorte — o espaço em que a `PreviewView`
  /// desenha as divisões.
  ///
  /// A conta é a da 004: o meio entre a borda direita de um livro e a esquerda
  /// do vizinho. Só o espaço muda, e por isso ela não depende mais da
  /// homografia (R33).
  private static func shelf(_ members: [Instance], content: CGRect, edge: Double) -> Rectify.Shelf? {
    guard !members.isEmpty, content.width > 0, content.height > 0 else { return nil }
    let nx = { (x: Float) in (Double(x) - Double(content.minX)) / Double(content.width) }
    let ny = { (y: Float) in (Double(y) - Double(content.minY)) / Double(content.height) }

    let ordered = members.sorted { $0.x < $1.x }
    var cuts: [Double] = []
    for i in 0..<max(0, ordered.count - 1) {
      let a = ordered[i], b = ordered[i + 1]
      // Divisões coladas na borda do recorte são a borda, não uma divisão.
      let n = nx((a.x + a.width + b.x) / 2)
      if n > edge, n < 1 - edge { cuts.append(n) }
    }

    let top = members.map(\.y).min() ?? 0
    let bottom = members.map { $0.y + $0.height }.max() ?? 0
    return Rectify.Shelf(count: members.count, dividers: cuts, top: ny(top), bottom: ny(bottom))
  }
}
