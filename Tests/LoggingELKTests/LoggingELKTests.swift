import XCTest
import NIO
@testable import LoggingELK
@testable import Logging

final class LoggingELKTests: XCTestCase {
    private var logstashHandler: LogstashLogHandler!    // swiftlint:disable:this implicitly_unwrapped_optional
    private var logger: Logger!                         // swiftlint:disable:this implicitly_unwrapped_optional
    
    /// Setup of the necessary logging backend `LogstashLogHandler` and bootstrap the `LoggingSystem` once for the entire test class
    override func setUp() {
        super.setUp()
        
        // Set high uploadInterval so that the actual uploading never happens
        LogstashLogHandler.setup(hostname: "0.0.0.0",
                                 port: 31311,
                                 backgroundActivityLogger: Logger(label: "backgroundActivity-logstashHandler",
                                                                  factory: StreamLogHandler.standardOutput),
                                 uploadInterval: 1000,
                                 logStorageSize: 1000)
        
        // Cancel the actual uploading to Logstash
        LogstashLogHandler.timer = nil
        
        self.logstashHandler = LogstashLogHandler(label: "logstash-test")

        // Use .bootstrapInternal to be able to bootstrap the logging backend multiple times
        LoggingSystem.bootstrapInternal { _ in
            self.logstashHandler
        }
        
        self.logger = Logger(label: "test")
    }
    
    
    /// Clear the internal state of the logging backend `LogstashLogHandler` after each test case
    override func tearDown() {
        super.tearDown()
        
        // Clear metadata
        self.logstashHandler.metadata.removeAll()
        // Clear the bytebuffer after each test run
        LogstashLogHandler.byteBuffer?.clear()
    }
    
    
    func testSimpleLogging() {
        XCTAssertTrue(LogstashLogHandler.byteBuffer?.readableBytes == 0)
        
        self.logger.error(Logger.Message(stringLiteral: self.randomString(length: 10)),
                          metadata: [self.randomString(length: 10): Logger.MetadataValue.string(self.randomString(length: 10))])
        
        XCTAssertTrue(LogstashLogHandler.byteBuffer!.readableBytes > 0)
    }
    
    /// Default log level is .info, so logs with level .trace won't be logged at all
    func testDefaultLogLevel() {
        XCTAssertTrue(LogstashLogHandler.byteBuffer?.readableBytes == 0)
        
        // Since default log level is .info, therefore .trace isn't logged
        self.logger.trace(Logger.Message(stringLiteral: self.randomString(length: 10)),
                          metadata: [self.randomString(length: 10): Logger.MetadataValue.string(self.randomString(length: 10))])
        
        XCTAssertTrue(LogstashLogHandler.byteBuffer!.readableBytes == 0)
    }
    
    /// Byte buffer must be at least the passed byte size
    func testByteBufferSize() {
        XCTAssertTrue(LogstashLogHandler.byteBuffer!.capacity > 1000)
    }
    
    func testSimpleMetadata() {
        let logMessage = Logger.Message(stringLiteral: self.randomString(length: 10))
        let logMetadata: Logger.Metadata = [self.randomString(length: 10): .string(self.randomString(length: 10))]
        
        self.logger.error(logMessage, metadata: logMetadata)
        
        guard let logDataSize: Int = LogstashLogHandler.byteBuffer?.readInteger(),
              let logData = LogstashLogHandler.byteBuffer?.readSlice(length: logDataSize) else {
            XCTFail("Log data couldn't be read from byte buffer")
            return
        }
        
        guard let logHTTPBody = try? JSONDecoder().decode(LogstashLogHandler.LogstashHTTPBody.self, from: logData) else {
            XCTFail("Error decoding the log HTTP body")
            return
        }
        
        XCTAssertEqual(logHTTPBody.loglevel, .error)
        XCTAssertEqual(logHTTPBody.message, logMessage)
        // Remove "location" metadata value
        var httpBodyMetadata = logHTTPBody.metadata
        httpBodyMetadata.removeValue(forKey: "location")
        XCTAssertEqual(httpBodyMetadata, logMetadata)
    }
    
