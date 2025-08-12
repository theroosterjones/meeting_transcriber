import os
import tempfile
import uuid
from datetime import datetime
from flask import Flask, render_template, request, jsonify, send_file, redirect, url_for, flash, session
from werkzeug.utils import secure_filename
from pydub import AudioSegment
from openai import OpenAI
from dotenv import load_dotenv
try:
    import speech_recognition as sr
    SPEECH_RECOGNITION_AVAILABLE = True
except ImportError:
    SPEECH_RECOGNITION_AVAILABLE = False
    print("Warning: SpeechRecognition not available. Live recording will be disabled.")
import io
import base64
from functools import wraps

# Load environment variables
load_dotenv()

app = Flask(__name__)
app.config['SECRET_KEY'] = os.urandom(24)
app.config['MAX_CONTENT_LENGTH'] = 500 * 1024 * 1024  # 500MB max file size for long recordings

# Configure OpenAI
client = OpenAI(api_key=os.getenv('OPENAI_API_KEY'))

# Configure upload settings
UPLOAD_FOLDER = 'uploads'
ALLOWED_EXTENSIONS = {'wav', 'mp3', 'm4a', 'flac', 'ogg', 'webm', 'opus'}

if not os.path.exists(UPLOAD_FOLDER):
    os.makedirs(UPLOAD_FOLDER)

