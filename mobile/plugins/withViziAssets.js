const { withDangerousMod } = require('expo/config-plugins');
const fs = require('fs');
const path = require('path');

/**
 * Copia o modelo e a imagem de referência para dentro do módulo nativo, onde o
 * CocoaPods consegue enxergá-los.
 *
 * Por que isto existe: `resource_bundles` no podspec só resolve caminhos dentro
 * da raiz do pod. Apontar para `../../../models/` produz um bundle vazio — sem
 * erro, sem aviso, e a falha só aparece em tempo de execução no aparelho.
 *
 * Roda antes do `pod install`, na fase dangerous do prebuild. O destino é
 * gerado e não versionado.
 */
const ASSETS = [
  { from: 'models/vizi-seg.mlpackage', to: 'vizi-seg.mlpackage', dir: true },
  { from: 'assets/reference.jpg', to: 'reference.jpg', dir: false },
];

module.exports = function withViziAssets(config) {
  return withDangerousMod(config, [
    'ios',
    (cfg) => {
      const root = cfg.modRequest.projectRoot;
      const dest = path.join(root, 'modules', 'vizi-vision', 'ios', 'Resources');

      fs.rmSync(dest, { recursive: true, force: true });
      fs.mkdirSync(dest, { recursive: true });

      for (const asset of ASSETS) {
        const src = path.join(root, asset.from);
        if (!fs.existsSync(src)) {
          throw new Error(
            `[withViziAssets] ${asset.from} não existe. O build produziria um app sem modelo, ` +
              `e a falha só apareceria ao tocar em "Carregar modelo" no aparelho.`,
          );
        }
        fs.cpSync(src, path.join(dest, asset.to), { recursive: asset.dir });
      }

      return cfg;
    },
  ]);
};
