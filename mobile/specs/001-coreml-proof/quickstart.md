# Quickstart — do repositório limpo ao app medindo no iPhone

Satisfaz o **SC-007**: repetível do zero sem consultar histórico de conversa.

> Procedimento de assinatura escrito a partir da documentação das ferramentas
> em 15/09/2026, **ainda não executado**. Corrigir aqui o que divergir na
> primeira execução — é o T016.

---

## Parte 1 — Exportar o modelo (Colab, uma vez por mudança de modelo)

Roda onde vivem o dataset e os pesos. O repositório recebe só o resultado.

```python
!pip install -U ultralytics coremltools

from ultralytics import YOLO

model = YOLO("best.pt")

model.export(
    format="coreml",
    imgsz=640,          # quadrado: a geometria em que o modelo foi treinado
    half=True,          # fp16: formato nativo do acelerador
    nms=False,          # NMS embutido tira operacoes do acelerador
)
```

**Por que quadrado e não retangular.** A câmera entrega 4:3, e exportar em
480×640 economizaria 25% da computação. Mas **o dataset é 640×640**, e o modelo
aprendeu essa proporção. Exportar retangular comprimiria os livros em 25%
horizontalmente em relação a tudo que ele viu no treino — mudança de proporção,
não de escala, e a degradação seria silenciosa.

A economia continua disponível, pelo caminho certo: **retreinar** em 480×640.
Isso é decisão para depois de haver um número de latência, não antes.

**Por que `nms=False`:** o NMS embutido insere operações que o compilador não
coloca no acelerador dedicado, e arrasta camadas vizinhas junto. A decodificação
acontece em Swift, onde custa uma fração de milissegundo.

**Conferir logo após exportar**, ainda no Colab:

```python
import coremltools as ct
m = ct.models.MLModel("best.mlpackage")
print(m.get_spec().description)
```

Um modelo de segmentação deve expor **duas saídas** — detecção e protótipos de
máscara. Se só houver uma, o ramo de máscara não veio e o marco 5 fica sem
matéria-prima. Anotar os shapes em `models/vizi-seg.shapes.md`: são a fonte da
verdade para o módulo nativo.

### A imagem de referência

**Uma imagem do conjunto de validação, em 640×640** — o mesmo formato do
dataset e da entrada do modelo.

Por que isso importa: com a imagem já no formato exato da entrada, **nenhum dos
dois caminhos redimensiona**. O `predict` não faz letterbox e o Core ML não
estica. Os dois veem pixels idênticos, e a comparação da US3 mede só o que
deveria — se a conversão preservou o comportamento, e não uma diferença de
geometria.

Escolher uma com quantidade média de instâncias: poucas não exercitam a
decodificação, muitas tornam a comparação frágil porque detecções na borda da
confiança entram e saem.

Gerar a saída de referência na mesma sessão:

```python
r = model.predict("reference.jpg", imgsz=640, conf=0.25)[0]

import json
json.dump({
    "classes":     r.boxes.cls.tolist(),
    "confidences": r.boxes.conf.tolist(),
    "boxes_xyxy":  r.boxes.xyxy.tolist(),
}, open("reference-expected.json", "w"), indent=2)
```

Baixar do Colab (o `.mlpackage` é uma **pasta**, então compactar antes):

```python
!zip -r vizi-seg.mlpackage.zip best.mlpackage
from google.colab import files
files.download("vizi-seg.mlpackage.zip")
files.download("reference-expected.json")
```

Commitar:

```
mobile/models/vizi-seg.mlpackage/     <- versionado de proposito
mobile/models/vizi-seg.shapes.md
mobile/assets/reference.jpg
mobile/assets/reference-expected.json
```

---

## Parte 2 — Preparar o ambiente local (uma vez)

```bash
cd mobile && npm install
```

### Ferramentas de assinatura e instalação

```bash
sudo apt install usbmuxd libimobiledevice-utils ideviceinstaller
```

