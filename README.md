# lumi_mate_flutter

Lumi Mate is a Flutter application designed to assist visually impaired users by providing real-time scene descriptions and facial recognition/registration features.

## Features

- **Scene Description:** Uses the device camera to capture images and sends them to an API for scene analysis. The app then reads out a description of the scene to the user.
- **Facial Recognition:** Identifies people in front of the camera and announces their names if recognized.
- **Face Registration:** Allows users to register new faces by voice command, associating a name with a captured image.
- **Voice Interaction:** Users can control the app entirely through voice commands, including wake word detection (e.g., "Hey Lumi") and natural language commands.
- **Accessible UI:** Designed with accessibility in mind, providing audio feedback and minimal visual clutter.

## Getting Started

This project is a starting point for a Flutter application. To run the app:

1. Ensure you have Flutter installed. See the [Flutter documentation](https://docs.flutter.dev/) for setup instructions.
2. Run `flutter pub get` to install dependencies.
3. Connect a device or start an emulator.
4. Run `flutter run` to launch the app.

## Project Structure

- `lib/screens/` – UI screens, including the main camera and interaction screen.
- `lib/services/` – Core logic for camera, voice, scene description, API communication, and speech.
- `test/` – Unit and widget tests.

## Resources

- [Flutter documentation](https://docs.flutter.dev/)

---

This app is intended to empower visually impaired users by making their environment more accessible through audio feedback and intelligent scene understanding.
