import os
import tempfile
import uuid
from datetime import datetime
from flask import Flask, render_template, request, jsonify, send_file, redirect, url_for, flash, session
from werkzeug.utils import secure_filename
from pydub import AudioSegment
import openai
from dotenv import load_dotenv
import speech_recognition as sr
import io
import base64
from functools import wraps

# Load environment variables
load_dotenv()

app = Flask(__name__)
app.config['SECRET_KEY'] = os.urandom(24)
app.config['MAX_CONTENT_LENGTH'] = 100 * 1024 * 1024  # 100MB max file size

# Configure OpenAI
openai.api_key = os.getenv('OPENAI_API_KEY')

# Configure upload settings
UPLOAD_FOLDER = 'uploads'
ALLOWED_EXTENSIONS = {'wav', 'mp3', 'm4a', 'flac', 'ogg', 'webm'}

if not os.path.exists(UPLOAD_FOLDER):
    os.makedirs(UPLOAD_FOLDER)

# Simple user credentials (in production, use a database and hashed passwords)
USERS = {
    os.getenv('ADMIN_USERNAME', 'admin'): os.getenv('ADMIN_PASSWORD', 'password123')
}

def login_required(f):
    @wraps(f)
    def decorated_function(*args, **kwargs):
        if 'logged_in' not in session:
            return redirect(url_for('login'))
        return f(*args, **kwargs)
    return decorated_function

def allowed_file(filename):
    return '.' in filename and filename.rsplit('.', 1)[1].lower() in ALLOWED_EXTENSIONS

def convert_audio_to_wav(audio_file_path):
    """Convert audio file to WAV format for better compatibility"""
    try:
        audio = AudioSegment.from_file(audio_file_path)
        wav_path = audio_file_path.rsplit('.', 1)[0] + '.wav'
        audio.export(wav_path, format='wav')
        return wav_path
    except Exception as e:
        print(f"Error converting audio: {e}")
        return audio_file_path

def transcribe_with_openai(audio_file_path):
    """Transcribe audio using OpenAI Whisper API"""
    try:
        # Convert to WAV if needed
        wav_path = convert_audio_to_wav(audio_file_path)
        
        with open(wav_path, 'rb') as audio_file:
            transcript = openai.Audio.transcribe(
                model="whisper-1",
                file=audio_file,
                response_format="verbose_json",
                timestamp_granularities=["word"]
            )
        
        return transcript
    except Exception as e:
        print(f"Error transcribing with OpenAI: {e}")
        return None

def transcribe_with_google(audio_file_path):
    """Fallback transcription using Google Speech Recognition"""
    try:
        recognizer = sr.Recognizer()
        with sr.AudioFile(audio_file_path) as source:
            audio = recognizer.record(source)
            text = recognizer.recognize_google(audio)
            return {"text": text, "method": "google"}
    except Exception as e:
        print(f"Error transcribing with Google: {e}")
        return None

@app.route('/')
@login_required
def index():
    return render_template('index.html')

@app.route('/login', methods=['GET', 'POST'])
def login():
    if request.method == 'POST':
        username = request.form['username']
        password = request.form['password']
        
        if username in USERS and USERS[username] == password:
            session['logged_in'] = True
            session['username'] = username
            flash('Login successful!', 'success')
            return redirect(url_for('index'))
        else:
            flash('Invalid username or password', 'error')
    
    return render_template('login.html')

@app.route('/logout')
def logout():
    session.clear()
    flash('You have been logged out', 'info')
    return redirect(url_for('login'))

@app.route('/upload', methods=['POST'])
@login_required
def upload_file():
    """Handle file upload and transcription"""
    if 'audio_file' not in request.files:
        return jsonify({'error': 'No file uploaded'}), 400
    
    file = request.files['audio_file']
    if file.filename == '':
        return jsonify({'error': 'No file selected'}), 400
    
    if not allowed_file(file.filename):
        return jsonify({'error': 'Invalid file type'}), 400
    
    try:
        # Save uploaded file
        filename = secure_filename(file.filename)
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        unique_filename = f"{timestamp}_{uuid.uuid4().hex}_{filename}"
        file_path = os.path.join(UPLOAD_FOLDER, unique_filename)
        file.save(file_path)
        
        # Transcribe with OpenAI
        transcript = transcribe_with_openai(file_path)
        
        if transcript:
            # Clean up temporary file
            os.remove(file_path)
            if file_path.endswith('.wav') and file_path != audio_file_path:
                os.remove(wav_path)
            
            return jsonify({
                'success': True,
                'transcript': transcript['text'],
                'duration': transcript.get('duration'),
                'method': 'openai'
            })
        else:
            # Try Google as fallback
            transcript = transcribe_with_google(file_path)
            if transcript:
                os.remove(file_path)
                return jsonify({
                    'success': True,
                    'transcript': transcript['text'],
                    'method': 'google'
                })
            else:
                return jsonify({'error': 'Transcription failed'}), 500
                
    except Exception as e:
        return jsonify({'error': f'Processing error: {str(e)}'}), 500

@app.route('/record', methods=['POST'])
@login_required
def record_audio():
    """Handle recorded audio from browser"""
    try:
        # Get base64 audio data
        audio_data = request.json.get('audio_data')
        if not audio_data:
            return jsonify({'error': 'No audio data received'}), 400
        
        # Decode base64 audio
        audio_bytes = base64.b64decode(audio_data.split(',')[1])
        
        # Save temporary file
        timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
        unique_filename = f"recorded_{timestamp}_{uuid.uuid4().hex}.wav"
        file_path = os.path.join(UPLOAD_FOLDER, unique_filename)
        
        with open(file_path, 'wb') as f:
            f.write(audio_bytes)
        
        # Transcribe
        transcript = transcribe_with_openai(file_path)
        
        if transcript:
            # Clean up
            os.remove(file_path)
            return jsonify({
                'success': True,
                'transcript': transcript['text'],
                'duration': transcript.get('duration'),
                'method': 'openai'
            })
        else:
            return jsonify({'error': 'Transcription failed'}), 500
            
    except Exception as e:
        return jsonify({'error': f'Processing error: {str(e)}'}), 500

@app.route('/health')
def health_check():
    """Health check endpoint"""
    return jsonify({
        'status': 'healthy',
        'openai_configured': bool(os.getenv('OPENAI_API_KEY')),
        'timestamp': datetime.now().isoformat()
    })

if __name__ == '__main__':
    # Check if OpenAI API key is configured
    if not os.getenv('OPENAI_API_KEY'):
        print("Warning: OPENAI_API_KEY not found in environment variables.")
        print("Please set your OpenAI API key in the .env file.")
    
    # Check if admin credentials are configured
    if not os.getenv('ADMIN_USERNAME') or not os.getenv('ADMIN_PASSWORD'):
        print("Warning: ADMIN_USERNAME or ADMIN_PASSWORD not found in environment variables.")
        print("Using default credentials: admin/password123")
        print("Please set ADMIN_USERNAME and ADMIN_PASSWORD in the .env file for security.")
    
    app.run(debug=True, host='0.0.0.0', port=5000)
