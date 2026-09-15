import { registerWebModule, NativeModule } from 'expo';

// ViziVisionModule is not available on the web platform.
class ViziVisionModule extends NativeModule<{}> {}

export default registerWebModule(ViziVisionModule, 'ViziVisionModule');
