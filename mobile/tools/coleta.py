#!/usr/bin/env python3
# /// script
# requires-python = ">=3.10"
# dependencies = ["numpy", "pillow", "opencv-python-headless", "ultralytics", "torch", "torchvision"]
#
# # O PyTorch de CPU: o do PyPI traz CUDA, gigas que este computador não usa.
# [tool.uv]
# index-strategy = "unsafe-best-match"
#
# [[tool.uv.index]]
# url = "https://download.pytorch.org/whl/cpu"
# ///
"""As sessões do modo coleta, fora do app (spec 008).

    uv run tools/coleta.py pacote <zip ou pasta>… --saida <pasta> [opções]
    uv run tools/coleta.py prova  <zip ou pasta>…

`pacote` transforma sessões de treino numa pasta que o Roboflow importa
arrastando: as imagens que o modelo lê no app, com o contorno de cada livro
que o app achou, para a pessoa corrigir em vez de desenhar. O contorno é
redesenhado pelo SAM a partir da caixa de cada livro — a máscara do app tem
160×160 e erra o topo dos livros (research, R58). `prova` mede o app
contra o inventário numa sessão de prova.

O contrato está em specs/008-coleta-treino/contracts/ferramentas.md; o formato
do zip, em specs/008-coleta-treino/contracts/zip-format.md — o FORMAT.md que
vai dentro de todo zip.
"""

import argparse
import io
import json
import os
import sys
import time
import unicodedata
import zipfile
from datetime import datetime
from pathlib import Path, PurePosixPath

import cv2
import numpy as np
from PIL import Image, ImageDraw

# A ordem é a de src/collection/policy.ts: a diagonal da foto inteira usa o
# índice daqui (research, R53).
DISTANCES = {"near": "perto", "mid": "media", "far": "longe"}
ANGLES = {"left": "esquerda", "front": "frente", "right": "direita"}
LIGHTS = {"day": "dia", "night": "noite"}

SIDE = 640                 # o quadrado que o modelo lê
MIN_MASK_PIXELS = 20       # a 640, como a 006 descarta máscara vazia (R34)
POLYGON_EPSILON = 0.01     # fração do perímetro (R52)
SAM_EPSILON = 0.005        # o SAM segue a borda de perto: simplificar menos (R58)
SAM_WEIGHTS = Path.home() / ".cache" / "vizi" / "sam2.1_b.pt"
SAM_BATCH = 8              # caixas por chamada: máscaras da foto inteira têm 12 MP cada
MIN_CORRELATION = 0.97     # a conferência de equivalência (SC-003, R50)


# ── Ler sessões ───────────────────────────────────────────────────────────

class Session:
    """Uma sessão, de um zip ou de uma pasta já extraída."""

    def __init__(self, source, root, reader, lister):
        self.source = source
        self.root = root
        self._read = reader
        self._list = lister
        self.manifest = self.json("session.json")
        self.id = self.manifest.get("id") or PurePosixPath(root).name

    def bytes(self, rel):
        return self._read(f"{self.root}/{rel}" if self.root else rel)

    def json(self, rel):
        return json.loads(self.bytes(rel))

    def exists(self, rel):
        try:
            self.bytes(rel)
            return True
        except (KeyError, FileNotFoundError):
            return False

    def image(self, rel):
        return Image.open(io.BytesIO(self.bytes(rel)))

    def items(self):
        """Os itens completos, na ordem da sessão — marcas e capturas dividem o número."""
        names = {i for i in self._list() if not i.startswith(".")}
        return sorted(names, key=lambda i: i[1:])

    @property
    def purpose(self):
        return self.manifest.get("purpose")

    @property
    def light(self):
        return self.manifest.get("light")


