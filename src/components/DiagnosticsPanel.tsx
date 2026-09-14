import React from 'react';
import { motionThreshold as MOTION_THRESHOLD, modelVariant } from '../lib/debugFlags';

/** Um retrato da última inferência, para ler na tela do celular. */
export interface Diagnostics {
  frame: string;
  boxes: number;
  maskBytes: number;
  expectedMaskBytes: number;
  /** Leitura de pixels + resize, medido pelo engine. */
  preprocessMs: number;
  inferenceMs: number;
  /** NMS + composição da máscara RGBA, medido pelo engine. */
  postprocessMs: number;
  /** Tempo do nosso desenho no canvas, medido aqui. */
  drawMs: number;
  /**
   * Relógio de parede em volta do `model.predict` inteiro. Maior que a soma de
   * pre+infer+post porque o wrapper faz a leitura de pixels (`toImageData`) e a
   * cópia dos resultados para fora do wasm sem contabilizar em `speed`.
   */
  predictMs: number;
  /**
   * Média móvel do intervalo real entre o início de duas inferências. É o que
   * fecha a conta: se a soma dos quatro estágios acima ficar bem abaixo deste
   * número, há tempo sendo gasto fora do que está instrumentado.
   */
  intervalMs: number;
  /** Diferença média por pixel (0-255) contra o frame da última inferência. */
  motion: number;
  /** Se este ciclo pulou a inferência por falta de movimento. */
  gated: boolean;
  /** Ociosidade sendo intercalada pela guarda térmica. 0 = aparelho saudável. */
  thermalIdleMs: number;
  /**
   * Inferência mais rápida vista nesta sessão. É a referência que a guarda
   * térmica usa como "aparelho frio" — e por isso precisa estar visível: se o
   * app abriu com o aparelho já quente, esta referência nasce quente e a guarda
   * nunca dispara. Comparar com `inferenceMs` é o que revela esse caso.
   */
  fastestInferenceMs: number;
  error: string | null;
}

interface DiagnosticsPanelProps {
  device: string | null;
  task: string | null;
  names: Record<number, string>;
  diagnostics: Diagnostics | null;
}

/**
 * Propriedades do ambiente, lidas uma vez: não mudam durante a sessão e não
 * teriam por que viajar dentro de um objeto reconstruído a cada inferência.
 *
 * `crossOriginIsolated` é o que diz se o LiteRT pôde escolher o build wasm
 * multi-thread — sem isolamento não há SharedArrayBuffer, e o modelo roda num
 * núcleo só. É a métrica que valida a fase de COOP/COEP.
 */
const CORES = navigator.hardwareConcurrency ?? 0;
const IS_ISOLATED = globalThis.crossOriginIsolated === true;

export const DiagnosticsPanel: React.FC<DiagnosticsPanelProps> = ({
  device,
  task,
  names,
  diagnostics
}) => {
  const classNames = Object.values(names);

  return (
    <div className="diagnostics-panel">
      {/* Sem isto não há como saber qual variante produziu uma medição — e
          comparar 320 contra 640 é justamente o que o flag `?model=` existe
          para permitir. */}
      <div><strong>modelo</strong> {modelVariant}</div>
      <div><strong>device</strong> {device ?? '—'}</div>
      <div><strong>task</strong> {task ?? '—'}</div>
      {/* Classe única confirma que não há o que filtrar: todo box é "livro". */}
      <div><strong>classes</strong> {classNames.length ? classNames.join(', ') : '—'}</div>
      {/* Um `coi false` explica sozinho um tempo de inferência alto no CPU. */}
      <div>
        <strong>coi</strong> {IS_ISOLATED ? 'sim' : 'não'} · {CORES || '?'} núcleos
      </div>

      {diagnostics ? (
        <>
          <div><strong>frame</strong> {diagnostics.frame}</div>
          <div><strong>boxes</strong> {diagnostics.boxes}</div>
          {/* Se maskBytes for 0 com task=segment, o modelo rodou mas não
              produziu máscara. Se divergir do esperado, o overlay não bate
              com o frame e é descartado no desenho. */}
          <div>
            <strong>mask</strong> {diagnostics.maskBytes} / {diagnostics.expectedMaskBytes}
          </div>

          {/* Os quatro estágios do ciclo, na ordem em que acontecem. */}
          <div><strong>pre</strong> {diagnostics.preprocessMs.toFixed(0)}ms</div>
          <div>
            <strong>infer</strong> {diagnostics.inferenceMs.toFixed(0)}ms
            {Number.isFinite(diagnostics.fastestInferenceMs) && (
              <> · min {diagnostics.fastestInferenceMs.toFixed(0)}ms</>
            )}
          </div>
          <div><strong>post</strong> {diagnostics.postprocessMs.toFixed(0)}ms</div>
          <div><strong>draw</strong> {diagnostics.drawMs.toFixed(1)}ms</div>

          {/* O que o `speed` do engine não vê: leitura de pixels para RGBA e
              cópia das caixas/máscara para fora do wasm. É o candidato a
              otimização que só aparece medindo o predict por fora. */}
          <div>
            <strong>extra</strong>{' '}
            {Math.max(
              0,
              diagnostics.predictMs -
                diagnostics.preprocessMs -
                diagnostics.inferenceMs -
                diagnostics.postprocessMs
            ).toFixed(0)}
            ms
          </div>

          {/* Tempo em que o loop não fez nada: throttle + granularidade do rAF.
              Se for alto, o gargalo é agendamento, não computação. */}
          <div>
            <strong>ocioso</strong>{' '}
            {Math.max(0, diagnostics.intervalMs - diagnostics.predictMs - diagnostics.drawMs).toFixed(0)}ms
          </div>

          {/* Leitura ao vivo do detector de movimento, ao lado do limiar: é
              assim que se calibra o `?motion=N` no aparelho. Com a cena parada
              o resto do painel congela e só esta linha continua se mexendo. */}
          <div>
            <strong>movim</strong>{' '}
            {Number.isFinite(diagnostics.motion) ? diagnostics.motion.toFixed(1) : '—'} /{' '}
            {MOTION_THRESHOLD.toFixed(1)}{' '}
            {diagnostics.gated ? '· parado' : '· ativo'}
          </div>

          {/* Só aparece quando a guarda age: em uso normal esta linha some, e
              vê-la é o sinal de que o aparelho está esquentando. */}
          {diagnostics.thermalIdleMs > 0 && (
            <div>
              <strong>térmico</strong> +{diagnostics.thermalIdleMs.toFixed(0)}ms
            </div>
          )}

          {/* O total de fato, e a taxa que ele produz. */}
          <div>
            <strong>ciclo</strong> {diagnostics.intervalMs.toFixed(0)}ms ·{' '}
            {diagnostics.intervalMs > 0
              ? `${(1000 / diagnostics.intervalMs).toFixed(1)} fps`
              : '—'}
          </div>

          {diagnostics.error && <div className="diagnostics-error">{diagnostics.error}</div>}
        </>
      ) : (
        <div>aguardando inferência…</div>
      )}
    </div>
  );
};
