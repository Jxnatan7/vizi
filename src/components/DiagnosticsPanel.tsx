import React from 'react';

/** Um retrato da última inferência, para ler na tela do celular. */
export interface Diagnostics {
  frame: string;
  boxes: number;
  maskBytes: number;
  expectedMaskBytes: number;
  inferenceMs: number;
  error: string | null;
}

interface DiagnosticsPanelProps {
  device: string | null;
  task: string | null;
  names: Record<number, string>;
  diagnostics: Diagnostics | null;
}

export const DiagnosticsPanel: React.FC<DiagnosticsPanelProps> = ({
  device,
  task,
  names,
  diagnostics
}) => {
  const classNames = Object.values(names);
  return (
    <div className="diagnostics-panel">
      <div><strong>device</strong> {device ?? '—'}</div>
      <div><strong>task</strong> {task ?? '—'}</div>
      {/* Classe única confirma que não há o que filtrar: todo box é "livro". */}
      <div><strong>classes</strong> {classNames.length ? classNames.join(', ') : '—'}</div>

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
          <div><strong>infer</strong> {diagnostics.inferenceMs.toFixed(0)}ms</div>
          {diagnostics.error && <div className="diagnostics-error">{diagnostics.error}</div>}
        </>
      ) : (
        <div>aguardando inferência…</div>
      )}
    </div>
  );
};