def open_sessions(path):
    """Todas as sessões de um zip ou de uma pasta — a própria, ou as de dentro."""
    path = Path(path)
    if path.is_file():
        archive = zipfile.ZipFile(path)
        names = archive.namelist()
        roots = sorted({str(PurePosixPath(n).parent) for n in names if PurePosixPath(n).name == "session.json"})
        sessions = []
        for root in roots:
            prefix = "" if root == "." else root
            def lister(prefix=prefix):
                base = f"{prefix}/items/" if prefix else "items/"
                return {n[len(base):].split("/")[0] for n in names if n.startswith(base) and n[len(base):].count("/") >= 1}
            sessions.append(Session(path, prefix, archive.read, lister))
        return sessions
    found = [path] if (path / "session.json").exists() else sorted(p.parent for p in path.glob("*/session.json"))
    if not found:
        found = sorted(p.parent for p in path.glob("*/*/session.json"))
    sessions = []
    for folder in found:
        def reader(rel, folder=folder):
            return (folder / rel).read_bytes()
        def lister(folder=folder):
            items = folder / "items"
            return {p.name for p in items.iterdir() if p.is_dir()} if items.exists() else set()
        sessions.append(Session(path, "", reader, lister))
    return sessions


def load_all(paths):
    sessions = []
    for p in paths:
        found = open_sessions(p)
        if not found:
            sys.exit(f"{p}: nenhuma sessão (session.json) encontrada")
        sessions.extend(found)
    return sessions


# ── Máscaras e contornos ──────────────────────────────────────────────────

def protos_of(session, item_id, name):
    raw = session.bytes(f"items/{item_id}/{name}")
    return np.frombuffer(raw, dtype="<f2").astype(np.float32).reshape(32, 160, 160)


def mask_at_640(det, protos):
    """A regra do FORMAT.md, com o mapa ampliado antes do limiar: a 160 o
    contorno sai em degraus de 4 px (R52)."""
    logit = np.tensordot(np.asarray(det["coef"], np.float32), protos, axes=1)
    logit = cv2.resize(logit, (SIDE, SIDE), interpolation=cv2.INTER_LINEAR)
    x, y, w, h = det["box"]
    mask = np.zeros((SIDE, SIDE), bool)
    r0, r1 = max(0, int(np.floor(y))), min(SIDE, int(np.ceil(y + h)))
    c0, c1 = max(0, int(np.floor(x))), min(SIDE, int(np.ceil(x + w)))
    mask[r0:r1, c0:c1] = logit[r0:r1, c0:c1] > 0
    return mask


