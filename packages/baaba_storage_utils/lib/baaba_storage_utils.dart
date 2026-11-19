// The platform option types are re-exported because BaabaStorage.init and
// SecureStorage.configure take them, so a consumer customising secure storage
// should not need flutter_secure_storage in its own pubspec.
export 'package:flutter_secure_storage/flutter_secure_storage.dart'
    show
        AndroidOptions,
        IOSOptions,
        KeychainAccessibility,
        LinuxOptions,
        MacOsOptions,
        WebOptions,
        WindowsOptions;

export 'src/baaba_storage.dart';
