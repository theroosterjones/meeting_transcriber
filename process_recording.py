#!/usr/bin/env python3
"""
Standalone script to process the interrupted recording file
"""

import os
import sys
from pydub import AudioSegment
from openai import OpenAI
from dotenv import load_dotenv

# Load environment variables
load_dotenv()

# Configure OpenAI
client = OpenAI(api_key=os.getenv('OPENAI_API_KEY'))

def split_audio_into_chunks(audio_file_path, chunk_duration_minutes=3):
    """Split audio file into smaller chunks for processing"""
    try:
        print(f"Loading audio file: {audio_file_path}")
        audio = AudioSegment.from_file(audio_file_path)
        chunk_duration_ms = chunk_duration_minutes * 60 * 1000  # Convert to milliseconds
        
        print(f"Audio duration: {len(audio) / 1000 / 60:.1f} minutes")
        print(f"Splitting into {chunk_duration_minutes}-minute chunks...")
        
        chunks = []
        for i in range(0, len(audio), chunk_duration_ms):
            chunk = audio[i:i + chunk_duration_ms]
            chunk_path = f"{audio_file_path.rsplit('.', 1)[0]}_chunk_{i//chunk_duration_ms}.wav"
            # Export with lower quality to reduce file size
            chunk.export(chunk_path, format='wav', parameters=["-ar", "16000", "-ac", "1"])
            chunks.append(chunk_path)
            print(f"Created chunk {len(chunks)}: {chunk_path}")
        
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
        
        with open(audio_file_path, 'rb') as audio_file:
            print("Sending to OpenAI Whisper API...")
            print("This may take 1-3 minutes for large files...")
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

def process_large_audio(audio_file_path):
    """Process large audio by splitting into chunks"""
    try:
        file_size = os.path.getsize(audio_file_path)
        file_size_mb = file_size / (1024*1024)
        
        print(f"Processing file: {audio_file_path}")
        print(f"File size: {file_size_mb:.1f} MB")
        
        # Split into 3-minute chunks for faster processing
        chunks = split_audio_into_chunks(audio_file_path, chunk_duration_minutes=3)
        
        all_transcripts = []
        for i, chunk_path in enumerate(chunks):
            print(f"\nProcessing chunk {i+1}/{len(chunks)}: {chunk_path}")
            
            # Check chunk size before processing
            chunk_size = os.path.getsize(chunk_path) / (1024*1024)
            print(f"Chunk size: {chunk_size:.1f} MB")
            
            if chunk_size > 25:
                print(f"Chunk too large ({chunk_size:.1f} MB), skipping...")
                continue
            
            # Transcribe chunk
            chunk_transcript = transcribe_with_openai(chunk_path)
            if chunk_transcript:
                all_transcripts.append(chunk_transcript.text)
                print(f"✓ Chunk {i+1} transcribed successfully")
            else:
                print(f"✗ Chunk {i+1} transcription failed")
            
            # Clean up chunk file
            if os.path.exists(chunk_path):
                os.remove(chunk_path)
                print(f"Cleaned up chunk file: {chunk_path}")
        
        if all_transcripts:
            # Combine all transcripts
            combined_text = " ".join(all_transcripts)
            print(f"\n✅ Transcription complete!")
            print(f"Total chunks processed: {len(chunks)}")
            print(f"Successful transcriptions: {len(all_transcripts)}")
            print(f"Combined text length: {len(combined_text)} characters")
            
            # Save to transcripts directory
            import os
            transcripts_dir = 'transcripts'
            if not os.path.exists(transcripts_dir):
                os.makedirs(transcripts_dir)
            
            # Create a clean filename
            base_name = os.path.basename(audio_file_path).rsplit('.', 1)[0]
            output_file = os.path.join(transcripts_dir, f"{base_name}_transcript.txt")
            with open(output_file, 'w', encoding='utf-8') as f:
                f.write(combined_text)
            print(f"Transcript saved to: {output_file}")
            
            return combined_text
        else:
            print("❌ No transcriptions were successful")
            return None
            
    except Exception as e:
        print(f"Error in large audio processing: {e}")
        import traceback
        traceback.print_exc()
        return None

if __name__ == "__main__":
    # Process the specific recording file
    recording_file = "uploads/recorded_20250821_095908_7308451c5dce4071acd99e60d3b5e6b5.wav"
    
    if not os.path.exists(recording_file):
        print(f"Error: File {recording_file} not found!")
        sys.exit(1)
    
    print("🎤 Processing interrupted recording...")
    print("=" * 50)
    
    transcript = process_large_audio(recording_file)
    
    if transcript:
        print("\n🎉 Processing completed successfully!")
        print(f"Transcript preview: {transcript[:200]}...")
    else:
        print("\n❌ Processing failed!")
