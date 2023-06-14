//
//  File.swift
//  
//
//  Created by Alexandr Zalutskiy on 14/06/2023.
//

import Foundation

actor LogstachLogStorage {
	var data = Data()

	func appendData(_ data: Data) {
		guard !data.isEmpty else {
			self.data = data
			return
		}

		self.data.append(contentsOf: Constants.newLineCharacter)
		self.data.append(data)
	}

	func getData() -> Data {
		return self.data
	}

	func popData(size: Int) {
		self.data = self.data.dropFirst(size)
	}

	private enum Constants {
		static let newLineCharacter: [UInt8] = [0x0a]
	}
}
