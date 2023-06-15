//
//  LogstashLogHandler+Uploading.swift
//  
//
//  Created by Philipp Zagar on 15.07.21.
//

import Foundation

extension LogstashLogHandler {
  static func scheduleUploadTask(initialDelay: TimeInterval) {
    guard timer == nil else {
      backgroundActivityLogger?.error("Timer already working")
      return
    }

    timer = Task {
      try await Task.sleep(nanoseconds: UInt64(initialDelay * TimeInterval(NSEC_PER_SEC)))
			do {
				try await uploadLogData()
			} catch {
				Self.backgroundActivityLogger?.error("\(error)")
			}
      Self.timer = nil
      scheduleUploadTask(initialDelay: initialDelay)
    }
  }

  /// Function which uploads the stored log data in the `ByteBuffer` to Logstash
  /// Never called directly, its only scheduled via the `scheduleUploadTask` function
  /// This function is thread-safe and designed to only block the stored log data `ByteBuffer`
  /// for a short amount of time (the time it takes to duplicate this bytebuffer). Then, the "original"
  /// stored log data `ByteBuffer` is freed and the lock is lifted
  static func uploadLogData() async throws {       // swiftlint:disable:this cyclomatic_complexity function_body_length

    let data = await storage.getData()

		guard !data.isEmpty else { return }

    guard let url = url else {
      fatalError("incorrect configuration of host and port")
    }

    let keepAlive: String
    if let uploadInterval = uploadInterval, uploadInterval < 10 && uploadInterval != 0 {
      keepAlive = "timeout=\(Int(uploadInterval * 3)), max=100"
    } else {
      keepAlive = "timeout=30, max=100"
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.allHTTPHeaderFields = [
      "Content-Type": "application/json",
      "Accept": "application/json",
      "Keep-Alive": keepAlive
    ]

    request.httpBody = data

    let (_, response) = try await Self.urlSession.data(for: request)

    guard let httpResponse = response as? HTTPURLResponse else {
      return
    }

    if httpResponse.statusCode != 200 {
      Self.backgroundActivityLogger?.log(
        level: .warning,
        "Error during sending logs to Logstash - \(httpResponse.statusCode)",
        metadata: [
          "url": .stringConvertible(url),
        ]
      )
		} else {
			await storage.popData(size: data.count)
		}
  }
}
