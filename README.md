# LumiMate

<p align="center">
  <img src="LumiMate-Logo.png" alt="LumiMate Logo" width="200" />
</p>

## Overview

LumiMate is a Flutter application designed to assist visually impaired users by providing real-time scene descriptions and facial recognition. Using the device camera and advanced AI technologies, LumiMate helps users understand their surroundings through audio feedback and voice interaction.

## Features

### Core Features

- **Scene Description:** Captures images and provides detailed audio descriptions of surroundings
- **Facial Recognition:** Identifies people in the camera view and announces their names when recognized
- **Face Registration:** Registers new faces with associated names via voice command
- **Voice Control:** Complete hands-free operation through voice commands
- **WebRTC Integration:** Real-time communication for enhanced assistance
- **Accessible UI:** Designed with visual impairment in mind, featuring high contrast and voice guidance

### Technical Features

- Flutter-based cross-platform compatibility (iOS and Android)
- Camera integration with image processing
- Speech-to-text and text-to-speech capabilities
- RESTful API integration for AI processing
- WebSocket/Socket.IO for real-time updates
- WebRTC for audio/video streaming

## Installation

### Prerequisites

- Flutter SDK (version 3.7.2 or higher)
- Dart SDK (matching Flutter SDK requirements)
- Android Studio or Xcode (for platform-specific development)
- An iOS or Android device for testing (camera access required)

### Setup Instructions

1. Clone the repository:
   ```
   git clone https://github.com/yourusername/lumi_mate_flutter.git
   ```

2. Navigate to the project directory:
   ```
   cd lumi_mate_flutter
   ```

3. Install dependencies:
   ```
   flutter pub get
   ```

4. Run the application:
   ```
   flutter run
   ```

## Project Structure

```
lumi_mate_flutter/
├── android/                  # Android platform code
├── ios/                      # iOS platform code
├── lib/
│   ├── config/               # Configuration files and constants
│   ├── screens/              # UI screens
│   │   ├── take_picture_screen.dart  # Main camera interface
│   │   └── ...
│   ├── services/             # Business logic and services
│   │   ├── webrtc_client.dart        # WebRTC implementation
│   │   ├── minicpm_service.dart      # AI service integration
│   │   └── ...
│   └── main.dart             # Application entry point
├── test/                     # Test files
├── scene_description_client.py  # Python client for scene description
└── pubspec.yaml              # Project dependencies
```

## Usage

### Voice Commands

LumiMate responds to the following voice commands:

- "Hey Lumi" - Wake word to activate voice recognition
- "Describe scene" - Takes a picture and describes what's in view
- "Register face" - Begins the face registration process
- "Who is this?" - Attempts to identify the person in view

### Accessibility Features

- TalkBack/VoiceOver compatible
- Audio feedback for all interactions
- High contrast UI elements
- Large touch targets

## Development

### Building for Production

```
flutter build apk      # For Android
flutter build ios      # For iOS (requires Xcode on macOS)
```

### Running Tests

```
flutter test
```

## API Integration

LumiMate connects to backend services for:

1. Scene description processing
2. Facial recognition
3. Audio processing

Refer to the service files in `lib/services/` for implementation details.

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Acknowledgements

- Flutter team for the amazing framework
- All contributors to the project
- AI services that power the scene description and facial recognition features

---

© 2025 LumiMate. Empowering visually impaired users through technology.