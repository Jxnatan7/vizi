import ExpoModulesCore

/// Superfície nativa do módulo.
///
/// Marco 1: apenas `probe()`, que existe para provar que código Swift próprio
/// foi compilado, assinado e instalado — a validação da US1. Carga do modelo e
/// medição entram na US2 (T020–T025).
public class ViziVisionModule: Module {
  public func definition() -> ModuleDefinition {
    Name("ViziVision")

    Function("probe") { () -> [String: Any] in
      let info = ProcessInfo.processInfo
      return [
        "module": "ViziVision",
        "os": info.operatingSystemVersionString,
        "processorCount": info.processorCount,
        "physicalMemoryMB": Int(info.physicalMemory / 1_048_576),
        "lowPowerMode": info.isLowPowerModeEnabled,
      ]
    }
  }
}
