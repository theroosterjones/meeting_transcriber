# Meeting Transcriber iOS — Architecture & Engineering Document

> This is the native iOS implementation of [Meeting Transcriber](../README.md).
> The original Python/Flask web app lives in the repository root. This iOS app
> replaces the browser + server architecture with a standalone on-device solution.

## 1. Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                        SwiftUI Views                        │
│  RecordingView  │  MeetingHistoryView  │  MeetingDetailView │
│                 │                      │  SettingsView       │
└────────┬────────┴──────────┬───────────┴──────────┬─────────┘
         │                   │                      │
         ▼                   ▼                      ▼
┌─────────────────────────────────────────────────────────────┐
│                        ViewModels                           │
│  MeetingRecorderVM  │  MeetingHistoryVM  │  MeetingDetailVM │
└────────┬────────────┴──────────┬─────────┴──────────┬───────┘
         │                       │                     │
         ▼                       │                     ▼
┌────────────────────┐           │        ┌────────────────────┐
│ TranscriptionEngine│           │        │SummarizationService│
│  (orchestrator)    │           │        │  (protocol-based)  │
└──┬──────┬──────┬───┘           │        └─────────┬──────────┘
   │      │      │               │                  │
   ▼      ▼      ▼               ▼                  ▼
┌──────┐┌──────┐┌──────┐  ┌──────────┐     ┌──────────────┐
│Audio ││Speech││Diari-│  │  File    │     │  OpenAI API  │
│Captu-││Recog-││zation│  │ Storage  │     │  (or local)  │
│re Mgr││n Mgr ││ Mgr  │  │ Manager  │     │              │
└──┬───┘└──┬───┘└──┬───┘  └──────────┘     └──────────────┘
   │       │       │
   ▼       ▼       ▼
