#!/usr/bin/env python3
"""Confere um zip do modo coleta contra o portão da spec 007.

    python3 check-zip.py vizi-coleta-2026-10-19T14-03-22.zip [--out pasta]

Lê o formato descrito em contracts/zip-format.md (o FORMAT.md de dentro do
zip) e, item por item, refaz cada contagem a partir das caixas, da faixa e do
recorte sem a margem — sem confiar nas marcas que o app gravou.

    SC-001  60 fps fora das capturas, e de volta a 60 depois de cada item
    SC-002  a contagem refeita é a que a tela mostrou; cada resposta no seu item
    SC-003  as quatro imagens em toda captura com recorte
    SC-005  as caixas das marcas desenhadas sobre square.jpg (para olhar)
    SC-006  nenhuma .tmp-*, e todo item com o que o item.json lista

Só a biblioteca padrão. O Pillow, se houver, desenha as caixas do SC-005.
Sai com 1 se algum critério falhar.
"""

import argparse
import io
import json
import struct
import sys
import zipfile
from pathlib import Path, PurePosixPath

FPS_OK = 58.0          # 60 com folga de arredondamento da janela
CAPTURE_WINDOW_MS = 2000


def f32(x):
    """O mesmo arredondamento do `Float` do Swift."""
    return struct.unpack("f", struct.pack("f", x))[0]


def in_band(box, band, side):
    """Band.contains, em Swift, refeito com a mesma aritmética."""
    mode = band["mode"]
    if mode == "off":
        return True
    x, y, w, h = box
    start, extent = (y, h) if mode == "horizontal" else (x, w)
    if extent <= 0:
        return False
    a = f32(f32(start) / f32(side))
    b = f32(f32(f32(start) + f32(extent)) / f32(side))
    lower = band["center"] - band["thickness"] / 2
    upper = band["center"] + band["thickness"] / 2
    overlap = max(0.0, min(b, upper) - max(a, lower))
    return overlap >= band["membership"] * (b - a)


def in_core(box, core, membership):
    """Reread.inside, em Swift: a fração da área da caixa dentro do núcleo."""
    x, y, w, h = box
    area = w * h
    if area <= 0:
        return False
    cx, cy, cw, ch = core
    ix = max(0.0, min(x + w, cx + cw) - max(x, cx))
    iy = max(0.0, min(y + h, cy + ch) - max(y, cy))
    return ix * iy >= membership * area


