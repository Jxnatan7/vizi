import React from 'react';
import type { OverlayOptions } from '../lib/overlay';

interface OverlayControlsProps extends OverlayOptions {
  /** Falso quando o modelo carregado não tem cabeça de segmentação. */
  canSegment: boolean;
  confidence: number;
  /** Ausente fora do modo debug: o limiar é um botão de calibração, não de uso. */
  onConfidenceChange?: (value: number) => void;
  onShowBoxesChange: (value: boolean) => void;
  onShowMasksChange: (value: boolean) => void;
  onMaskOpacityChange: (value: number) => void;
}

export const OverlayControls: React.FC<OverlayControlsProps> = ({
  showBoxes,
  showMasks,
  maskOpacity,
  canSegment,
  confidence,
  onConfidenceChange,
  onShowBoxesChange,
  onShowMasksChange,
  onMaskOpacityChange
}) => {
  return (
    <div className="overlay-controls">
      <div className="overlay-toggles">
        <label className="overlay-toggle">
          <input
            type="checkbox"
            checked={showBoxes}
            onChange={(e) => onShowBoxesChange(e.target.checked)}
          />
          <span>Caixas</span>
        </label>

        <label className={`overlay-toggle ${canSegment ? '' : 'disabled'}`}>
          <input
            type="checkbox"
            checked={showMasks}
            disabled={!canSegment}
            onChange={(e) => onShowMasksChange(e.target.checked)}
          />
          <span>Segmentação</span>
        </label>
      </div>

      {/* O slider só multiplica o alfa que o engine já embutiu na máscara,
          então 1 é o padrão do Ultralytics e o máximo possível. */}
      <label className={`overlay-slider ${showMasks && canSegment ? '' : 'disabled'}`}>
        <span>Opacidade</span>
        <input
          type="range"
          min="0"
          max="1"
          step="0.05"
          value={maskOpacity}
          disabled={!showMasks || !canSegment}
          onChange={(e) => onMaskOpacityChange(Number(e.target.value))}
        />
      </label>

      {onConfidenceChange && (
        <label className="overlay-slider">
          <span>Confiança {Math.round(confidence * 100)}%</span>
          <input
            type="range"
            min="0.05"
            max="0.95"
            step="0.05"
            value={confidence}
            onChange={(e) => onConfidenceChange(Number(e.target.value))}
          />
        </label>
      )}
    </div>
  );
};