def polygon_of(mask, epsilon):
    """O contorno externo maior, simplificado; `None` sem contorno que preste."""
    found, _ = cv2.findContours(mask.astype(np.uint8), cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
    if not found:
        return None
    outline = max(found, key=cv2.contourArea)
    poly = cv2.approxPolyDP(outline, epsilon * cv2.arcLength(outline, True), True).reshape(-1, 2)
    return poly.astype(np.float64) if len(poly) >= 3 else None


def contours(detections, protos, threshold, duplicate):
    """Os livros da imagem: cada detecção aceita com o polígono da máscara do
    app, no espaço de 640, e quantas saíram como duplicata.

    Em ordem de confiança, descarta a detecção cuja máscara está `duplicate` ou
    mais dentro da máscara de uma já aceita (R52)."""
    kept, found, dropped = [], [], 0
    for det in sorted((d for d in detections if d["score"] >= threshold), key=lambda d: -d["score"]):
        mask = mask_at_640(det, protos)
        area = int(mask.sum())
        if area < MIN_MASK_PIXELS:
            continue
        if any((mask & k).sum() / min(area, k.sum()) >= duplicate for k in kept):
            dropped += 1
            continue
        poly = polygon_of(mask, POLYGON_EPSILON)
        if poly is None:
            continue
        kept.append(mask)
        found.append((det, poly))
    return found, dropped


class Refiner:
    """O SAM 2.1, com a caixa de cada livro como pergunta (R58).

    A máscara do app tem 160×160 — a 2048, um degrau de 13 px —, e no topo dos
    livros ela vaza para o vizinho. O SAM lê a imagem em 1024 e devolve a
    máscara no tamanho dela. A imagem é codificada uma vez; as caixas vão em
    lotes, porque cada máscara da foto inteira tem 12 MP."""

    def __init__(self):
        from ultralytics.models.sam import SAM2Predictor

        if not SAM_WEIGHTS.exists():
            # O Ultralytics baixa um peso conhecido para o diretório atual.
            SAM_WEIGHTS.parent.mkdir(parents=True, exist_ok=True)
            here = os.getcwd()
            os.chdir(SAM_WEIGHTS.parent)
            try:
                from ultralytics.utils.downloads import attempt_download_asset
                attempt_download_asset(SAM_WEIGHTS.name)
            finally:
                os.chdir(here)
        # `save=False`: sem isto o Ultralytics grava cada imagem em `runs/`.
        self.predictor = SAM2Predictor(overrides=dict(
            task="segment", mode="predict", imgsz=1024, model=str(SAM_WEIGHTS), verbose=False, save=False))

    def polygons(self, bgr, boxes, fallbacks):
        """Um polígono por caixa, em pixels da imagem. Sem máscara do SAM, vale
        o polígono do app — o `fallback` da mesma posição."""
        self.predictor.set_image(bgr)
        out = []
        try:
            for start in range(0, len(boxes), SAM_BATCH):
                chunk = boxes[start:start + SAM_BATCH]
                result = self.predictor(bboxes=chunk)[0]
                masks = result.masks.data.cpu().numpy().astype(bool) if result.masks is not None else []
                for i, fallback in enumerate(fallbacks[start:start + SAM_BATCH]):
                    poly = None
                    if i < len(masks) and masks[i].sum() >= MIN_MASK_PIXELS:
                        poly = polygon_of(masks[i], SAM_EPSILON)
                    out.append(poly if poly is not None else fallback)
        finally:
            self.predictor.reset_image()
        return out


def outline(found, refiner, image, scale_x, scale_y):
    """Os polígonos em pixels da imagem do pacote: os do SAM, ou os do app
    levados de 640 para a imagem."""
    app = [np.column_stack([p[:, 0] * scale_x, p[:, 1] * scale_y]) for _, p in found]
    if refiner is None or not found:
        return app
    boxes = [[d["box"][0] * scale_x, d["box"][1] * scale_y,
              (d["box"][0] + d["box"][2]) * scale_x, (d["box"][1] + d["box"][3]) * scale_y] for d, _ in found]
    bgr = np.asarray(image.convert("RGB"))[:, :, ::-1].copy()
    return refiner.polygons(bgr, boxes, app)


# ── As imagens do pacote ──────────────────────────────────────────────────

def homography(src, dst):
    a, b = [], []
    for (x, y), (u, v) in zip(src, dst):
        a.append([x, y, 1, 0, 0, 0, -u * x, -u * y]); b.append(u)
        a.append([0, 0, 0, x, y, 1, -v * x, -v * y]); b.append(v)
    return np.append(np.linalg.solve(np.asarray(a, float), np.asarray(b, float)), 1).reshape(3, 3)


def crop_square(session, item_id, item, side):
    """O recorte encaixado num quadrado de `side`, centrado, com preto em volta:
    a mesma conta do FrameTransform.fit, que o Roboflow reduz a 640 sem
    distorcer. A cunha fora da foto sai preta, como a releitura a vê (R50)."""
    crop = session.image(f"items/{item_id}/{item['images']['crop']['file']}").convert("RGB")
    w0, h0 = crop.size
    k = side / max(w0, h0)
    w, h = round(w0 * k), round(h0 * k)
    scaled = np.asarray(crop.resize((w, h), Image.LANCZOS)).copy()

    quad = (item.get("geometry") or {}).get("sourceQuad") or []
    photo = item["images"].get("photo")
    if len(quad) == 4 and photo:
        hm = homography([(0, 0), (w0, 0), (w0, h0), (0, h0)], quad)
        ys, xs = np.mgrid[0:h, 0:w]
        pts = np.stack([(xs + 0.5) / k, (ys + 0.5) / k, np.ones_like(xs, float)], -1) @ hm.T
        u, v = pts[..., 0] / pts[..., 2], pts[..., 1] / pts[..., 2]
        scaled[(u < 0) | (u > photo["width"]) | (v < 0) | (v > photo["height"])] = 0

    canvas = Image.new("RGB", (side, side))
    canvas.paste(Image.fromarray(scaled), ((side - w) // 2, (side - h) // 2))
    return canvas, (w0, h0)


def correlation(a, b, region=None):
    ga = np.asarray(a.convert("L"), float)
    gb = np.asarray(b.convert("L"), float)
    if region:
        x0, y0, x1, y1 = region
        ga, gb = ga[y0:y1, x0:x1], gb[y0:y1, x0:x1]
    if ga.size == 0 or ga.std() == 0 or gb.std() == 0:
        return 1.0 if np.allclose(ga, gb, atol=8) else 0.0
    return float(np.corrcoef(ga.ravel(), gb.ravel())[0, 1])


def check_crop(canvas, crop_size, session, item_id, item):
    """SC-003: o conteúdo no lugar gravado, e a imagem reduzida igual ao
    quadrado que a releitura leu, a menos de compressão e tom."""
    rr = item["reread"]
    w0, h0 = crop_size
    k = SIDE / max(w0, h0)
    content = [(SIDE - w0 * k) / 2, (SIDE - h0 * k) / 2, w0 * k, h0 * k]
    if max(abs(a - b) for a, b in zip(content, rr["content"])) > 0.5:
        return f"o conteúdo cai em {[round(v, 1) for v in content]}, e a releitura gravou {rr['content']}"
    small = canvas.resize((SIDE, SIDE), Image.BOX)
    ref = session.image(f"items/{item_id}/{item['images']['rereadSquare']['file']}").convert("RGB")
    cx, cy, cw, ch = rr["content"]
    r = correlation(small, ref, (int(cx) + 2, int(cy) + 2, int(cx + cw) - 2, int(cy + ch) - 2))
    return None if r >= MIN_CORRELATION else f"correlação {r:.3f} com o quadrado da releitura"


def check_photo(photo, session, item_id, item):
    """SC-003 para a foto: esticada a 640 como o Roboflow e o app esticam."""
    small = photo.convert("RGB").resize((SIDE, SIDE), Image.BOX)
    ref = session.image(f"items/{item_id}/{item['images']['photoSquare']['file']}").convert("RGB")
    r = correlation(small, ref)
    return None if r >= MIN_CORRELATION else f"correlação {r:.3f} com o quadrado da foto"


# ── Nomes ─────────────────────────────────────────────────────────────────

def slug(text):
    text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode().lower()
    out = "".join(ch if ch.isalnum() else "-" for ch in text)
    while "--" in out:
        out = out.replace("--", "-")
    return out.strip("-") or "sem-nome"


def image_name(session, item_id, tags, kind):
    """`<sessão>_<item>_<prateleira>_<distância>-<ângulo>-<luz>_<recorte|foto>.jpg`
    (contrato, "A pasta")."""
    parts = [session.id, item_id]
    light = LIGHTS.get(session.light or "", "")
    if tags is None:
        pass
    elif tags.get("background"):
        parts += ["sem-livros", light]
    else:
        shelf = (tags.get("shelf") or {}).get("name") or "sem-prateleira"
        variation = [DISTANCES.get(tags.get("distance") or ""), ANGLES.get(tags.get("angle") or ""), light]
        parts += [slug(shelf), "-".join(v for v in variation if v)]
    parts.append(kind)
    return "_".join(p for p in parts if p) + ".jpg"


# ── pacote ────────────────────────────────────────────────────────────────

def wants_photo(tags, light, legacy_index):
    """A foto inteira vai na diagonal do guia: (distância + ângulo + luz) mod 3
    = 0 — três das nove células por luz, uma de cada distância e uma de cada
    ângulo, e a noite pega outra diagonal (R53). Sem variação gravada, uma em
    cada três pela ordem."""
    if tags is None or not tags.get("distance") or not tags.get("angle"):
        return legacy_index % 3 == 0
    d = list(DISTANCES).index(tags["distance"])
    a = list(ANGLES).index(tags["angle"])
    l = 1 if light == "night" else 0
    return (d + a + l) % 3 == 0


def cmd_pacote(args):
    sessions = load_all(args.entradas)

    refused = []
    for s in sessions:
        if s.purpose == "exam":
            refused.append(f"{s.id}: é uma prova — a prova nunca entra no treino")
        elif s.purpose is None and not args.sem_tipo:
            refused.append(f"{s.id}: sessão sem tipo, de antes da spec 008 — use --sem-tipo para aceitá-la como treino")
        elif s.purpose not in (None, "training"):
            refused.append(f"{s.id}: tipo desconhecido {s.purpose!r}")
    if refused:
        print("Nada gerado:", *refused, sep="\n  ", file=sys.stderr)
        return 2

    out = Path(args.saida)
    if out.exists() and any(out.iterdir()):
        print(f"{out} já existe e não está vazia: escolha outra pasta.", file=sys.stderr)
        return 2
    out.mkdir(parents=True, exist_ok=True)
    preview = Path(args.previa) if args.previa else None
    if preview:
        preview.mkdir(parents=True, exist_ok=True)

    # Só as imagens (R59): quem marca é a IA do Roboflow, e nada aqui precisa
    # de máscara, SAM nem anotação.
    contour = not args.so_imagens
    refiner = None if args.sem_sam or not contour else Refiner()
    if args.so_imagens and preview:
        print("  --previa ignorada: com --so-imagens não há contorno a desenhar.")
        preview = None

    def progress(name, count, started):
        if contour:  # só as imagens leva segundos: a linha por imagem é para o SAM
            print(f"  {name} · {count} contornos · {time.time() - started:.1f} s", flush=True)

    coco = {
        "info": {"description": "vizi — pacote da coleta", "date_created": datetime.now().isoformat(timespec="seconds")},
        "categories": [{"id": 1, "name": "book", "supercategory": "none"}],
        "images": [],
        "annotations": [],
    }
    summary = {}
    rejected = []

    def add(name, image, polygons, group, kind, dropped=0, raw=None):
        image_id = len(coco["images"]) + 1
        if raw is not None:
            (out / name).write_bytes(raw)
        else:
            image.save(out / name, quality=92)
        coco["images"].append({"id": image_id, "file_name": name, "width": image.width, "height": image.height})
        drawn = []
        for pts in polygons:
            x0, y0 = pts.min(axis=0)
            x1, y1 = pts.max(axis=0)
            coco["annotations"].append({
                "id": len(coco["annotations"]) + 1, "image_id": image_id, "category_id": 1,
                "segmentation": [[round(float(v), 1) for v in pts.ravel()]],
                "bbox": [round(float(x0), 1), round(float(y0), 1), round(float(x1 - x0), 1), round(float(y1 - y0), 1)],
                "area": round(float(cv2.contourArea(pts.astype(np.float32))), 1),
                "iscrowd": 0,
            })
            drawn.append(pts)
        row = summary.setdefault(group, {"recorte": 0, "foto": 0, "sem livros": 0, "contornos": 0, "duplicatas": 0})
        row[kind] += 1
        row["contornos"] += len(polygons)
        row["duplicatas"] += dropped
        if preview:
            shown = image.convert("RGB").copy()
            draw = ImageDraw.Draw(shown)
            for pts in drawn:
                draw.polygon([tuple(p) for p in pts], outline=(72, 201, 155), width=max(2, shown.width // 600))
            shown.thumbnail((1600, 1600))
            shown.save(preview / name, quality=85)

    for s in sessions:
        legacy_counter = {}
        for item_id in s.items():
            if not item_id.startswith("c"):
                continue  # marcas não vão (FR-020)
            item = s.json(f"items/{item_id}/item.json")
            tags = item.get("tags")
            background = bool(tags and tags.get("background"))
            threshold = args.confianca if args.confianca is not None else item["thresholds"]["confidence"]
            group = "sem livros" if background else ((tags or {}).get("shelf") or {}).get("name") or s.id
            has_crop = bool(item.get("reread")) and "crop" in item["images"] and "rereadSquare" in item["images"]

            if has_crop and not background:
                name = image_name(s, item_id, tags, "recorte")
                canvas, crop_size = crop_square(s, item_id, item, args.lado)
                problem = check_crop(canvas, crop_size, s, item_id, item)
                if problem:
                    rejected.append(f"{name}: {problem}")
                else:
                    started = time.time()
                    polygons, dropped = [], 0
                    if contour:
                        protos = protos_of(s, item_id, item["reread"]["protos"])
                        found, dropped = contours(item["reread"]["detections"], protos, threshold, args.duplicata)
                        polygons = outline(found, refiner, canvas, args.lado / SIDE, args.lado / SIDE)
                    add(name, canvas, polygons, group, "recorte", dropped)
                    progress(name, len(polygons), started)

            key = group
            index = legacy_counter.get(key, 0)
            legacy_counter[key] = index + 1
            if background or not has_crop or wants_photo(tags, s.light, index):
                kind = "sem livros" if background else "foto"
                name = image_name(s, item_id, tags, "foto")
                raw = s.bytes(f"items/{item_id}/{item['images']['photo']['file']}")
                photo = Image.open(io.BytesIO(raw))
                problem = check_photo(photo, s, item_id, item)
                if problem:
                    rejected.append(f"{name}: {problem}")
                    continue
                polygons, dropped = [], 0
                started = time.time()
                if not background and contour:
                    if item.get("transform", "stretch") != "stretch":
                        rejected.append(f"{name}: transformação {item.get('transform')!r}; só a esticada leva à foto")
                        continue
                    protos = protos_of(s, item_id, item["photoRead"]["protos"])
                    found, dropped = contours(item["photoRead"]["detections"], protos, threshold, args.duplicata)
                    polygons = outline(found, refiner, photo, photo.width / SIDE, photo.height / SIDE)
                add(name, photo, polygons, group, kind, dropped, raw=raw)
                progress(name, len(polygons), started)

    if not coco["images"]:
        print("Nenhuma imagem gerada: as sessões não têm captura que passe na conferência"
              " (marcas não vão para o pacote).", *rejected, sep="\n  ", file=sys.stderr)
        if not any(out.iterdir()):
            out.rmdir()
        return 1

    if contour:
        (out / "_annotations.coco.json").write_text(json.dumps(coco, ensure_ascii=False))
        print(f"pacote em {out}: {len(coco['images'])} imagens, {len(coco['annotations'])} contornos")
    else:
        print(f"pacote em {out}: {len(coco['images'])} imagens, sem contornos")
    print(f"\n  {'prateleira':<28} {'recorte':>7} {'foto':>5} {'sem livros':>10} {'contornos':>9} {'duplicatas':>10}")
    for group, row in sorted(summary.items()):
        print(f"  {group[:28]:<28} {row['recorte']:>7} {row['foto']:>5} {row['sem livros']:>10} "
              f"{row['contornos']:>9} {row['duplicatas']:>10}")
    if rejected:
        print(f"\n  {len(rejected)} recusada(s) na conferência — não entraram:")
        for line in rejected:
            print(f"    {line}")
    if preview:
        print(f"\n  prévias com os contornos em {preview}")
    if contour:
        print("\nNo Roboflow: solte primeiro o _annotations.coco.json, depois as imagens.")
    else:
        print("\nNo Roboflow: suba as imagens e marque com \"Find Objects with AI\", pedindo \"book\".")
    return 0


# ── prova ─────────────────────────────────────────────────────────────────

def cmd_prova(args):
    sessions = load_all(args.entradas)
    not_exam = [s.id for s in sessions if s.purpose != "exam"]
    if not_exam:
        print("Só sessões de prova:", *[f"{i}: não é prova" for i in not_exam], sep="\n  ", file=sys.stderr)
        return 2

    total = exact = 0
    for s in sessions:
        rows = []
        for item_id in s.items():
            if not item_id.startswith("c"):
                continue
            item = s.json(f"items/{item_id}/item.json")
            shelf = (item.get("tags") or {}).get("shelf") or {}
            truth = s.json(f"items/{item_id}/truth.json") if s.exists(f"items/{item_id}/truth.json") else None
            answer = None if truth is None or truth.get("skipped") else truth.get("count")
            rows.append((shelf, item_id, item["result"]["count"], answer))

        model = (s.manifest.get("model") or {}).get("weightsSha256", "?")[:12]
        print(f"prova {s.id} · modelo {model} · {len(rows)} capturas\n")
        print(f"  {'prateleira':<26} {'item':<6} {'app':>4} {'gabarito':>9} {'inventário':>11}")
        per_shelf = {}
        for shelf, item_id, app, answer in rows:
            name = shelf.get("name", "—")
            inventory = shelf.get("count")
            # O JavaScript manda número como double: 22 pode chegar como 22.0.
            if isinstance(inventory, float) and inventory.is_integer():
                inventory = int(inventory)
            if answer is None:
                verdict = "sem gabarito"
            else:
                ok = app == answer
                verdict = "✓" if ok else f"✗ {app - answer:+d}"
                total += 1
                exact += ok
                hits, n = per_shelf.get(name, (0, 0))
                per_shelf[name] = (hits + ok, n + 1)
            if answer is not None and inventory is not None and answer != inventory:
                verdict += f"  (gabarito ≠ inventário {inventory})"
            print(f"  {name[:26]:<26} {item_id:<6} {app:>4} {'—' if answer is None else answer:>9} "
                  f"{'—' if inventory is None else inventory:>11}   {verdict}")

        captured = {(r[0] or {}).get("id") for r in rows}
        missing = [sh for sh in s.manifest.get("shelves") or [] if sh.get("id") not in captured]
        print()
        if per_shelf:
            print("  por prateleira: " + " · ".join(f"{n} {h}/{t}" for n, (h, t) in per_shelf.items()))
        print("  sem captura: " + (", ".join(sh.get("name", "?") for sh in missing) if missing else "nenhuma"))
        print()

    if total:
        print(f"exatas: {exact} de {total} ({100 * exact / total:.0f}%)")
    else:
        print("nenhuma captura com gabarito")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="comando", required=True)

    p = sub.add_parser("pacote", help="sessões de treino → pasta para o Roboflow")
    p.add_argument("entradas", nargs="+", help="zips exportados pelo app, ou as pastas extraídas")
    p.add_argument("--saida", required=True, help="pasta a criar; vazia ou inexistente")
    p.add_argument("--sem-tipo", action="store_true", help="aceita sessões anteriores à 008, como treino")
    p.add_argument("--lado", type=int, default=2048, help="lado da imagem do recorte (padrão 2048)")
    p.add_argument("--confianca", type=float, default=None,
                   help="confiança mínima de um contorno (padrão: o limiar gravado no item)")
    p.add_argument("--duplicata", type=float, default=0.8,
                   help="fração da máscara dentro de uma mais forte que a descarta (padrão 0,8)")
    p.add_argument("--previa", help="pasta para cópias com os contornos desenhados, para conferir antes")
    p.add_argument("--so-imagens", action="store_true",
                   help="só as imagens, sem contornos nem _annotations.coco.json: quem marca é a IA do Roboflow")
    p.add_argument("--sem-sam", action="store_true",
                   help="contornos da máscara do app, sem o SAM: rápido, mas grosseiro no topo dos livros")
    p.set_defaults(run=cmd_pacote)

    p = sub.add_parser("prova", help="a contagem do app contra o inventário")
    p.add_argument("entradas", nargs="+", help="zips de prova, ou as pastas extraídas")
    p.set_defaults(run=cmd_prova)

    args = parser.parse_args()
    return args.run(args)


if __name__ == "__main__":
    sys.exit(main())
