import { requireNativeView } from 'expo';
import type { ViewProps } from 'react-native';

/**
 * Mostra o buffer que o modelo recebe — já transformado, não a câmera crua.
 *
 * Nenhum pixel atravessa a fronteira: a view nativa recebe o buffer direto da
 * fila da câmera (princípio II).
 */
const NativePreview = requireNativeView<ViewProps>('ViziVision', 'PreviewView');

export default function PreviewView(props: ViewProps) {
  return <NativePreview {...props} />;
}
