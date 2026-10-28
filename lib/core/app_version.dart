/// The app's version, stamped into every export so a future import knows which
/// app wrote the file.
///
/// Must match `version:` in pubspec.yaml (without the build number); a test
/// fails if the two drift apart, so bumping the release also means bumping
/// this.
const appVersion = '0.7.0';
