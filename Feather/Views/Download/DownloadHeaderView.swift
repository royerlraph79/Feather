//
//  DownloadHeaderView.swift
//  Feather
//
//  Created by samara on 16.05.2025.
//

import SwiftUI
import Combine
import NimbleExtensions

/// The header's contents on their own, with no surface or placement.
///
/// Shared by both presentations: the pre-26 overlay, which supplies its own
/// glass, and the iOS 26 tab view accessory, where the system supplies it.
struct DownloadHeaderContent: View {
	@ObservedObject var downloadManager: DownloadManager

	var body: some View {
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
	}
}

struct DownloadHeaderView: View {
	@ObservedObject var downloadManager: DownloadManager

	var body: some View {
		ZStack {
			if !downloadManager.manualDownloads.isEmpty {
				DownloadHeaderContent(downloadManager: downloadManager)
				.padding(.horizontal, 16)
				.padding(.vertical, 12)
				// Keeps its own surface. Dropping it and letting safeAreaBar's blur
				// carry the header does avoid stacking glass, but with the bar
				// pinned over the navigation row the bare text then collides with
				// the title and the toolbar buttons. The card is what separates the
				// two rows.
				.modifier(DownloadHeaderSurface())
				.padding(.leading, 16)
				// Keep the trailing toolbar buttons tappable. That platter is
				// anchored to the trailing edge -- 20pt inset, ~102pt wide for
				// Library's refresh + add pair -- so its leading edge lands about
				// 122pt from the right whatever the screen width is. 130 clears it
				// with a gap, and works out the same on every device.
				.padding(.trailing, 130)
				.padding(.top, 4)
				.transition(.move(edge: .top).combined(with: .opacity))
			}
		}
		.animation(.spring(), value: downloadManager.manualDownloads.count)
	}
}

extension View {
	/// Floats the download header over this view, for releases without
	/// `tabViewBottomAccessory`.
	///
	/// Overlay rather than safeAreaInset or safeAreaBar: both of those put the
	/// header where the tab content does not reach, and a backdrop with nothing
	/// rendered under it blurs to a flat fill. A FLEX capture of the safeAreaBar
	/// build caught exactly that -- the header as a bare
	/// `SwiftUI._UIInheritedView` on an `SDFLayer` with `opaque = YES` and no
	/// `_UILiquidLensView` beneath it, while the tab bar and navigation platters
	/// in the same tree had theirs. Overlaid, the list renders behind it and the
	/// same modifier draws as real Liquid Glass.
	@ViewBuilder
	func downloadHeaderInset() -> some View {
		if #available(iOS 26, *) {
			// iOS 26 uses the tab view's bottom accessory instead, which is the
			// one placement that gets a system-supplied backdrop without covering
			// anything.
			self
		} else {
			overlay(alignment: .top) {
				DownloadHeaderView(downloadManager: DownloadManager.shared)
			}
		}
	}

	/// Installs the download header as the tab view's bottom accessory (iOS 26).
	///
	/// This is the slot Music's mini-player uses. The system draws the glass and
	/// scrolls tab content beneath it, so the header refracts without sitting on
	/// top of the navigation bar the way the overlay has to.
	@ViewBuilder
	func downloadAccessory() -> some View {
		if #available(iOS 26, *) {
			modifier(DownloadAccessory(downloadManager: DownloadManager.shared))
		} else {
			self
		}
	}
}

@available(iOS 26, *)
private struct DownloadAccessory: ViewModifier {
	@ObservedObject var downloadManager: DownloadManager

	// No surface of its own: the accessory is already a system glass container,
	// and stacking glass on glass is the case the HIG rules out.
	@ViewBuilder
	func body(content: Content) -> some View {
		if #available(iOS 26.1, *) {
			content.tabViewBottomAccessory(isEnabled: !downloadManager.manualDownloads.isEmpty) {
				DownloadHeaderContent(downloadManager: downloadManager)
					.padding(.horizontal, 16)
			}
		} else if !downloadManager.manualDownloads.isEmpty {
			// 26.0 has no isEnabled overload, so only attach the modifier while a
			// download is running -- otherwise it reserves an empty bar above the
			// tab bar for the whole session.
			content.tabViewBottomAccessory {
				DownloadHeaderContent(downloadManager: downloadManager)
					.padding(.horizontal, 16)
			}
		} else {
			content
		}
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
