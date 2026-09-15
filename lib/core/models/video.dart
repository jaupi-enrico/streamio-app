/// Mirrors core/models/Video.ts's `Subtitle` interface.
class Subtitle {
  const Subtitle({
    required this.label,
    required this.file,
    this.isDefault = false,
    this.initialDefault = false,
  });

  final String label;
  final String file;
  final bool isDefault;
  final bool initialDefault;

  Subtitle copyWith({
    String? label,
    String? file,
    bool? isDefault,
    bool? initialDefault,
  }) {
    return Subtitle(
      label: label ?? this.label,
      file: file ?? this.file,
      isDefault: isDefault ?? this.isDefault,
      initialDefault: initialDefault ?? this.initialDefault,
    );
  }
}
