import Foundation

protocol FileStorageManagerProtocol {
    func saveMeeting(_ meeting: Meeting) throws
    func loadMeeting(id: UUID) throws -> Meeting
    func loadAllMeetings() throws -> [Meeting]
    func deleteMeeting(id: UUID) throws
    func saveTranscript(_ text: String, for meeting: Meeting) throws
    func saveSummary(_ text: String, for meeting: Meeting) throws
    func loadTranscript(for meeting: Meeting) throws -> String
    func loadSummary(for meeting: Meeting) throws -> String
    func exportTranscript(for meeting: Meeting) throws -> URL
    func exportSummary(for meeting: Meeting) throws -> URL
}

final class FileStorageManager: FileStorageManagerProtocol {
    private let fileManager = FileManager.default

    private var documentsDirectory: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    private var meetingsDirectory: URL {
        documentsDirectory.appendingPathComponent("Meetings", isDirectory: true)
    }

    private var metadataDirectory: URL {
        documentsDirectory.appendingPathComponent("Metadata", isDirectory: true)
    }

    init() {
        try? fileManager.createDirectory(at: meetingsDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: metadataDirectory, withIntermediateDirectories: true)
    }

    // MARK: - Meeting CRUD

    func saveMeeting(_ meeting: Meeting) throws {
        let url = metadataDirectory.appendingPathComponent("\(meeting.id.uuidString).json")
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(meeting)
            try data.write(to: url, options: .atomic)
        } catch {
            throw AppError.fileWriteFailed(error)
        }
    }

    func loadMeeting(id: UUID) throws -> Meeting {
        let url = metadataDirectory.appendingPathComponent("\(id.uuidString).json")
        guard fileManager.fileExists(atPath: url.path) else {
            throw AppError.fileNotFound(url.lastPathComponent)
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(Meeting.self, from: data)
        } catch {
            throw AppError.fileReadFailed(error)
        }
    }

    func loadAllMeetings() throws -> [Meeting] {
        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: metadataDirectory,
                includingPropertiesForKeys: [.creationDateKey],
                options: .skipsHiddenFiles
            )
        } catch {
            throw AppError.fileReadFailed(error)
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        var meetings = [Meeting]()
        for url in contents where url.pathExtension == "json" {
            if let data = try? Data(contentsOf: url),
               let meeting = try? decoder.decode(Meeting.self, from: data) {
                meetings.append(meeting)
            }
        }

        return meetings.sorted { $0.createdAt > $1.createdAt }
    }

    func deleteMeeting(id: UUID) throws {
        let metadataURL = metadataDirectory.appendingPathComponent("\(id.uuidString).json")
        let meetingDir = meetingsDirectory.appendingPathComponent(id.uuidString)

        try? fileManager.removeItem(at: metadataURL)
        try? fileManager.removeItem(at: meetingDir)
    }

    // MARK: - Transcript & Summary

    func saveTranscript(_ text: String, for meeting: Meeting) throws {
        let dir = meetingDirectory(for: meeting)
        try ensureDirectory(dir)
        let url = dir.appendingPathComponent(meeting.transcriptFileName)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw AppError.fileWriteFailed(error)
        }
    }

    func saveSummary(_ text: String, for meeting: Meeting) throws {
        let dir = meetingDirectory(for: meeting)
        try ensureDirectory(dir)
        let url = dir.appendingPathComponent(meeting.summaryFileName)
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            throw AppError.fileWriteFailed(error)
        }
    }

    func loadTranscript(for meeting: Meeting) throws -> String {
        let url = meetingDirectory(for: meeting).appendingPathComponent(meeting.transcriptFileName)
        guard fileManager.fileExists(atPath: url.path) else {
            throw AppError.fileNotFound(meeting.transcriptFileName)
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw AppError.fileReadFailed(error)
        }
    }

    func loadSummary(for meeting: Meeting) throws -> String {
        let url = meetingDirectory(for: meeting).appendingPathComponent(meeting.summaryFileName)
        guard fileManager.fileExists(atPath: url.path) else {
            throw AppError.fileNotFound(meeting.summaryFileName)
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw AppError.fileReadFailed(error)
        }
    }

    // MARK: - Export

    func exportTranscript(for meeting: Meeting) throws -> URL {
        meetingDirectory(for: meeting).appendingPathComponent(meeting.transcriptFileName)
    }

    func exportSummary(for meeting: Meeting) throws -> URL {
        meetingDirectory(for: meeting).appendingPathComponent(meeting.summaryFileName)
    }

    // MARK: - Private

    private func meetingDirectory(for meeting: Meeting) -> URL {
        meetingsDirectory.appendingPathComponent(meeting.id.uuidString, isDirectory: true)
    }

    private func ensureDirectory(_ url: URL) throws {
        if !fileManager.fileExists(atPath: url.path) {
            do {
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            } catch {
                throw AppError.fileWriteFailed(error)
            }
        }
    }
}
