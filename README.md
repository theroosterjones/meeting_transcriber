# Meeting Transcriber

A web-based application that transcribes meeting audio using OpenAI's speech recognition API. Built with Flask and designed for easy deployment and use.

## Features

- **Real-time Audio Transcription**: Upload audio files or record directly in the browser
- **Long Audio Support**: Automatic chunking for files over 25MB (supports 1+ hour recordings)
- **AI-Powered Summaries**: Generate key points, executive summaries, and detailed summaries
- **OpenAI Integration**: Leverages OpenAI's advanced speech recognition and GPT capabilities
- **Web Interface**: Clean, user-friendly web interface for easy interaction
- **Secure**: Environment-based configuration for API keys and sensitive data
- **Cross-platform**: Works on Windows, macOS, and Linux
- **File Size Handling**: Smart file size management with automatic chunking
- **Multiple Summary Types**: Key points, executive summary, and detailed analysis

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
   
   Edit `.env` file and add your credentials:
   ```
   OPENAI_API_KEY=your_actual_openai_api_key_here
   ADMIN_USERNAME=your_username_here
   ADMIN_PASSWORD=your_secure_password_here
   ```

## Usage

1. **Start the application**
   ```bash
   python3 app.py
   ```

2. **Open your browser**
   Navigate to `http://localhost:5002`

3. **Use the application**
   - Upload an audio file (supports files up to 500MB)
   - Record audio directly in the browser
   - Get transcribed text results
   - Generate AI-powered summaries (Key Points, Executive, or Detailed)

## Recent Updates (v2.0)

### Major Improvements:
- **Long Audio Support**: Now handles recordings over 1 hour by automatically splitting into manageable chunks
- **AI Summaries**: Added three types of AI-generated summaries using GPT-3.5-turbo
- **File Size Management**: Smart handling of large files with automatic chunking
- **Better Error Handling**: Improved error messages and file size validation
- **Enhanced UI**: Added summary generation buttons and improved user experience

### Technical Changes:
- **Automatic Chunking**: Files over 25MB are split into 10-minute chunks for processing
- **Summary API**: New `/summarize` endpoint for generating different types of summaries
- **GPT Integration**: Added GPT-3.5-turbo for summary generation
- **Port Change**: Application now runs on port 5002 instead of 5000
- **Python Command**: Updated to use `python3` instead of `python`

### Summary Types Available:
1. **Key Points**: Main topics, decisions, action items, and insights
2. **Executive Summary**: High-level overview with strategic decisions and business impact
3. **Detailed Summary**: Comprehensive coverage with timelines, assignees, and risks

## Configuration

The application uses environment variables for configuration. Copy `env_example.txt` to `.env` and modify as needed:

- `OPENAI_API_KEY`: Your OpenAI API key (required)
- `ADMIN_USERNAME`: Your login username (required)
- `ADMIN_PASSWORD`: Your login password (required)
- `FLASK_ENV`: Set to 'development' for debug mode
- `FLASK_DEBUG`: Enable/disable debug mode

**Security Note**: No default credentials are provided. You must set your own username and password in the `.env` file.

## Dependencies

- **Flask**: Web framework
- **SpeechRecognition**: Audio processing
- **PyAudio**: Audio input/output
- **OpenAI**: API integration for transcription and summarization
- **python-dotenv**: Environment variable management
- **pydub**: Audio file manipulation and chunking
- **numpy**: Numerical operations
- **Werkzeug**: WSGI utilities
- **requests**: HTTP library

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