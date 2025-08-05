# Meeting Transcriber

A web-based application that transcribes meeting audio using OpenAI's speech recognition API. Built with Flask and designed for easy deployment and use.

## Features

- **Real-time Audio Transcription**: Upload audio files or record directly in the browser
- **OpenAI Integration**: Leverages OpenAI's advanced speech recognition capabilities
- **Web Interface**: Clean, user-friendly web interface for easy interaction
- **Secure**: Environment-based configuration for API keys and sensitive data
- **Cross-platform**: Works on Windows, macOS, and Linux

## Prerequisites

- Python 3.7 or higher
- OpenAI API key
- Microphone access (for live recording)

## Installation

### Quick Setup (Recommended)

**On macOS/Linux:**
```bash
git clone <your-repository-url>
cd Meeting_Transcriber
chmod +x setup.sh
./setup.sh
```

**On Windows:**
```bash
git clone <your-repository-url>
cd Meeting_Transcriber
setup.bat
```

### Manual Setup

1. **Clone the repository**
   ```bash
   git clone <your-repository-url>
   cd Meeting_Transcriber
   ```

2. **Create a virtual environment**
   ```bash
   python -m venv venv
   source venv/bin/activate  # On Windows: venv\Scripts\activate
   ```

3. **Install dependencies**
   ```bash
   pip install -r requirements.txt
   ```

4. **Set up environment variables**
   ```bash
   cp env_example.txt .env
   ```
   
   Edit `.env` file and add your OpenAI API key:
   ```
   OPENAI_API_KEY=your_actual_openai_api_key_here
   ```

## Usage

1. **Start the application**
   ```bash
   python app.py
   ```

2. **Open your browser**
   Navigate to `http://localhost:5000`

3. **Use the application**
   - Upload an audio file, or
   - Record audio directly in the browser
   - Get transcribed text results

## Configuration

The application uses environment variables for configuration. Copy `env_example.txt` to `.env` and modify as needed:

- `OPENAI_API_KEY`: Your OpenAI API key (required)
- `FLASK_ENV`: Set to 'development' for debug mode
- `FLASK_DEBUG`: Enable/disable debug mode

## Dependencies

- **Flask**: Web framework
- **SpeechRecognition**: Audio processing
- **PyAudio**: Audio input/output
- **OpenAI**: API integration for transcription
- **python-dotenv**: Environment variable management
- **pydub**: Audio file manipulation
- **numpy**: Numerical operations

## Project Structure

```
Meeting_Transcriber/
├── app.py              # Main Flask application
├── requirements.txt     # Python dependencies
├── env_example.txt     # Environment variables template
├── .env                # Environment variables (create from template)
├── static/             # Static assets (CSS, JS, images)
└── templates/          # HTML templates
    ├── index.html      # Main application page
    └── login.html      # Login page
```

## API Usage

This application requires an OpenAI API key. You can get one by:

1. Visiting [OpenAI Platform](https://platform.openai.com/api-keys)
2. Creating an account or signing in
3. Generating a new API key
4. Adding it to your `.env` file

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

If you encounter any issues or have questions, please open an issue on the GitHub repository.

## Acknowledgments

- OpenAI for providing the speech recognition API
- Flask community for the excellent web framework
- All contributors to the open-source dependencies used in this project 