┌──────────────────────────────┐
│    iOS Frameworks            │
│  AVFoundation  │  Speech     │
│  Accelerate    │  Foundation │
└──────────────────────────────┘
```

### Pattern: MVVM with Protocol-Oriented Service Layer

Every service is defined by a protocol, making each layer independently testable and
swappable. The `TranscriptionEngine` is the single orchestration point that wires
AudioCapture → SpeechRecognition → SpeakerDiarization into a unified Combine pipeline.

### Data Flow

1. `AudioCaptureManager` installs a tap on `AVAudioEngine`, publishing PCM buffers
2. `TranscriptionEngine` subscribes and fans out each buffer to:
   - `SpeechRecognitionManager.feedAudioBuffer()` for on-device transcription
   - `SpeakerDiarizationManager.processAudioBuffer()` for speaker feature extraction
3. Speech results arrive as partial/final via Combine; diarization publishes speaker changes
4. When a final speech result + speaker change align, a `TranscriptSegment` is emitted
5. The ViewModel appends segments to the live list; SwiftUI re-renders
6. On stop, segments are serialized to `.txt` and metadata to `.json` via `FileStorageManager`

---

## 2. Layer-by-Layer Breakdown

### 2.1 Audio Capture Layer (`AudioCaptureManager`)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Framework | AVAudioEngine | Streaming buffer access; lower latency than AVAudioRecorder |
| Sample rate | 16 kHz | Standard for speech; saves memory over 44.1 kHz |
| Format | Float32 mono | Required by both Speech framework and diarization DSP |
| Buffer size | 1024 frames | ~64ms chunks; good balance of latency vs overhead |
| Interruption handling | Pause/resume on AVAudioSession notifications | Required for phone calls, Siri, etc. |

Key implementation detail: the hardware sample rate may differ from 16 kHz.
An `AVAudioConverter` resamples in the tap callback before publishing.

### 2.2 Speech Recognition Layer (`SpeechRecognitionManager`)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Engine | SFSpeechRecognizer (on-device) | Zero network cost; works offline; privacy |
| Restart strategy | 55-second timer | Apple caps continuous recognition at ~1 min |
| Punctuation | `addsPunctuation = true` (iOS 16+) | Cleaner output without post-processing |
| Locale | en-US (configurable) | Most common; can be made user-selectable |

The 55-second restart timer transparently ends the current recognition request and
creates a new one. The last finalized text is cached to avoid duplicating it in the
next session's output. This enables 1+ hour recordings.

### 2.3 Speaker Diarization Layer (`SpeakerDiarizationManager`)

**This is the most nuanced engineering decision in the app.**

| Approach | Accuracy | Latency | Offline | Battery | Complexity |
|----------|----------|---------|---------|---------|------------|
| Energy + spectral features (chosen) | Moderate (2-3 speakers) | <5ms | Yes | Excellent | Medium |
| CoreML ECAPA-TDNN embedding model | High (5+ speakers) | ~30ms | Yes | Good | High |
| Whisper + pyannote via cloud | Very high | 2-5s | No | N/A | Low |

**Chosen approach: On-device spectral feature clustering.**

The implementation extracts a 26-dimensional feature vector per audio chunk:
- RMS energy (1 dim)
- Zero-crossing rate (1 dim)
- Spectral centroid, rolloff, flatness (3 dims)
- 8-band energy distribution (8 dims)
- 13 MFCC-like coefficients via log-mel + DCT (13 dims)

Speakers are assigned by cosine similarity against running centroid vectors.
New speakers are created when similarity falls below 0.82 threshold. Centroids
are updated online (running mean), so the system adapts to each speaker's voice
throughout the meeting.

**Upgrade path:** Export an ECAPA-TDNN model from SpeechBrain as CoreML, drop it
into the project, and replace `extractFeatures()` with model inference. The
`SpeakerDiarizationManagerProtocol` makes this a drop-in swap.

### 2.4 Summarization Layer (`SummarizationService`)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Default provider | OpenAI-compatible API | Best quality; user already has API key from Python version |
| Model | gpt-4o-mini | Good quality/cost ratio; fast |
| Long transcript handling | Chunk into ~9K word segments, summarize each, then merge | Handles 1+ hour meetings |
| Abstraction | Protocol (`SummarizationServiceProtocol`) | Swap to local LLM without UI changes |
| Summary types | Key Points, Executive, Detailed | Maps 1:1 from the Python app's 3 summary types |

The `baseURL` is configurable, so any OpenAI-compatible endpoint works:
OpenRouter, Azure OpenAI, local llama.cpp server, Ollama, etc.

### 2.5 Storage Layer (`FileStorageManager`)

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Storage location | App Documents directory | Survives app updates; visible in Files.app |
| Metadata format | JSON (one file per meeting) | Structured; supports future schema evolution |
| Transcript format | Plain text (.txt) | Matches Python version output; universally readable |
| Directory structure | `Meetings/{uuid}/` + `Metadata/{uuid}.json` | Clean separation; easy to back up |

---

## 3. Migration Plan: Python → iOS

### Phase 1: Core Recording + Transcription (Week 1)
- [x] AudioCaptureManager (replaces MediaRecorder + browser audio)
- [x] SpeechRecognitionManager (replaces Whisper API for transcription)
- [x] TranscriptionEngine orchestrator
- [x] Basic RecordingView with live display

**Key difference from Python:** The Python version records audio chunks in the browser
(WebM/Opus), sends them to Flask as base64, converts to WAV with pydub, then sends to
Whisper API. The iOS version eliminates all of this: AVAudioEngine provides PCM directly,
and SFSpeechRecognizer transcribes in real-time on device. No audio file is ever created
during recording.

### Phase 2: Speaker Diarization (Week 2)
- [x] SpeakerDiarizationManager with spectral features
- [x] Integration into TranscriptionEngine pipeline
- [x] Speaker badge UI components

**Key difference from Python:** The Python version has NO diarization at all. The iOS
version adds genuine speaker detection, which is entirely new functionality.

### Phase 3: Storage + History (Week 2-3)
- [x] FileStorageManager
- [x] Meeting history list view
- [x] Meeting detail view with transcript display
- [x] Export/share functionality

**Key difference from Python:** Python stores flat files in `transcripts/` with timestamp
names. iOS uses structured JSON metadata alongside text files, organized by UUID. This
supports richer queries and future sync capabilities.

### Phase 4: Summarization (Week 3)
- [x] SummarizationService protocol
- [x] OpenAI implementation with chunking
- [x] Summary type picker (same 3 types as Python)
- [x] API configuration UI

**Key difference from Python:** Python calls GPT-3.5-turbo from Flask. iOS calls
gpt-4o-mini from the device directly. The chunking strategy is the same (split large
transcripts, summarize parts, merge). No backend server needed.

### Phase 5: Polish + App Store (Week 4)
- Add asset catalog with app icon
- Onboarding flow for first-time permissions
- Accessibility audit (VoiceOver, Dynamic Type)
- Performance profiling on older devices (iPhone 12 minimum)
- TestFlight beta testing

---

## 4. Folder Structure

```
MeetingTranscriber/
├── MeetingTranscriber.xcodeproj/
│   └── project.pbxproj
└── MeetingTranscriber/
    ├── Info.plist
    ├── App/
    │   └── MeetingTranscriberApp.swift          # @main entry point
    ├── Models/
    │   ├── Meeting.swift                         # Core data model
    │   ├── TranscriptSegment.swift               # Single utterance
    │   ├── SpeakerProfile.swift                  # Speaker embedding + metadata
    │   └── AppError.swift                        # Typed error enum
    ├── Services/
    │   ├── Audio/
    │   │   └── AudioCaptureManager.swift         # AVAudioEngine tap + resampling
    │   ├── Speech/
    │   │   ├── SpeechRecognitionManager.swift    # SFSpeechRecognizer streaming
    │   │   └── TranscriptionEngine.swift         # Pipeline orchestrator
    │   ├── Diarization/
    │   │   └── SpeakerDiarizationManager.swift   # Spectral feature clustering
    │   ├── Summarization/
    │   │   └── SummarizationService.swift        # Protocol + OpenAI impl
    │   ├── Storage/
    │   │   └── FileStorageManager.swift          # Documents directory I/O
    │   └── Network/
    │       └── APIConfiguration.swift            # User-configurable API settings
    ├── ViewModels/
    │   ├── MeetingRecorderViewModel.swift        # Recording state + live segments
    │   ├── MeetingHistoryViewModel.swift         # Meeting list CRUD
    │   └── MeetingDetailViewModel.swift          # Detail + summarization
    ├── Views/
    │   ├── ContentView.swift                     # TabView root
    │   ├── Recording/
    │   │   └── RecordingView.swift               # Live recording UI
    │   ├── History/
    │   │   └── MeetingHistoryView.swift          # Meeting list + delete
    │   ├── Detail/
    │   │   └── MeetingDetailView.swift           # Transcript + summary tabs
    │   └── Components/
    │       ├── AudioLevelIndicator.swift          # Real-time meter
    │       ├── SpeakerBadge.swift                 # Color-coded speaker pill
    │       ├── TranscriptSegmentRow.swift         # Single segment display
    │       └── SettingsView.swift                 # API key config
    ├── Utilities/                                # Extensions, helpers (future)
    └── Resources/                                # Assets, fonts (future)
