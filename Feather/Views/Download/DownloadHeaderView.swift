//
//  DownloadHeaderView.swift
//  Feather
//
//  Created by samara on 16.05.2025.
//

import SwiftUI
import Combine
import NimbleExtensions

struct DownloadHeaderView: View {
	@ObservedObject var downloadManager: DownloadManager
	
	var body: some View {
		ZStack {
			if !downloadManager.manualDownloads.isEmpty {
				VStack(spacing: 12) {
					if let firstDownload = downloadManager.manualDownloads.first {
						DownloadItemView(download: firstDownload)

						if downloadManager.manualDownloads.count > 1 {
							HStack {
								Spacer()
								Text(verbatim: "+\(downloadManager.manualDownloads.count - 1)")
									.font(.caption)
									.foregroundColor(.secondary)
									.padding(.vertical, 4)
							}
						}
					}
				}
				.padding(.horizontal, 16)
				.padding(.vertical, 12)
				.modifier(DownloadHeaderSurface())
				.padding(.horizontal, 16)
				.padding(.top, 4)
				.transition(.move(edge: .top).combined(with: .opacity))
			}
		}
		.animation(.spring(), value: downloadManager.manualDownloads.count)
	}
}

/// Backdrop for the download header.
///
/// The header is transient chrome floating above the tab content, so it belongs
/// to the navigation layer and takes Liquid Glass on iOS 26. It is read-only
/// status, so the glass is deliberately not `.interactive()` — nothing in here
/// is tappable, and press affordance on unpressable content misleads.
///
/// `.regular` rather than `.clear`: clear needs media-rich content behind it and
/// a dimming layer to stay legible, neither of which applies over a plain app
/// background.
private struct DownloadHeaderSurface: ViewModifier {
	private var shape: RoundedRectangle {
		RoundedRectangle(cornerRadius: 22, style: .continuous)
	}

	@ViewBuilder
	func body(content: Content) -> some View {
		if #available(iOS 26, *) {
			content.glassEffect(.regular, in: shape)
		} else {
			// Deployment target is iOS 16, so pre-26 needs a real backdrop of its
			// own — without one the header reads as loose text over the content.
			content.background(.regularMaterial, in: shape)
		}
	}
}

struct DownloadItemView: View {
	let download: Download
	@State private var progress: Double = 0
	@State private var bytesDownloaded: Int64 = 0
	@State private var totalBytes: Int64 = 0
	@State private var unpackageProgress: Double = 0
	
	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			Text(download.fileName)
				.font(.subheadline)
				.lineLimit(1)
			
			ProgressView(value: overallProgress)
				.progressViewStyle(.linear)
			
			HStack {
				Text(verbatim: "\(Int(overallProgress * 100))%")
					.contentTransition(.numericText())
				Spacer()
				if totalBytes > 0 {
					Text(verbatim: "\($bytesDownloaded.wrappedValue.formattedByteCount) / \(totalBytes.formattedByteCount)")
						.contentTransition(.numericText())
				}
			}
			.font(.caption)
			.foregroundColor(.secondary)
		}
		.padding(.vertical, 4)
		.onReceive(download.$progress) { self.progress = $0 }
		.onReceive(download.$bytesDownloaded) { self.bytesDownloaded = $0 }
		.onReceive(download.$totalBytes) { self.totalBytes = $0 }
		.onReceive(download.$unpackageProgress) { self.unpackageProgress = $0 }
	}
	
	private var overallProgress: Double {
		download.onlyArchiving
			? unpackageProgress
			: (0.3 * unpackageProgress) + (0.7 * progress)
	}
}
