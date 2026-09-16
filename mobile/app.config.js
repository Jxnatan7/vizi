// Fonte da verdade da configuração nativa.
//
// As pastas ios/ e android/ NÃO são versionadas: `expo prebuild` as regenera
// a partir deste arquivo. Sem Mac, editar um projeto Xcode à mão não é opção,
// então toda configuração nativa precisa ser expressável aqui.
// Ver .specify/memory/constitution.md § Restrições técnicas.

export default {
  expo: {
    name: 'vizi',
    slug: 'vizi',
    version: '1.0.0',
    orientation: 'portrait',
    icon: './assets/icon.png',
    userInterfaceStyle: 'automatic',
    newArchEnabled: true,

    ios: {
      // Assinado com Apple ID gratuito. Contas gratuitas permitem 10 App IDs
      // por 7 dias — trocar este valor queima cota.
      bundleIdentifier: 'com.jxnatan7.vizi',
      supportsTablet: false,

      infoPlist: {
        // Sem esta chave o iOS encerra o app na primeira tentativa de acesso à
        // câmera — sem diálogo, sem erro, só o app fechando.
        NSCameraUsageDescription:
          'O vizi usa a câmera para detectar e contar objetos em tempo real, no próprio aparelho.',
      },
    },

    android: {
      package: 'com.jxnatan7.vizi',
      adaptiveIcon: {
        backgroundColor: '#E6F4FE',
        foregroundImage: './assets/android-icon-foreground.png',
        backgroundImage: './assets/android-icon-background.png',
        monochromeImage: './assets/android-icon-monochrome.png',
      },
    },

    plugins: ['expo-dev-client', './plugins/withViziAssets'],
  },
};
