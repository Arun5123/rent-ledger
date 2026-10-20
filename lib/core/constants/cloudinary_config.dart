/// Credentials for the receipt, photo and ID-proof uploads.
///
/// Firebase Cloud Storage requires the Blaze pricing plan, so binary assets go
/// straight to Cloudinary instead, using an *unsigned* upload preset. Unsigned
/// uploads need no API secret, which is what makes them safe to ship inside a
/// client build.
///
/// The defaults below are this project's own Cloudinary environment. Either
/// value can still be overridden at build time:
///
/// ```sh
/// flutter run \
///   --dart-define=CLOUDINARY_CLOUD_NAME=other-cloud \
///   --dart-define=CLOUDINARY_UPLOAD_PRESET=other_preset
/// ```
abstract final class CloudinaryConfig {
  /// Not a secret: the cloud name is visible in every delivery URL.
  static const String cloudName = String.fromEnvironment(
    'CLOUDINARY_CLOUD_NAME',
    defaultValue: 'sqfv2g1n',
  );

  /// Must exist in the Cloudinary console with **Signing Mode: Unsigned**.
  static const String uploadPreset = String.fromEnvironment(
    'CLOUDINARY_UPLOAD_PRESET',
    defaultValue: 'rentledger_unsigned',
  );

  /// API Key for signed operations like permanent asset deletion.
  static const String apiKey = String.fromEnvironment(
    'CLOUDINARY_API_KEY',
    defaultValue: '131132525172676',
  );

  /// API Secret for signed operations like permanent asset deletion.
  static const String apiSecret = String.fromEnvironment(
    'CLOUDINARY_API_SECRET',
    defaultValue: '8b0mOdf-1ogFGiMRXfVCIJIDb38',
  );

  static bool get isConfigured =>
      cloudName.isNotEmpty && uploadPreset.isNotEmpty;

  static bool get hasApiCredentials =>
      cloudName.isNotEmpty && apiKey.isNotEmpty && apiSecret.isNotEmpty;
}