> **Não rodar `systemctl enable usbmuxd`.** A unit não tem seção `[Install]` de
> propósito: o serviço é ativado por udev quando um dispositivo Apple é
> conectado (`39-usbmuxd.rules`, `ENV{SYSTEMD_WANTS}="usbmuxd.service"` para o
> fabricante `5ac`). Basta conectar o iPhone. Conferir com:
>
> ```bash
> systemctl is-active usbmuxd    # 'active' depois de plugar
> ```
>
> Não existe pacote `libplist3` no Ubuntu 24.04 — o nome ali é `libplist-2.0-4`,
> e entra como dependência. Ambos verificados em 15/09/2026.

Baixar o binário estático do **AltServer-Linux**. Usar o fork
`jaakkopalvaila/AltServer-Linux`, não o upstream: ele carrega a correção de
assinatura para iOS 26.4+ e a correção de login de Apple ID de setembro de 2026.

```bash
sudo apt install libavahi-compat-libdnssd1   # fornece libdns_sd.so

mkdir -p ~/.local/bin && cd ~/.local/bin
curl -fLO https://github.com/jaakkopalvaila/AltServer-Linux/releases/download/ng-2026-09-13/AltServer-x86_64
mv AltServer-x86_64 AltServer && chmod +x AltServer
```

Trocar `x86_64` pela arquitetura de `uname -m` se for outra — o release também
traz `aarch64`, `armv7` e `i586`.

Sem `libdns_sd.so` o AltServer cospe um traceback de Python ao iniciar,
tentando anunciar-se por mDNS. Não impede a instalação por USB, mas parece
falha grave e não é.

Flags (atenção: **`-h`, não `--help`** — `--help` é rejeitado):

```
-u  --udid UDID        UDID do aparelho
-a  --appleID AppleID
-p  --password passwd
-d  --debug            repetível, aumenta o nível
```

### Parear o aparelho

Conectar por USB, desbloquear, e tocar em **Confiar** quando o iPhone
perguntar.

```bash
idevicepair pair
idevice_id -l      # imprime o UDID; guardar
```

#### Se `idevice_id` vier vazio

O stack empacotado do Ubuntu 24.04 é **anterior ao iOS 17**:

| pacote | candidato | |
|---|---|---|
| `libimobiledevice-utils` | 1.3.0-8.1build3 | 2020 |
| `ideviceinstaller` | 1.1.1-1build4 | 2020 |

Compilar do git, **nesta ordem** — cada um depende do anterior:

```bash
sudo apt install build-essential git autoconf automake libtool-bin pkg-config \
  libssl-dev libusb-1.0-0-dev libcurl4-openssl-dev libzip-dev

sudo systemctl stop usbmuxd

for r in libplist libimobiledevice-glue libusbmuxd libimobiledevice usbmuxd ideviceinstaller; do
  git clone https://github.com/libimobiledevice/$r
  ( cd $r && ./autogen.sh --prefix=/usr/local && make && sudo make install )
done
sudo ldconfig
```

O `AltServer` é binário estático e traz a própria cópia do libimobiledevice,
então isto afeta principalmente o passo de descobrir o UDID.

**Contorno, se só o UDID travar:** o número de série USB do iPhone *é* o UDID.

```bash
sudo lsusb -v 2>/dev/null | grep -i iserial
```

### Modo de Desenvolvedor — a ordem importa

**A opção não existe em Ajustes até o iOS ver um gatilho de desenvolvimento.**
Procurar por ela antes da primeira tentativa de instalação é procurar algo que
ainda não foi criado — não é bug nem falta de conta paga.

A sequência correta:

1. Rodar o `AltServer` uma primeira vez (Parte 4). **Vai falhar** — é esperado.
2. A tentativa faz surgir **Ajustes → Privacidade e Segurança → Modo de
   Desenvolvedor**.
3. Ligar e reiniciar o aparelho.
4. Rodar o `AltServer` de novo. Agora instala.
5. **Ajustes → Geral → VPN e Gerenciamento de Dispositivo** → confiar no
   desenvolvedor.

Os passos 1 a 3 acontecem uma única vez na vida do aparelho.

---

## Parte 3 — Compilar (a cada mudança nativa, raro)

Disparado por push na branch. O runner macOS executa:

```
expo prebuild --platform ios     # gera ios/ a partir de app.config.js
pod install
xcodebuild  (sem assinatura)
empacota o app compilado em um .ipa
```

O artefato fica disponível para download. Repositório público, runners macOS
gratuitos e ilimitados — não há orçamento de build a economizar.

---

