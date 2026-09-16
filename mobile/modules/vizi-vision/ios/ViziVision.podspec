Pod::Spec.new do |s|
  s.name           = 'ViziVision'
  s.version        = '1.0.0'
  s.summary        = 'Inferencia Core ML no dispositivo'
  s.description    = 'Carrega o modelo de segmentacao e mede a inferencia no aparelho.'
  s.author         = ''
  s.homepage       = 'https://docs.expo.dev/modules/'
  s.platforms      = { :ios => '16.4', :tvos => '16.4' }
  s.source         = { git: '' }
  s.static_framework = true

  s.dependency 'ExpoModulesCore'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }

  s.source_files = "**/*.{h,m,mm,swift,hpp,cpp}"

  # Modelo e imagem de referencia sao copiados para ./Resources/ pelo config
  # plugin withViziAssets, que roda antes do pod install.
  #
  # Caminhos EXPLICITOS, nao glob: 'Resources/**/*' entraria dentro do
  # .mlpackage e achataria a estrutura de pastas que o Core ML exige.
  #
  # Tentativa anterior com '../../../models/...' produziu um bundle vazio: o
  # CocoaPods nao resolve caminhos fora da raiz do pod, e nao avisa.
  s.resource_bundles = {
    'ViziVisionAssets' => [
      'Resources/vizi-seg.mlpackage',
      'Resources/reference.jpg'
    ]
  }
end
