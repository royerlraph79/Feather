//
//  SigningOptionsDylibSharedView.swift
//  Feather
//
//  Created by samara on 19.04.2025.
//

import SwiftUI
import NimbleViews
import ZsignSwift

// MARK: - View
struct SigningDylibView: View {
    @State private var _dylibs: [String] = []
    @State private var _systemDylibs: [String] = []

    var app: AppInfoPresentable
    @Binding var options: Options?

    var body: some View {
        NBList(.localized("Dylibs"), type: .list) {
            Section {
                ForEach(_dylibs, id: \.self) { dylib in
                    SigningToggleCellView(
                        title: dylib,
                        options: $options,
                        arrayKeyPath: \.disInjectionFiles
                    )
                }
            }
            .disabled(options == nil)

            if !_systemDylibs.isEmpty {
                NBSection("System Dylibs (\(_systemDylibs.count))") {
                    ForEach(_systemDylibs, id: \.self) { dylib in
                        SigningToggleCellView(
                            title: dylib,
                            options: $options,
                            arrayKeyPath: \.disInjectionFiles
                        )
                    }
                }
                .disabled(options == nil)
            }
        }
        .onAppear(perform: _loadDylibs)
    }
}

// MARK: - Extension: View
extension SigningDylibView {
    private func _loadDylibs() {
        guard let path = Storage.shared.getAppDirectory(for: app) else { return }

        let bundle = Bundle(url: path)
        let execPath = path.appendingPathComponent(bundle?.exec ?? "").relativePath

        let allDylibs = Zsign.listDylibs(appExecutable: execPath).map { $0 as String }

        _dylibs = allDylibs.filter {
            $0.hasPrefix("@rpath") || $0.hasPrefix("@executable_path")
        }

        _systemDylibs = allDylibs.filter {
            !$0.hasPrefix("@rpath") && !$0.hasPrefix("@executable_path")
        }
    }
}
