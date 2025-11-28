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
    // Para voces de Google Cloud TTS (ej: "es-US-Neural2-A" -> "ES-US Neural2-A")
    if (provider == 'gcp' && voiceCode.contains('-')) {
      // Formato: idioma-país-tipo-letra (ej: es-US-Neural2-A)
      final parts = voiceCode.split('-');
      if (parts.length >= 3) {
        final country = parts.take(2).join('-'); // es-US
        final rest = parts.skip(2).join('-'); // Neural2-A, Wavenet-B, Studio-C
        return '$country $rest';
      }
    }
    
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
  
  /// Obtiene el tipo de voz (Neural2, Wavenet, Studio, etc.)
  String get voiceType {
    if (voiceCode.contains('Neural2')) return 'Neural2';
    if (voiceCode.contains('Wavenet')) return 'Wavenet';
    if (voiceCode.contains('Studio')) return 'Studio';
    if (voiceCode.contains('Journey')) return 'Journey';
    if (voiceCode.contains('Chirp')) return 'Chirp';
    if (voiceCode.contains('Standard')) return 'Standard';
    return 'Otro';
  }
  
  /// Obtiene el género de la voz basado en settings o inferencia del código
  String get gender {
    // Primero intentar desde settings
    if (settings != null && settings!.containsKey('gender')) {
      final g = settings!['gender'].toString().toUpperCase();
      if (g == 'FEMALE') return 'Mujer';
      if (g == 'MALE') return 'Hombre';
      return 'Neutral';
    }
    
    // Inferir desde voice code
    final code = voiceCode.toLowerCase();
    if (code.contains('female')) return 'Mujer';
    if (code.contains('male')) return 'Hombre';
    
    // Por la letra final en voces Google (A, B, C, D = patrón común)
    // A, C, E, G, H suelen ser femeninas; B, D, F suelen ser masculinas
    if (provider == 'gcp') {
      final lastChar = voiceCode.split('-').last.toUpperCase();
      if (RegExp(r'[ACEGH]').hasMatch(lastChar)) return 'Mujer';
      if (RegExp(r'[BDF]').hasMatch(lastChar)) return 'Hombre';
    }
    
    return 'Neutral';
  }
  
  /// Obtiene una descripción detallada de las características de la voz
  String get description {
    final type = voiceType;
    final genderLower = gender.toLowerCase();
    
    // Descripciones específicas por tipo de voz
    switch (type) {
      case 'Neural2':
        if (genderLower == 'mujer') {
          return 'Voz femenina ultra-realista con tonos cálidos y naturales. Ideal para narrativas largas y contenido educativo.';
        } else if (genderLower == 'hombre') {
          return 'Voz masculina profunda y clara con excelente dicción. Perfecta para audiolibros y podcasts profesionales.';
        }
        return 'Calidad premium con la última tecnología de síntesis neural. Suena completamente humana.';
      
      case 'Studio':
        if (genderLower == 'mujer') {
          return 'Optimizada para largos períodos de escucha. Voz suave y consistente que reduce la fatiga auditiva.';
        } else if (genderLower == 'hombre') {
          return 'Tonos balanceados ideales para sesiones extendidas. Claridad excepcional en cualquier volumen.';
        }
        return 'Diseñada especialmente para contenido extenso como novelas y documentales.';
      
      case 'Wavenet':
        if (genderLower == 'mujer') {
          return 'Voz expresiva con matices emocionales. Excelente para diálogos y narrativa dramática.';
        } else if (genderLower == 'hombre') {
          return 'Tonalidad rica y versátil. Transmite autoridad y confianza en cada palabra.';
        }
        return 'Tecnología Wavenet de alta fidelidad. Calidad superior con entonación natural.';
      
      case 'Journey':
        return 'Estilo conversacional y cercano. Perfecta para contenido informal y storytelling personal.';
      
      case 'Chirp':
        if (genderLower == 'mujer') {
          return 'Altamente expresiva con rango emocional amplio. Ideal para contenido infantil y narrativas dinámicas.';
        } else if (genderLower == 'hombre') {
          return 'Voz energética y versátil. Excelente para contenido motivacional y educativo interactivo.';
        }
        return 'Tecnología avanzada con expresividad emocional mejorada.';
      
      case 'Standard':
        return 'Voz clara y confiable. Buena opción para pruebas y contenido general.';
      
      default:
        return 'Voz de síntesis de texto a voz con calidad profesional.';
    }
  }

  factory Voice.fromJson(Map<String, dynamic> json) => Voice(
        id: json['id'].toString(),
        provider: json['provider'] ?? 'azure',
        voiceCode: json['voice_code'] ?? 'es-MX-DaliaNeural',
        lang: json['lang'] ?? 'es-MX',
        settings: json['settings_json'] as Map<String, dynamic>?,
      );
}
