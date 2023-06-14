//
//  LogstashLogHandler.swift
//
//
//  Created by Philipp Zagar on 26.06.21.
//

import Foundation
import Logging

/// `LogstashLogHandler` is a simple implementation of `LogHandler` for directing
/// `Logger` output to Logstash via HTTP requests
public struct LogstashLogHandler: LogHandler {
	/// The label of the `LogHandler`
	let label: String
	/// The host where a Logstash instance is running
	static var url: URL?
	/// Used to log background activity of the `LogstashLogHandler` and `HTTPClient`
	/// This logger MUST be created BEFORE the `LoggingSystem` is bootstrapped, else it results in an infinte recusion!
	static var backgroundActivityLogger: Logger?
	/// Represents a certain amount of time which serves as a delay between the triggering of the uploading to Logstash
	static var uploadInterval: TimeInterval?
	/// Specifies how large the log storage `ByteBuffer` must be at least
	static var logStorageSize: Int?
	/// Specifies how large the log storage `ByteBuffer` with all the current uploading buffers can be at the most
	static var maximumTotalLogStorageSize: Int?

	static var urlSession: URLSession = .shared
	/// The `HTTPClient.Request` which stays consistent (except the body) over all uploadings to Logstash
	static var urlRequest: URLRequest?

	static var timer: Task<Void, Swift.Error>?

	/// The log storage byte buffer which serves as a cache of the log data entires
	static var storage: LogstachLogStorage = .init()

	/// Keeps track of how much memory is allocated in total
	static var totalByteBufferSize: Int?

	/// The default `Logger.Level` of the `LogstashLogHandler`
	/// Logging entries below this `Logger.Level` won't get logged at all
	public var logLevel: Logger.Level = .info
	/// Holds the `Logger.Metadata` of the `LogstashLogHandler`
	public var metadata = Logger.Metadata()
	/// Convenience subscript to get and set `Logger.Metadata`
	public subscript(metadataKey metadataKey: String) -> Logger.Metadata.Value? {
		get {
			self.metadata[metadataKey]
		}
		set {
			self.metadata[metadataKey] = newValue
		}
	}

	/// Creates a `LogstashLogHandler` that directs its output to Logstash
	// Make sure that the `backgroundActivityLogger` is instanciated BEFORE `LoggingSystem.bootstrap(...)` is called (currently not even possible otherwise)
	public init(label: String) {
		// If LogstashLogHandler was not yet set up, abort
		guard let _ = Self.url else {
			fatalError(Error.notYetSetup.rawValue)
		}

		self.label = label

		// Set a "super-secret" metadata value to validate that the backgroundActivityLogger
		// doesn't use the LogstashLogHandler as a logging backend
		// Currently, this behavior isn't even possible in production, but maybe in future versions of the swift-log package
		self[metadataKey: "super-secret-is-a-logstash-loghandler"] = .string("true")
	}

	/// Setup of the `LogstashLogHandler`, need to be called once before `LoggingSystem.bootstrap(...)` is called
	public static func setup(hostname: String,
													 port: Int,
													 useHTTPS: Bool = false,
													 backgroundActivityLogger: Logger = Logger(label: "backgroundActivity-logstashHandler"),
													 uploadInterval: TimeInterval = 3.0,
													 logStorageSize: Int = 524_288,
													 maximumTotalLogStorageSize: Int = 4_194_304) {
		self.url = URL(string: "\(useHTTPS ? "https" : "http")://\(hostname):\(port)")
		Self.backgroundActivityLogger = backgroundActivityLogger
		Self.uploadInterval = uploadInterval
		// If the double minimum log storage size is larger than maximum log storage size throw error
		if maximumTotalLogStorageSize.nextPowerOf2() < (2 * logStorageSize.nextPowerOf2()) {
			fatalError(Error.maximumLogStorageSizeTooLow.rawValue)
		}
		// Round up to the power of two since ByteBuffer automatically allocates in these steps
		Self.logStorageSize = logStorageSize.nextPowerOf2()
		Self.maximumTotalLogStorageSize = maximumTotalLogStorageSize.nextPowerOf2()

		// Need to be wrapped in a class since those properties can be mutated
		Self.storage = .init()
		Self.totalByteBufferSize = maximumTotalLogStorageSize

		// Check if backgroundActivityLogger doesn't use the LogstashLogHandler as a logging backend
		if let usesLogstashHandlerValue = backgroundActivityLogger[metadataKey: "super-secret-is-a-logstash-loghandler"],
			 case .string(let usesLogstashHandler) = usesLogstashHandlerValue,
			 usesLogstashHandler == "true" {

			fatalError(Error.backgroundActivityLoggerBackendError.rawValue)
		}
	}

	/// The main log function of the `LogstashLogHandler`
	/// Merges the `Logger.Metadata`, encodes the log entry to a propertly formatted HTTP body
	/// which is then cached in the log store `ByteBuffer`
	// This function is thread-safe via a `ConditionalLock` on the log store `ByteBuffer`
	public func log(level: Logger.Level,            // swiftlint:disable:this function_parameter_count function_body_length
									message: Logger.Message,
									metadata: Logger.Metadata?,
									source: String,
									file: String,
									function: String,
									line: UInt) {
		guard let uploadInterval = Self.uploadInterval else {
			fatalError(Error.notYetSetup.rawValue)
		}

		let mergedMetadata = mergeMetadata(passedMetadata: metadata, file: file, function: function, line: line)

		guard let logData = encodeLogData(level: level, message: message, metadata: mergedMetadata) else {
			Self.backgroundActivityLogger?.log(
				level: .warning,
				"Error during encoding log data",
				metadata: [
					"label": .string(self.label),
					"logEntry": .dictionary(
						[
							"message": .string(message.description),
							"metadata": .dictionary(mergedMetadata),
							"logLevel": .string(level.rawValue)
						]
					)
				]
			)

			return
		}

		Task {
			await Self.storage.appendData(logData)
		}

		if Self.timer == nil {
			Self.scheduleUploadTask(initialDelay: uploadInterval)
		}
	}
}