# Simple user credentials (in production, use a database and hashed passwords)
USERS = {
    os.getenv('ADMIN_USERNAME', 'admin'): os.getenv('ADMIN_PASSWORD', 'your_secure_password_here')
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

def split_audio_into_chunks(audio_file_path, chunk_duration_minutes=10):
    """Split audio file into smaller chunks for processing"""
    try:
        audio = AudioSegment.from_file(audio_file_path)
        chunk_duration_ms = chunk_duration_minutes * 60 * 1000  # Convert to milliseconds
        
        chunks = []
        for i in range(0, len(audio), chunk_duration_ms):
            chunk = audio[i:i + chunk_duration_ms]
            chunk_path = f"{audio_file_path.rsplit('.', 1)[0]}_chunk_{i//chunk_duration_ms}.wav"
            chunk.export(chunk_path, format='wav')
            chunks.append(chunk_path)
        
        return chunks
    except Exception as e:
        print(f"Error splitting audio: {e}")
        return [audio_file_path]

def transcribe_with_openai(audio_file_path):
    """Transcribe audio using OpenAI Whisper API"""
    try:
        print(f"Starting transcription of: {audio_file_path}")
        
        # Check file size
        file_size = os.path.getsize(audio_file_path)
        print(f"File size: {file_size / (1024*1024):.2f} MB")
        
        # OpenAI Whisper API has a 25MB limit
        if file_size > 25 * 1024 * 1024:  # 25MB
            print(f"File too large ({file_size / (1024*1024):.2f} MB) for OpenAI API (25MB limit)")
            return None
        
        # Convert to WAV if needed
        wav_path = convert_audio_to_wav(audio_file_path)
        print(f"Converted to WAV: {wav_path}")
        
        with open(wav_path, 'rb') as audio_file:
            print("Sending to OpenAI Whisper API...")
            transcript = client.audio.transcriptions.create(
                model="whisper-1",
                file=audio_file,
                response_format="verbose_json"
            )
            print("Received response from OpenAI")
        
        return transcript
    except Exception as e:
        print(f"Error transcribing with OpenAI: {e}")
        import traceback
        traceback.print_exc()
        return None

def transcribe_with_google(audio_file_path):
    """Fallback transcription using Google Speech Recognition"""
    if not SPEECH_RECOGNITION_AVAILABLE:
        return None
    try:
        recognizer = sr.Recognizer()
        with sr.AudioFile(audio_file_path) as source:
            audio = recognizer.record(source)
            text = recognizer.recognize_google(audio)
            return {"text": text, "method": "google"}
    except Exception as e:
        print(f"Error transcribing with Google: {e}")
        return None

def transcribe_long_audio(audio_file_path):
    """Transcribe long audio by splitting into chunks"""
    try:
        file_size = os.path.getsize(audio_file_path)
        file_size_mb = file_size / (1024*1024)
        
        # If file is under 25MB, process normally
        if file_size_mb <= 25:
            return transcribe_with_openai(audio_file_path)
        
        print(f"File is {file_size_mb:.1f} MB, splitting into chunks...")
        
        # Split into 10-minute chunks (approximately 15-20MB each)
        chunks = split_audio_into_chunks(audio_file_path, chunk_duration_minutes=10)
        
        all_transcripts = []
        for i, chunk_path in enumerate(chunks):
            print(f"Processing chunk {i+1}/{len(chunks)}: {chunk_path}")
            
            # Transcribe chunk
            chunk_transcript = transcribe_with_openai(chunk_path)
            if chunk_transcript:
                all_transcripts.append(chunk_transcript.text)
            
            # Clean up chunk file
            if os.path.exists(chunk_path):
                os.remove(chunk_path)
        
        if all_transcripts:
            # Combine all transcripts
            combined_text = " ".join(all_transcripts)
            return type('obj', (object,), {
                'text': combined_text,
                'method': 'openai_chunked'
            })()
        else:
            return None
            
    except Exception as e:
        print(f"Error in long audio transcription: {e}")
        return None

def generate_summary(transcript_text, summary_type="key_points"):
    """Generate summary of transcription using OpenAI GPT"""
    try:
        if summary_type == "key_points":
            prompt = f"""Please analyze this meeting transcript and provide a concise summary with key points:

{transcript_text}

Please provide:
1. Main topics discussed
2. Key decisions made
3. Action items and next steps
4. Important insights or conclusions

Format as a clear, structured summary."""
        
        elif summary_type == "executive":
            prompt = f"""Please create an executive summary of this meeting transcript:

{transcript_text}

Provide a high-level overview including:
- Meeting purpose and outcomes
- Strategic decisions
- Business impact
- Recommendations

Keep it concise and executive-friendly."""
        
        elif summary_type == "detailed":
            prompt = f"""Please create a detailed summary of this meeting transcript:

{transcript_text}

Include:
- Complete agenda coverage
- All major discussion points
- Decisions and rationale
- Action items with assignees
- Timeline and deadlines
- Risks and concerns raised

Provide a comprehensive but organized summary."""
        
        else:
            prompt = f"""Please summarize this meeting transcript:

{transcript_text}

Provide a clear, concise summary of the main points discussed."""
        
        response = client.chat.completions.create(
            model="gpt-3.5-turbo",
            messages=[
                {"role": "system", "content": "You are a professional meeting summarizer. Create clear, actionable summaries."},
                {"role": "user", "content": prompt}
            ],
            max_tokens=1000,
            temperature=0.3
        )
        
        return response.choices[0].message.content
        
    except Exception as e:
        print(f"Error generating summary: {e}")
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
        
        # Transcribe with OpenAI (handles long files automatically)
        transcript = transcribe_long_audio(file_path)
        
        if transcript:
            # Clean up temporary file
            os.remove(file_path)
            
            return jsonify({
                'success': True,
                'transcript': transcript.text,
                'method': transcript.method
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
                os.remove(file_path)
                return jsonify({'error': 'Transcription failed. Please try again.'}), 500
                
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
        
        # Transcribe (handles long files automatically)
        transcript = transcribe_long_audio(file_path)
        
        if transcript:
            # Clean up
            os.remove(file_path)
            return jsonify({
                'success': True,
                'transcript': transcript.text,
                'method': transcript.method
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

@app.route('/summarize', methods=['POST'])
@login_required
def summarize_transcript():
    """Generate summary of transcription"""
    try:
        data = request.get_json()
        transcript_text = data.get('transcript')
        summary_type = data.get('summary_type', 'key_points')
        
        if not transcript_text:
            return jsonify({'error': 'No transcript provided'}), 400
        
        print(f"Generating {summary_type} summary...")
        summary = generate_summary(transcript_text, summary_type)
        
        if summary:
            return jsonify({
                'success': True,
                'summary': summary,
                'summary_type': summary_type
            })
        else:
            return jsonify({'error': 'Failed to generate summary'}), 500
            
    except Exception as e:
        return jsonify({'error': f'Summary error: {str(e)}'}), 500

if __name__ == '__main__':
    # Check if OpenAI API key is configured
    if not os.getenv('OPENAI_API_KEY'):
        print("Warning: OPENAI_API_KEY not found in environment variables.")
        print("Please set your OpenAI API key in the .env file.")
    
    # Check if admin credentials are configured
    if not os.getenv('ADMIN_USERNAME') or not os.getenv('ADMIN_PASSWORD'):
        print("Warning: ADMIN_USERNAME or ADMIN_PASSWORD not found in environment variables.")
        print("Please set ADMIN_USERNAME and ADMIN_PASSWORD in the .env file for security.")
        print("Default credentials will not work - you must configure your own.")
    
    app.run(debug=True, host='0.0.0.0', port=5002)