## Parte 4 — Assinar e instalar (a cada compilação, e a cada 7 dias)

Baixar o artefato `vizi-unsigned-ipa` da execução do workflow e então:

```bash
./AltServer -u <UDID> -a <seu-apple-id> -p <senha> vizi-unsigned.ipa
```

Um comando faz tudo: autentica na Apple, obtém certificado de desenvolvimento,
registra o UDID do aparelho, cria o App ID, gera o perfil de provisionamento,
assina o `.ipa` e instala por USB.

Depois, no iPhone: **Ajustes → Geral → VPN e Gerenciamento de Dispositivo** →
confiar no desenvolvedor.

### O servidor de anisette — definir sempre

O padrão embutido no AltServer (`armconverter.com/...`) está **fora do ar**, e
o do Sideloadly também. Ambos devolvem HTTP 502, e o AltServer tenta ler a
página de erro como JSON:

```
Received response status code: 502
Incorrect Content-Type: must be textual to extract_string, JSON to extract_json.
```

Quando isso acontece o login nunca ocorre — e, por consequência, o **Modo de
Desenvolvedor não aparece**, porque nenhuma instalação de desenvolvimento foi
tentada.

Servidor verificado funcionando em 15/09/2026:

```bash
export ALTSERVER_ANISETTE_SERVER=https://ani.sidestore.io
```

Devolve o formato v1 completo, incluindo `X-MMe-Client-Info` (atenção à
capitalização: `MMe`, não `Mme`).

**Não vale a pena subir `nyamisty/alt_anisette_server` localmente:** a imagem
roda Wine com o iCloud para Windows e automatiza o login por AutoHotkey,
exigindo credenciais Apple próprias configuradas no container. Sem elas, ela
sai com `Your Apple ID or password is incorrect` e nunca abre a porta 6969.

**Por que o client-info desatualizado não atrapalha:** o servidor devolve
`com.apple.dt.Xcode`, string que a Apple bloqueia com HTTP 503 desde setembro
de 2026. O fork NG substitui por `com.apple.akd` antes de enviar (Fix 2), o que
torna irrelevante um servidor de anisette defasado — mas não um morto.

**Como distinguir os erros:** HTTP 503 significa que a Apple ainda está
bloqueando; um código GSA como `-20101` ou `-20209` significa que a requisição
chegou ao serviço e o problema é a credencial.

### Restrições da conta gratuita

| | |
|---|---|
| validade da assinatura | **7 dias** |
| apps instalados | 3 simultâneos |
| App IDs | 10 por 7 dias — por isso o `bundleIdentifier` não deve mudar à toa |
| autenticação | senha real + 2FA; senha de app específica **não** funciona |

**A cada 7 dias** o app para de abrir. A recuperação repete **apenas esta
parte**, com o mesmo `.ipa` já baixado — sem recompilar (**SC-006**).

### Alternativa, se o AltServer não fechar

`Sideloader` (D, compilar com `dub build`) faz o mesmo fluxo e é a segunda
tentativa antes de considerar a conta paga. Exige toolchain D — LDC2 ou DMD
2.104.2+; GDC não serve.

---

## Parte 5 — Iterar no JavaScript (o ciclo normal)

```bash
cd mobile && npx expo start
```

Abrir o app no aparelho e conectar. Alterações em `src/` e `App.tsx` aparecem
sem recompilar (**SC-004**). Só `modules/vizi-vision/` e dependências nativas
exigem voltar à Parte 3.

---

## Parte 6 — Medir

1. Aparelho o mais frio possível. Fechar outros apps.
2. Abrir o app e anotar a **latência da primeira execução** — ela inclui
   preparação do modelo e não se repete.
3. Disparar a sequência de 100 repetições.
4. Ler mediana, p95, condição térmica e unidade de execução.
5. Conferir as instâncias detectadas contra `reference-expected.json`.

**O portão:** mediana < 30 ms e p95 < 40 ms, com o aparelho em temperatura
normal, e instâncias batendo com a referência.

**Se o aparelho estiver quente,** a medição não é comparável com uma anterior a
frio. O protótipo web mediu variação de 264 a 317 ms no mesmo modelo por causa
de temperatura — cerca de 20%. Abaixo disso, diferença não é distinguível de
ruído.
