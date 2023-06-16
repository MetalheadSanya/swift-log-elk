//
//  File.swift
//  
//
//  Created by Alexandr Zalutskiy on 14/06/2023.
//

import Foundation

actor LogstachLogStorage {
	private let fileUrl: URL

	var data = Data()

	init() {
		var cacheFolder = FileManager.default.temporaryDirectory
		if let cache = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first {
			cacheFolder = cache
		}

		fileUrl = cacheFolder.appendingPathComponent("log.txt")
		if FileManager.default.fileExists(atPath: fileUrl.absoluteString) {
			do {
				data = try Data(contentsOf: fileUrl, options: [])
			} catch {
				LogstashLogHandler.backgroundActivityLogger?.error(
					"Error while read log file: \(error)"
				)
			}
		}
	}

	private func updateLogFile() {
		if FileManager.default.fileExists(atPath: fileUrl.absoluteString) {
			do {
				try FileManager.default.removeItem(at: fileUrl)
				try data.write(to: fileUrl, options: .atomic)
			} catch {
				LogstashLogHandler.backgroundActivityLogger?.error(
					"Error while write log file: \(error)"
				)
			}
		}
	}

	private func readLogFile() {

	}

	func appendData(_ data: Data) {
		if data.isEmpty {
			self.data = data
		} else {
			self.data.append(contentsOf: Constants.newLineCharacter)
			self.data.append(data)
		}
		updateLogFile()
	}

	func getData() -> Data {
		return self.data
	}

	func popData(size: Int) {
		if size == data.count {
			self.data = Data()
		} else {
			self.data = self.data.dropFirst(size + 1)
		}
		updateLogFile()
	}

	private enum Constants {
		static let newLineCharacter: [UInt8] = [0x0a]
	}
}