    func testComplexMetadata() {
        let logMessage = Logger.Message(stringLiteral: self.randomString(length: 10))
        let logMetadata: Logger.Metadata =
        [
            self.randomString(length: 10): .dictionary(
                                                [
                                                    self.randomString(length: 10): .dictionary(
                                                        [
                                                            self.randomString(length: 10): .string(self.randomString(length: 10)),
                                                            self.randomString(length: 10): .array(
                                                                [
                                                                    .string(self.randomString(length: 10)),
                                                                    .dictionary(
                                                                        [
                                                                            self.randomString(length: 10): .array(
                                                                                [
                                                                                    .string(self.randomString(length: 10))
                                                                                ]
                                                                            )
                                                                        ]
                                                                    )
                                                                ]
                                                            )
                                                        ]
                                                    )
                                                ]
                                            )
        ]
        
        self.logger.info(logMessage, metadata: logMetadata)
        
        guard let logDataSize: Int = LogstashLogHandler.byteBuffer?.readInteger(),
              let logData = LogstashLogHandler.byteBuffer?.readSlice(length: logDataSize) else {
            XCTFail("Log data couldn't be read from byte buffer")
            return
        }
        
        guard let logHTTPBody = try? JSONDecoder().decode(LogstashLogHandler.LogstashHTTPBody.self, from: logData) else {
            XCTFail("Error decoding the log HTTP body")
            return
        }
        
        XCTAssertEqual(logHTTPBody.loglevel, .info)
        XCTAssertEqual(logHTTPBody.message, logMessage)
        // Remove "location" metadata value
        var httpBodyMetadata = logHTTPBody.metadata
        httpBodyMetadata.removeValue(forKey: "location")
        XCTAssertEqual(httpBodyMetadata, logMetadata)
    }
    
    func testEmptyMetadata() {
        let logMessage = Logger.Message(stringLiteral: self.randomString(length: 10))
        let logMetadata: Logger.Metadata =
        [
            self.randomString(length: 10): .string(""),
            self.randomString(length: 10): .array([]),
            self.randomString(length: 10): .dictionary([:])
        ]
        
        self.logger.info(logMessage, metadata: logMetadata)
        
        guard let logDataSize: Int = LogstashLogHandler.byteBuffer?.readInteger(),
              let logData = LogstashLogHandler.byteBuffer?.readSlice(length: logDataSize) else {
            XCTFail("Log data couldn't be read from byte buffer")
            return
        }
        
        guard let logHTTPBody = try? JSONDecoder().decode(LogstashLogHandler.LogstashHTTPBody.self, from: logData) else {
            XCTFail("Error decoding the log HTTP body")
            return
        }
        
        XCTAssertEqual(logHTTPBody.loglevel, .info)
        XCTAssertEqual(logHTTPBody.message, logMessage)
        // Remove "location" metadata value
        var httpBodyMetadata = logHTTPBody.metadata
        httpBodyMetadata.removeValue(forKey: "location")
        XCTAssertEqual(httpBodyMetadata, logMetadata)
    }
    
    func testCustomStringConvertibleMetadata() {
        let logMessage = Logger.Message(stringLiteral: self.randomString(length: 10))
        let logMetadata: Logger.Metadata =
        [
            "thisisatest": .stringConvertible("")
        ]
        // Since stringConvertible is automatically converted to a string during the encoding process and cannot be transformed back to a stringConvertible since the two can't be differentiated
        let expectedLogMetadata: Logger.Metadata =
        [
            "thisisatest": .string("")
        ]
        
        self.logger.info(logMessage, metadata: logMetadata)
        
        guard let logDataSize: Int = LogstashLogHandler.byteBuffer?.readInteger(),
              let logData = LogstashLogHandler.byteBuffer?.readSlice(length: logDataSize) else {
            XCTFail("Log data couldn't be read from byte buffer")
            return
        }
        
        guard let logHTTPBody = try? JSONDecoder().decode(LogstashLogHandler.LogstashHTTPBody.self, from: logData) else {
            XCTFail("Error decoding the log HTTP body")
            return
        }
        
        XCTAssertEqual(logHTTPBody.loglevel, .info)
        XCTAssertEqual(logHTTPBody.message, logMessage)
        // Remove "location" metadata value
        var httpBodyMetadata = logHTTPBody.metadata
        httpBodyMetadata.removeValue(forKey: "location")
    
        XCTAssertEqual(httpBodyMetadata, expectedLogMetadata)
    }
    