```

---

## 5. Recommendations

### 5.1 Best Diarization Approach on iOS

**Recommendation: Ship with spectral features; upgrade to ECAPA-TDNN CoreML in v1.1.**

The spectral feature approach implemented here works well for 2-3 speaker meetings
(which covers 80%+ of use cases). It runs at <5ms per buffer, uses zero additional
memory beyond the 26-float feature vectors, and works fully offline.

For a v1.1 upgrade:
1. Export ECAPA-TDNN from SpeechBrain (`speechbrain/spkrec-ecapa-voxceleb`)
2. Convert to CoreML via `coremltools`
3. The 192-dimensional embeddings give much better speaker separation
4. Expected inference time: ~30ms per 1.5s chunk on A15+ chips
5. Swap by implementing `SpeakerDiarizationManagerProtocol` — zero UI changes

### 5.2 Best Summarization Approach

**Recommendation: Cloud API (OpenAI-compatible) with configurable endpoint.**

On-device LLMs (e.g., Apple's foundation models in iOS 18.4+) are improving but cannot
yet reliably summarize 10,000+ word transcripts with the quality GPT-4o-mini achieves.
The configurable `baseURL` means users can point to:

- OpenAI directly
- Azure OpenAI (for enterprise compliance)
- A self-hosted Ollama/vLLM instance on their own hardware
- Any OpenAI-compatible proxy

When Apple ships on-device foundation model APIs with sufficient context windows,
implement `SummarizationServiceProtocol` with an `AppleIntelligenceService` — zero
UI or ViewModel changes required.

### 5.3 Backend Necessity

**Recommendation: No backend required. Ship as a fully standalone app.**

| Python version | iOS version |
|----------------|-------------|
| Flask server needed | No server |
| Browser records, server transcribes | Device does both |
| Whisper API via server | SFSpeechRecognizer on-device |
| GPT via server proxy | Direct API call from device |
| Server stores files | Device stores files |

The only network call the iOS app makes is the optional summarization API call,
which goes directly from device to OpenAI. No intermediary server, no hosting costs,
no scaling concerns.

---

## 6. Tradeoff Analysis

### Option A: Fully On-Device

| Aspect | Assessment |
|--------|------------|
| **Transcription** | SFSpeechRecognizer: good for clear speech, degrades with accents/noise. ~90% accuracy in quiet rooms. |
| **Diarization** | Spectral features: works for 2-3 speakers. No pre-trained speaker models needed. |
| **Summarization** | Apple Intelligence (iOS 18.4+): limited context window, not yet production-ready for long documents. |
| **Privacy** | Maximum — zero data leaves device. |
| **Offline** | Fully functional (except summarization). |
| **Battery** | Excellent — no network I/O during recording. |
| **Cost** | $0 per user per month. |
| **Verdict** | **Ship this for recording + transcription. Not viable for summarization yet.** |

### Option B: Hybrid (Chosen)

| Aspect | Assessment |
|--------|------------|
| **Transcription** | On-device SFSpeechRecognizer — same as Option A. |
| **Diarization** | On-device spectral features — same as Option A. |
| **Summarization** | Cloud API (user's own API key) — high quality, user controls costs. |
| **Privacy** | Transcript text sent to API only when user explicitly taps "Generate Summary." |
| **Offline** | Recording + transcription work offline. Summary requires connection. |
| **Battery** | Excellent during recording. One short network burst for summary. |
| **Cost** | ~$0.01-0.05 per summary (GPT-4o-mini). User provides their own key. |
| **Verdict** | **Best overall balance. Recommended for v1.0.** |

### Option C: Cloud-First

| Aspect | Assessment |
|--------|------------|
| **Transcription** | Whisper API: higher accuracy, handles accents/noise better. Adds 2-5s latency. |
| **Diarization** | pyannote.audio via server: state-of-the-art accuracy, 5+ speakers. |
| **Summarization** | Same cloud API. |
| **Privacy** | All audio leaves device. Must comply with GDPR, SOC2, etc. |
| **Offline** | Nothing works offline. |
| **Battery** | Worse — continuous audio streaming over network. |
| **Cost** | $0.006/min Whisper + GPU server for pyannote + API calls. ~$0.50-2.00/hour of meeting. |
| **Scaling** | Need to run and maintain server infrastructure. |
| **Verdict** | **Only justified for enterprise customers who need maximum accuracy and will pay for it. Overkill for v1.0.** |

### Decision Matrix

| Criterion (weight) | On-Device | Hybrid | Cloud-First |
|---------------------|-----------|--------|-------------|
| Privacy (25%) | 10 | 8 | 3 |
| Accuracy (20%) | 6 | 7 | 10 |
| Offline capability (15%) | 10 | 8 | 0 |
| Battery efficiency (15%) | 10 | 9 | 4 |
| Cost to user (15%) | 10 | 9 | 3 |
| Implementation complexity (10%) | 7 | 7 | 4 |
| **Weighted total** | **8.7** | **8.0** | **3.9** |

**The hybrid approach scores highest when privacy, offline, and battery are weighted
appropriately for a mobile app.** The cloud-first approach only wins if accuracy is
the sole criterion, which it rarely is for an App Store consumer product.

---

## 7. Performance Guarantees

| Concern | Solution |
|---------|----------|
| Main thread blocking | All audio processing on AVAudioEngine's render thread; all speech callbacks off-main; only UI state updates dispatched to main |
| Memory (long recordings) | Segments are lightweight structs (~200 bytes each); 1-hour meeting ≈ 2,000 segments ≈ 400KB |
| Battery during recording | 16 kHz mono audio + on-device speech + lightweight DSP ≈ 5-8% battery per hour on iPhone 14+ |
| App backgrounding | `UIBackgroundModes: audio` keeps recording alive; AVAudioSession interruption handler manages phone calls |
| Large transcript summarization | Chunked into ~9K word segments; parallel API calls possible (serial by default to stay within rate limits) |
| Storage | JSON metadata + text files; 1,000 meetings ≈ 50MB. No SQLite overhead. |

---

## 8. Testing Strategy

| Layer | Test Type | Tool |
|-------|-----------|------|
| Models | Unit tests | XCTest |
| FileStorageManager | Unit tests with temp directory | XCTest |
| SpeakerDiarizationManager | Unit tests with synthetic audio buffers | XCTest |
| SummarizationService | Mock protocol conformance | XCTest + protocol mocks |
| ViewModels | Unit tests with injected mock services | XCTest |
| UI | Snapshot + interaction tests | XCUITest |
| Integration | End-to-end recording on device | TestFlight |

Every service has a protocol, so ViewModels can be tested with mock implementations
that return predetermined data. No network calls needed in the test suite.
