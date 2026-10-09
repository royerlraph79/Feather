//
//  SourcesViewModel.swift
//  Feather
//
//  Created by samara on 30.04.2025.
//

import Foundation
import AltSourceKit
import SwiftUI
import NimbleJSON

// MARK: - Class
@MainActor
final class SourcesViewModel: ObservableObject {
	static let shared = SourcesViewModel()
	
	typealias RepositoryDataHandler = Result<ASRepository, Error>
	
	
	var isFinished = true
	@Published var sources: [AltSource: ASRepository] = [:]
	
	func fetchSources(_ sources: FetchedResults<AltSource>, refresh: Bool = false, batchSize: Int = 4) async {
		guard isFinished else { return }
		if !refresh, sources.allSatisfy({ self.sources[$0] != nil }) { return }

		isFinished = false
		defer { isFinished = true }
		self.sources = [:]

		let sourcesArray = Array(sources)
		let safeBatchSize = max(1, batchSize)

		for startIndex in stride(from: 0, to: sourcesArray.count, by: safeBatchSize) {
			let endIndex = min(startIndex + safeBatchSize, sourcesArray.count)

			await withTaskGroup(of: (Int, ASRepository?).self) { group in
				for index in startIndex..<endIndex {
					guard let url = sourcesArray[index].sourceURL else { continue }

					group.addTask {
						let repo: ASRepository? = await withCheckedContinuation { continuation in
							NBFetchService().fetch(from: url) { (result: RepositoryDataHandler) in
								continuation.resume(returning: try? result.get())
							}
						}
						return (index, repo)
					}
				}

				for await (index, repo) in group {
					if let repo {
						self.sources[sourcesArray[index]] = repo
					}
				}
			}
		}
	}

}
