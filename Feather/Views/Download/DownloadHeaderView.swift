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
				.padding(.horizontal, 16)
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
	func downloadHeaderInset() -> some View {
		modifier(DownloadHeaderPresentation(downloadManager: DownloadManager.shared))
	}
}

/// Places the header above the navigation bar without starving its glass.
///
/// Apple's rule is that Liquid Glass "blurs content behind it", so the header
/// only lenses where something renders underneath. Stacking it above the tab
/// view puts it where nothing does, and the effect collapses to a flat fill --
/// a FLEX capture of that build caught it as a `SwiftUI._UIInheritedView` on an
/// `SDFLayer` with `opaque = YES` and no `_UILiquidLensView` beneath it.
///
/// So rather than move the header somewhere content already reaches, bring the
/// content up to the header: grow the hosting controller's top safe area by the
/// header's height. UIKit propagates that inset, so the navigation bar lays out
/// below the header instead of under it, while the list keeps its frame at the
/// top of the window and merely insets its content -- exactly how a list scrolls
/// under a navigation bar. The header then has live content behind it and the
/// same `glassEffect` renders as a real lens, with the layout unchanged.
private struct DownloadHeaderPresentation: ViewModifier {
	@ObservedObject var downloadManager: DownloadManager
	@State private var headerHeight: CGFloat = 0
	@State private var statusBarInset: CGFloat = 0

	private var isShowing: Bool { !downloadManager.manualDownloads.isEmpty }

	func body(content: Content) -> some View {
		content
			.overlay(alignment: .top) {
				DownloadHeaderView(downloadManager: downloadManager)
					.background {
						GeometryReader { proxy in
							Color.clear.preference(
								key: DownloadHeaderHeightKey.self,
								value: proxy.size.height
							)
						}
					}
					// Sit against the status bar, not the grown safe area. Without
					// this the header slides down by the very inset it asks for,
					// landing back on the navigation bar it was meant to clear.
					.padding(.top, statusBarInset)
					.ignoresSafeArea(.container, edges: .top)
			}
			.onPreferenceChange(DownloadHeaderHeightKey.self) { headerHeight = $0 }
			.background(
				RootSafeAreaTopInset(
					inset: isShowing ? headerHeight : 0,
					statusBarInset: $statusBarInset
				)
				.frame(width: 0, height: 0)
			)
	}
}

private struct DownloadHeaderHeightKey: PreferenceKey {
	static var defaultValue: CGFloat = 0
	static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
		value = max(value, nextValue())
	}
}

/// Adds to the root view controller's top safe area.
///
/// `safeAreaInset`/`safeAreaBar` are not usable here: they adjust the SwiftUI
/// safe area for their own children, but the navigation bar positions against
/// the window's, so it never moves and the header ends up on top of it.
/// `additionalSafeAreaInsets` changes the UIKit safe area the bar actually
/// reads, which is what lets the bar drop below the header.
private struct RootSafeAreaTopInset: UIViewRepresentable {
	let inset: CGFloat
	@Binding var statusBarInset: CGFloat

	func makeUIView(context: Context) -> UIView {
		let view = UIView()
		view.isUserInteractionEnabled = false
		return view
	}

	func updateUIView(_ uiView: UIView, context: Context) {
		let inset = self.inset
		DispatchQueue.main.async {
			guard let window = uiView.window else { return }

			// The window's own inset, which additionalSafeAreaInsets does not
			// touch, so it stays the true status bar height and gives the header
			// something stable to sit against.
			let top = window.safeAreaInsets.top
			if abs(statusBarInset - top) > 0.5 {
				statusBarInset = top
			}

			guard let root = window.rootViewController else { return }
			guard abs(root.additionalSafeAreaInsets.top - inset) > 0.5 else { return }
			root.additionalSafeAreaInsets.top = inset
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
			// Inside a GlassEffectContainer, per Apple: "each view with the
			// glassEffect(_:in:) modifier renders with the effects behind it",
			// and effects "render differently depending on container presence".
			// Standalone, the modifier only blurs -- the lensing needs the
			// container's rendering pass.
			GlassEffectContainer {
				content.glassEffect(.regular, in: shape)
			}
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
