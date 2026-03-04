import Foundation

enum AppError: LocalizedError {
    case microphonePermissionDenied
    case speechRecognitionPermissionDenied
    case audioSessionSetupFailed(Error)
    case recordingFailed(Error)
    case speechRecognitionUnavailable
    case speechRecognitionFailed(Error)
    case fileWriteFailed(Error)
    case fileReadFailed(Error)
    case fileNotFound(String)
    case summarizationFailed(Error)
    case networkError(Error)
    case apiKeyMissing
    case invalidResponse
    case audioBufferEmpty
    case diarizationFailed(Error)

    var errorDescription: String? {
        switch self {
        case .microphonePermissionDenied:
            return "Microphone access is required. Please enable it in Settings."
        case .speechRecognitionPermissionDenied:
            return "Speech recognition permission is required. Please enable it in Settings."
        case .audioSessionSetupFailed(let error):
            return "Audio session setup failed: \(error.localizedDescription)"
        case .recordingFailed(let error):
            return "Recording failed: \(error.localizedDescription)"
        case .speechRecognitionUnavailable:
            return "Speech recognition is not available on this device."
        case .speechRecognitionFailed(let error):
            return "Speech recognition error: \(error.localizedDescription)"
        case .fileWriteFailed(let error):
            return "Failed to save file: \(error.localizedDescription)"
        case .fileReadFailed(let error):
            return "Failed to read file: \(error.localizedDescription)"
        case .fileNotFound(let name):
            return "File not found: \(name)"
        case .summarizationFailed(let error):
            return "Summarization failed: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .apiKeyMissing:
            return "API key is not configured. Please add it in Settings."
        case .invalidResponse:
            return "Received an invalid response from the server."
        case .audioBufferEmpty:
            return "No audio data captured."
        case .diarizationFailed(let error):
            return "Speaker detection failed: \(error.localizedDescription)"
        }
    }
}
