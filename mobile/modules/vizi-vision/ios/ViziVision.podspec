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

  # Modelo e imagem de referencia entram no app por aqui, e nao por manipulacao
  # do projeto Xcode: a pasta ios/ e regenerada pelo prebuild a cada build, e
  # qualquer alteracao feita nela some.
  #
  # O Xcode pode compilar o .mlpackage para .mlmodelc durante o build, ou nao.
  # O lado Swift procura os dois (ver ModelAssets.swift).
  s.resource_bundles = {
    'ViziVisionAssets' => [
      '../../../models/vizi-seg.mlpackage',
      '../../../assets/reference.jpg'
    ]
  }
end
