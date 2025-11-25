class Voice {
  final String id; // provider+code or UUID del backend
  final String provider; // azure|gcp|polly|coqui
  final String voiceCode; // p.ej. es-MX-LibertoNeural
  final String lang; // es-MX, es-CO, es-ES
  final Map<String, dynamic>? settings; // rate, pitch, style

  Voice({
    required this.id,
    required this.provider,
    required this.voiceCode,
    required this.lang,
    this.settings,
  });

  /// Genera un nombre amigable desde el código de voz
  String get name {
    // Para voces simples de Google TTS (es-Normal, es-Clara)
    if (voiceCode.contains('-')) {
      final parts = voiceCode.split('-');
      if (parts.length == 2) {
        // Ej: "es-Normal" -> "Normal", "es-Clara" -> "Clara"
        return parts.last;
      }
      
      // Para códigos largos (ej: "es-MX-DaliaNeural" -> "Dalia")
      if (parts.length >= 3) {
        // Remover sufijos como "Neural", "Standard", "Wavenet"
        String namePart = parts.last
            .replaceAll('Neural', '')
            .replaceAll('Standard', '')
            .replaceAll('Wavenet', '')
            .replaceAll('Female', '')
            .replaceAll('Male', '')
            .replaceAll(RegExp(r'[0-9]'), '')
            .trim();
        
        if (namePart.isEmpty) {
          // Si no queda nada, usar el país y género
          final country = parts.length > 1 ? parts[1] : 'ES';
          final isFemale = voiceCode.toLowerCase().contains('female');
          return '$country ${isFemale ? 'Mujer' : 'Hombre'}';
        }
        return namePart;
      }
    }
    return voiceCode; // Fallback
  }

  factory Voice.fromJson(Map<String, dynamic> json) => Voice(
        id: json['id'].toString(),
        provider: json['provider'] ?? 'azure',
        voiceCode: json['voice_code'] ?? 'es-MX-DaliaNeural',
        lang: json['lang'] ?? 'es-MX',
        settings: json['settings_json'] as Map<String, dynamic>?,
      );
}
