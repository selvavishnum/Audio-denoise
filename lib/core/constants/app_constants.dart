class AppConstants {
  // App info
  static const String appName = 'ClearWave Studio';
  static const String appVersion = '1.0.0';
  static const String packageName = 'com.selvavishnu.clearwave';

  // Free tier
  static const int maxFreeDenoises = 100;

  // Promo codes (influencer codes for unlimited access)
  static const List<String> validPromoCodes = [
    'CLEARWAVE2024',
    'STUDIO_PRO',
    'INFLUENCER_VIP',
    'INSTA_UNLIMITED',
    'CREATOR_FREE',
    'AUDIOPROMAX',
    'STUDIOMODE',
  ];

  // Audio settings
  static const int defaultSampleRate = 44100;
  static const int defaultBitRate = 320000;
  static const String recordingExtension = 'm4a';
  static const String outputExtension = 'wav';

  // SharedPreferences keys
  static const String keyDenoiseCount = 'denoise_count';
  static const String keyIsUnlimited = 'is_unlimited';
  static const String keyActivatedCode = 'activated_code';
  static const String keyOnboardingDone = 'onboarding_done';
  static const String keyProjects = 'audio_projects';

  // Hive box names
  static const String boxProjects = 'projects_box';

  // Denoise modes
  static const String modeAiQuick = 'ai_quick';
  static const String modeVoice = 'voice';
  static const String modeMusic = 'music';
  static const String modePodcast = 'podcast';
  static const String modeStudio = 'studio';

  // FFmpeg filter presets
  static const Map<String, String> ffmpegPresets = {
    modeAiQuick: 'afftdn=nf=-25:nr=20',
    modeVoice: 'afftdn=nf=-20:nr=30,highpass=f=80,lowpass=f=10000',
    modeMusic: 'anlmdn=s=7:p=0.002:r=0.002:m=15',
    modePodcast: 'afftdn=nf=-22:nr=25,highpass=f=100,equalizer=f=3000:t=q:w=1:g=2',
  };

  // Recording paths
  static const String recordingsDirName = 'recordings';
  static const String processedDirName = 'processed';
  static const String exportDirName = 'exports';
}
