# Meeting Transcriber

A meeting transcription and summarization system. This repository contains two implementations:

1. **Python/Flask Web App** (original) — browser-based recording and transcription via OpenAI Whisper API
2. **iOS App** (new, in `MeetingTranscriber/`) — native Swift/SwiftUI app with on-device transcription, real-time speaker diarization, and AI summarization

---

## iOS App (`MeetingTranscriber/`)

The native iOS version replaces the browser + server architecture with a standalone app that runs entirely on-device (except for optional AI summarization).

**Key differences from the Python version:**
- No server required — recording, transcription, and speaker detection all run on the iPhone
- Real-time streaming transcription via Apple's Speech framework (on-device, offline-capable)
- Speaker diarization (not present in the Python version) — detects and labels different speakers
- Same 3 summary types (Key Points, Executive, Detailed) via OpenAI-compatible API called directly from the device

**Getting started:**
1. Open `MeetingTranscriber/MeetingTranscriber.xcodeproj` in Xcode
2. Set your development team in Signing & Capabilities
3. Build to a physical iOS device (microphone + speech require real hardware)
4. Add your OpenAI API key in the Settings tab for summarization

For full architecture details, see [`MeetingTranscriber/ARCHITECTURE.md`](MeetingTranscriber/ARCHITECTURE.md).

---

## Python Web App (Original)

A web-based application that transcribes meeting audio using OpenAI's Whisper API. Built with Flask and designed for easy deployment and use. This is the original implementation that the iOS app was derived from.

### Features

- **Audio Transcription**: Upload audio files or record directly in the browser
- **Long Audio Support**: Automatic chunking for files over 10MB (supports 1+ hour recordings)
- **AI-Powered Summaries**: Generate key points, executive summaries, and detailed summaries via GPT
- **OpenAI Integration**: Whisper for transcription, GPT-3.5-turbo for summaries
- **Web Interface**: Clean, user-friendly browser UI
- **Secure**: Environment-based configuration for API keys with login authentication
- **Cross-platform**: Works on Windows, macOS, and Linux

### Prerequisites

- Python 3.7 or higher
- OpenAI API key
- Microphone access (for live recording)

### Quick Setup

**On macOS/Linux:**
```bash
chmod +x setup.sh
./setup.sh
```

**On Windows:**
```bash
setup.bat
```

### Manual Setup

1. **Create a virtual environment**
   ```bash
   python -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   ```

2. **Install dependencies**
   ```bash
   pip install -r requirements.txt
   ```

3. **Set up environment variables**
   ```bash
   cp env_example.txt .env
   ```

   Edit `.env` and add your credentials:
   ```
   OPENAI_API_KEY=your_actual_openai_api_key_here
   ADMIN_USERNAME=your_username_here
   ADMIN_PASSWORD=your_secure_password_here
   ```

### Usage

1. **Start the application**
   ```bash
   python3 app.py
   ```

2. **Open your browser** at `http://localhost:5002`

3. **Use the application**
   - Upload an audio file (supports files up to 500MB)
   - Record audio directly in the browser
   - Get transcribed text results
   - Generate AI-powered summaries (Key Points, Executive, or Detailed)

### Configuration

The application uses environment variables. Copy `env_example.txt` to `.env` and modify as needed:

- `OPENAI_API_KEY`: Your OpenAI API key (required)
- `ADMIN_USERNAME`: Your login username (required)
- `ADMIN_PASSWORD`: Your login password (required)
- `FLASK_ENV`: Set to 'development' for debug mode
- `FLASK_DEBUG`: Enable/disable debug mode

**Security Note**: No default credentials are provided. You must set your own username and password in the `.env` file.

---

## Project Structure

```
Meeting_Transcriber/
├── app.py                      # Python: Main Flask application
├── process_recording.py        # Python: Standalone script for interrupted recordings
├── requirements.txt            # Python: Dependencies
├── env_example.txt             # Python: Environment variables template
├── setup.sh / setup.bat        # Python: Setup scripts
├── templates/                  # Python: HTML templates
│   ├── index.html
│   └── login.html
├── uploads/                    # Python: Temporary audio storage (runtime)
├── transcripts/                # Python: Transcript output (runtime)
│
└── MeetingTranscriber/         # iOS: Native Swift/SwiftUI app
    ├── ARCHITECTURE.md         # iOS: Full architecture & tradeoff analysis
    ├── MeetingTranscriber.xcodeproj/
    └── MeetingTranscriber/
        ├── App/                # Entry point
        ├── Models/             # Data models
        ├── Services/           # Audio, Speech, Diarization, Summarization, Storage
        ├── ViewModels/         # MVVM view models
        └── Views/              # SwiftUI views
```

---

## Version History

### v3.0.1 (March 2026) - iOS App Verified & Tuned
- **Build verified** — compiles clean on Xcode 26.2, zero errors/warnings
- **Tested on device** — live transcription confirmed working on physical iPhone
- **Speaker diarization tuned** — fixed false speaker splits (single speaker was being labeled as 3-4):
  - Raised similarity threshold (0.82 → 0.92)
  - Increased minimum gap between speaker changes (300ms → 2s)
  - Added confirmation debouncing (8 consecutive frames must agree before switching)
- **Asset catalog added** — AppIcon and AccentColor placeholders for App Store readiness
- **Summarization** — not yet tested (requires OpenAI API key in Settings tab)

### v3.0 (March 2026) - Native iOS App
- **Native iOS app** built with Swift + SwiftUI (MVVM architecture)
- **On-device transcription** via Apple Speech framework (no server, no Whisper API needed)
- **Speaker diarization** using spectral feature clustering (new capability not in Python version)
- **Real-time live transcription** display with speaker-change highlighting
- **Standalone operation** — no backend server required
- **Same summarization** workflow (Key Points, Executive, Detailed) via configurable OpenAI-compatible API

### v2.2 (August 21, 2025) - Transcript Management & Performance Optimization
- Dedicated `transcripts/` directory for organized file management
- Reduced chunking threshold from 25MB to 10MB for faster processing
- 3-minute chunks for improved processing speed
- Added `/transcripts` API endpoints
- Added `process_recording.py` for processing interrupted recordings

### v2.1 (August 2025) - Enhanced Processing
- Better progress messaging with time estimates
- Improved error handling and file validation
- Faster chunking and transcription pipeline

### v2.0 (August 2025) - Long Audio Support & AI Summaries
- Long audio support (1+ hours) via automatic chunking
- Three AI summary types using GPT-3.5-turbo
- Application moved to port 5002

---

## API Key

Both the Python and iOS apps require an OpenAI API key for summarization:

1. Visit [OpenAI Platform](https://platform.openai.com/api-keys)
2. Create an account or sign in
3. Generate a new API key
4. **Python**: Add to `.env` file
5. **iOS**: Enter in the app's Settings tab

## License

This project is licensed under the MIT License - see the LICENSE file for details. 