    func testMetadataMerging() {
        let logMessage = Logger.Message(stringLiteral: self.randomString(length: 10))
        let logMetadataLogger: Logger.Metadata =
        [
            self.randomString(length: 10): .string(self.randomString(length: 10))
        ]
        let logMetadataFunction: Logger.Metadata =
        [
            self.randomString(length: 10): .string(self.randomString(length: 10))
        ]
        
        // Set logger metadata
        self.logger[metadataKey: logMetadataLogger.first!.key] = logMetadataLogger.first!.value     // swiftlint:disable:this force_unwrapping
        // Set metadata for specific log entry via passing the metadata in the function call
        self.logger.info(logMessage, metadata: logMetadataFunction)
        
        guard let logDataSize: Int = LogstashLogHandler.byteBuffer?.readInteger(),
              let logData = LogstashLogHandler.byteBuffer?.readSlice(length: logDataSize) else {
            XCTFail("Log data couldn't be read from byte buffer")
            return
        }
        
        guard let logHTTPBody = try? JSONDecoder().decode(LogstashLogHandler.LogstashHTTPBody.self, from: logData) else {
            XCTFail("Error decoding the log HTTP body")
            return
        }
        
        XCTAssertEqual(logHTTPBody.loglevel, .info)
        XCTAssertEqual(logHTTPBody.message, logMessage)
        // Remove "location" metadata value
        var httpBodyMetadata = logHTTPBody.metadata
        httpBodyMetadata.removeValue(forKey: "location")
        // Metadata of the log entry must be equal to the merged metadata of the logger and the function
        XCTAssertEqual(httpBodyMetadata, logMetadataLogger.merging(logMetadataFunction) { _, new in new })
    }
    
    
    func testTooLargeLogEntry() {
        // Log data entry is larger than the size of the byte buffer (1024 byte)
        self.logger.info(Logger.Message(stringLiteral: self.randomString(length: 10)),
                         metadata:
                            [
                                self.randomString(length: 10): .string(self.randomString(length: 1000))
                            ]
        )
        
        // Goal is that "A single log entry is larger than the configured log storage size" error is printed on stdout
        // But sadly quite hard to test, maybe with a Pipe?
    }
    
    func testBackgroundActivityLoggerHasLogstashLogHandlerBackend() {
        // Create a new logger (that already has the LogstashLogHandler as a logging backend since
        // LoggingSystem.bootstrap(...) was already called
        let backgroundActivityLogger = Logger(label: "backgroundActivityLoggerWithLogstashLogHandlerBackend")
        
        // This initialization now fails since the backgroundActivityLogger has the LogstashLogHandler as a logging backend
        expectFatalError(expectedMessage: LogstashLogHandler.Error.backgroundActivityLoggerBackendError.rawValue) {
            LogstashLogHandler.setup(hostname: "0.0.0.0",
                                     port: 31311,
                                     backgroundActivityLogger: backgroundActivityLogger,
                                     uploadInterval: TimeAmount.seconds(1000),
                                     logStorageSize: 1000)
        }
    }
    
    func testMaximumLogStorageTooLow() {
        // This initialization fails since the maximumTotalLogStorageSize isn't at least double
        // of the logStorageSize (in terms of multiples of 2)
        expectFatalError(expectedMessage: LogstashLogHandler.Error.maximumLogStorageSizeTooLow.rawValue) {
            LogstashLogHandler.setup(hostname: "0.0.0.0",
                                     port: 31311,
                                     backgroundActivityLogger: LogstashLogHandler.backgroundActivityLogger!,
                                     uploadInterval: TimeAmount.seconds(1000),
                                     logStorageSize: 1000,
                                     maximumTotalLogStorageSize: 1023)
        }
    }
    
    private func randomString(length: Int) -> String {
        let letters = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
        return String((0..<length).map { _ in letters.randomElement() ?? "x" })
    }
}
