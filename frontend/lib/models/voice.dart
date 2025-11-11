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

  factory Voice.fromJson(Map<String, dynamic> json) => Voice(
        id: json['id'].toString(),
        provider: json['provider'] ?? 'azure',
        voiceCode: json['voice_code'] ?? 'es-MX-DaliaNeural',
        lang: json['lang'] ?? 'es-MX',
        settings: json['settings_json'] as Map<String, dynamic>?,
      );
}