class Report:
    def __init__(self):
        self.failures = []

    def check(self, ok, criterion, detail):
        mark = "✓" if ok else "✗"
        print(f"  {mark} {criterion}: {detail}")
        if not ok:
            self.failures.append(f"{criterion}: {detail}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("zip")
    parser.add_argument("--out", help="onde gravar as marcas desenhadas (padrão: <zip>-check/)")
    args = parser.parse_args()

    archive = zipfile.ZipFile(args.zip)
    names = archive.namelist()
    root = PurePosixPath(names[0]).parts[0]
    read = lambda rel: archive.read(f"{root}/{rel}")
    exists = lambda rel: f"{root}/{rel}" in names
    report = Report()

    print(f"sessão {root}")
    if not exists("FORMAT.md") or "versão 1" not in read("FORMAT.md").decode().lower():
        print("  ! o FORMAT.md não diz versão 1 — os campos podem ter mudado")
    session = json.loads(read("session.json"))
    report.check(session.get("format") == 1, "formato", f"session.json format={session.get('format')}")
    side = session.get("model", {}).get("inputWidth", 640)
    print(f"  modelo: {session.get('model', {}).get('weightsSha256', '?')[:12]}… · "
          f"fim: {session.get('endReason')} · {session.get('counts')}")

    # ── SC-006: nenhuma .tmp-*, e todo item completo ────────────────────────
    item_ids = sorted({PurePosixPath(n).parts[2] for n in names
                       if len(PurePosixPath(n).parts) > 3 and PurePosixPath(n).parts[1] == "items"})
    leftovers = [i for i in item_ids if i.startswith(".tmp-")]
    report.check(not leftovers, "SC-006", f"{len(leftovers)} pastas .tmp-*" if leftovers else "nenhuma .tmp-*")
    # Na ordem da sessão: o número é comum a marcas e capturas.
    item_ids = sorted((i for i in item_ids if not i.startswith(".")), key=lambda i: i[1:])

    out_dir = Path(args.out) if args.out else Path(str(args.zip).removesuffix(".zip") + "-check")
    try:
        from PIL import Image, ImageDraw
    except ImportError:
        Image = None

    rows = []
    items_at = []
    sc002 = sc003 = sc006 = True
    for item_id in item_ids:
        item = json.loads(read(f"items/{item_id}/item.json"))
        kind, band, th = item["kind"], item["band"], item["thresholds"]
        items_at.append((item["at"], kind))

        missing = [img["file"] for img in item.get("images", {}).values()
                   if not exists(f"items/{item_id}/{img['file']}")]
        protos = [item.get("protos"), (item.get("photoRead") or {}).get("protos"),
                  (item.get("reread") or {}).get("protos")]
        missing += [p for p in protos if isinstance(p, str) and not exists(f"items/{item_id}/{p}")]
        if missing:
            sc006 = False
            print(f"  ✗ SC-006 {item_id}: faltam {missing}")

        truth = json.loads(read(f"items/{item_id}/truth.json")) if exists(f"items/{item_id}/truth.json") else None
        truth_text = "—" if truth is None else ("pulou" if truth.get("skipped") else str(truth.get("count")))

        if kind == "mark":
            dets = item["detections"]
            counted = [d for d in dets if d["score"] >= th["confidence"] and in_band(d["box"], band, side)]
            shown_app = item["frameCount"]
            if len(counted) != shown_app:
                sc002 = False
                print(f"  ✗ SC-002 {item_id}: refeita {len(counted)} ≠ frameCount {shown_app}")
            near = [d for d in dets if d["score"] < th["confidence"] and in_band(d["box"], band, side)]
            rows.append((item_id, "marca", shown_app, item.get("displayedCount"), truth_text, len(near)))
            if Image and exists(f"items/{item_id}/square.jpg"):
                draw_mark(Image, ImageDraw, read(f"items/{item_id}/square.jpg"), dets, th, band, side,
                          out_dir / f"{item_id}.jpg")
        else:
            result = item["result"]
            photo = item["photoRead"]["detections"]
            photo_count = sum(1 for d in photo if d["score"] >= th["confidence"] and in_band(d["box"], band, side))
            reread = item.get("reread")
            if result["countSource"] == "photo":
                refeita, near = photo_count, sum(
                    1 for d in photo if d["score"] < th["confidence"] and in_band(d["box"], band, side))
            else:
                dets = reread["detections"]
                refeita = sum(1 for d in dets
                              if d["score"] >= th["confidence"] and in_core(d["box"], reread["core"], reread["membership"]))
                near = sum(1 for d in dets
                           if d["score"] < th["confidence"] and in_core(d["box"], reread["core"], reread["membership"]))
            if refeita != result["count"]:
                sc002 = False
                print(f"  ✗ SC-002 {item_id}: refeita {refeita} ≠ count {result['count']} ({result['countSource']})")

            images = item.get("images", {})
            if "crop" in images:
                expected = {"photo", "photoSquare", "crop"}
                if item.get("options", {}).get("reread", True):
                    expected.add("rereadSquare")
                if not expected <= set(images):
                    sc003 = False
                    print(f"  ✗ SC-003 {item_id}: faltam {sorted(expected - set(images))}")
            elif not result.get("declineReason") and result["count"] > 0:
                # Sem recorte, o motivo tem de estar nos dados: a recusa, ou
                # nenhum livro na faixa.
                sc003 = False
                print(f"  ✗ SC-003 {item_id}: sem recorte e sem motivo nos dados")
            rows.append((item_id, "captura", result["count"], None, truth_text, near))

    report.check(sc002, "SC-002", f"contagem refeita em {len(item_ids)} itens")
    report.check(sc003, "SC-003", "imagens das capturas com recorte")
    report.check(sc006, "SC-006", "todo item com o que o item.json lista")
    if Image:
        print(f"  · SC-005: marcas desenhadas em {out_dir}/ — conferir que as caixas caem sobre os livros")
    else:
        print("  · SC-005: instale o Pillow para desenhar as marcas")

    # ── SC-001: a telemetria ────────────────────────────────────────────────
    samples = []
    for line in read("telemetry.jsonl").decode().splitlines() if exists("telemetry.jsonl") else []:
        try:
            entry = json.loads(line)
        except json.JSONDecodeError:
            continue  # a última linha pode estar cortada (FORMAT.md)
        if entry.get("type") == "sample":
            samples.append(entry)
    captures = [at for at, kind in items_at if kind == "capture"]
    outside = [s["fpsCaptured"] for s in samples
               if all(abs(s["at"] - at) > CAPTURE_WINDOW_MS for at in captures)]
    if samples:
        worst = min(outside) if outside else float("nan")
        report.check(bool(outside) and worst >= FPS_OK, "SC-001",
                     f"pior fps fora das capturas {worst:.1f} em {len(outside)} amostras")
        slow = []
        for at, kind in items_at:
            after = [s for s in samples if s["at"] > at]
            back = next((s for s in after if s["fpsCaptured"] >= FPS_OK), None)
            if back is None or back["at"] - at > 5000:
                slow.append(f"{kind}@{(at - session['startedAt']) / 1000:.0f}s")
        report.check(not slow, "SC-001", "de volta a 60 depois de cada item" if not slow
                     else f"sem volta a 60 em 5 s: {', '.join(slow)}")
    else:
        print("  · SC-001: sem telemetria (a câmera não rodou com a coleta aberta?)")

    # ── O modelo, com dado real ─────────────────────────────────────────────
    print("\n  item     tipo     app   tela  real   abaixo do limiar")
    for item_id, kind, app, shown, truth_text, near in rows:
        shown_text = "—" if shown is None else str(shown)
        print(f"  {item_id:<8} {kind:<8} {app:>4}  {shown_text:>4}  {truth_text:>5}   {near}")

    if report.failures:
        print(f"\n{len(report.failures)} critério(s) falharam.")
        return 1
    print("\nTudo confere.")
    return 0


def draw_mark(Image, ImageDraw, jpeg, dets, th, band, side, dest):
    """As caixas que estavam na tela, sobre o quadrado gravado (SC-005)."""
    image = Image.open(io.BytesIO(jpeg)).convert("RGB")
    draw = ImageDraw.Draw(image)
    for d in dets:
        if d["score"] >= th["confidence"] and in_band(d["box"], band, side) and d["score"] >= th["appearance"]:
            x, y, w, h = d["box"]
            draw.rectangle([x, y, x + w, y + h], outline=(72, 201, 155), width=2)
    dest.parent.mkdir(parents=True, exist_ok=True)
    image.save(str(dest), quality=90)


if __name__ == "__main__":
    sys.exit(main())
