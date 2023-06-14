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

	func popData() -> Data {
		let data = self.data
		self.data = Data()
		return data
	}

	private enum Constants {
		static let newLineCharacter: [UInt8] = [0x0a]
	}
}
