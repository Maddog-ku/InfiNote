//
//  ContentView.swift
//  InfiNote
//

import SwiftUI

struct ContentView: View {
#if os(iOS)
    @State private var clearToken: Int = 0
    @State private var backgroundTemplate: CanvasBackgroundTemplate = .lines
    @State private var selectedTool: EditorTool = .pen
    @State private var eraserMode: EraserMode = .stroke
    @State private var eraserSize: Double = 20
    @State private var lassoMoveToken: Int = 0
    @State private var lassoMoveDelta: CGSize = .zero
    @State private var lassoScaleToken: Int = 0
    @State private var lassoScaleFactor: Double = 1
    @State private var lassoDeleteToken: Int = 0
    @State private var lassoMergeToken: Int = 0
    @State private var brushColor: Color = .black
    @State private var brushWidth: Double = 2.2
    @State private var brushOpacity: Double = 1
#endif

    var body: some View {
#if os(iOS)
        NavigationStack {
            VStack(spacing: 0) {
                PencilCanvasRepresentable(
                    clearToken: $clearToken,
                    backgroundTemplate: $backgroundTemplate,
                    tool: $selectedTool,
                    eraserMode: $eraserMode,
                    eraserSize: $eraserSize,
                    lassoMoveToken: $lassoMoveToken,
                    lassoMoveDelta: $lassoMoveDelta,
                    lassoScaleToken: $lassoScaleToken,
                    lassoScaleFactor: $lassoScaleFactor,
                    lassoDeleteToken: $lassoDeleteToken,
                    lassoMergeToken: $lassoMergeToken,
                    color: $brushColor,
                    width: $brushWidth,
                    opacity: $brushOpacity
                )
                .overlay(alignment: .bottom) {
                    VStack(spacing: 10) {
                        Picker("Tool", selection: $selectedTool) {
                            ForEach(EditorTool.allCases) { tool in
                                Text(tool.title).tag(tool)
                            }
                        }
                        .pickerStyle(.segmented)

                        if selectedTool == .eraser {
                            HStack(spacing: 12) {
                                Picker("Mode", selection: $eraserMode) {
                                    ForEach(EraserMode.allCases) { mode in
                                        Text(mode.title).tag(mode)
                                    }
                                }
                                .pickerStyle(.segmented)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Size \(eraserSize, specifier: "%.0f")")
                                        .font(.caption2)
                                    Slider(value: $eraserSize, in: 4...80)
                                }
                            }
                        } else if selectedTool == .lasso {
                            HStack(spacing: 10) {
                                Button("Left") {
                                    lassoMoveDelta = CGSize(width: -18, height: 0)
                                    lassoMoveToken &+= 1
                                }
                                Button("Right") {
                                    lassoMoveDelta = CGSize(width: 18, height: 0)
                                    lassoMoveToken &+= 1
                                }
                                Button("Up") {
                                    lassoMoveDelta = CGSize(width: 0, height: -18)
                                    lassoMoveToken &+= 1
                                }
                                Button("Down") {
                                    lassoMoveDelta = CGSize(width: 0, height: 18)
                                    lassoMoveToken &+= 1
                                }
                                Button("−") {
                                    lassoScaleFactor = 0.92
                                    lassoScaleToken &+= 1
                                }
                                Button("+") {
                                    lassoScaleFactor = 1.08
                                    lassoScaleToken &+= 1
                                }
                                Button("Delete", role: .destructive) {
                                    lassoDeleteToken &+= 1
                                }
                                Button("Merge") {
                                    lassoMergeToken &+= 1
                                }
                            }
                            .buttonStyle(.bordered)
                        } else {
                            HStack(spacing: 14) {
                                ColorPicker("Color", selection: $brushColor, supportsOpacity: false)
                                    .labelsHidden()

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Width \(brushWidth, specifier: "%.1f")")
                                        .font(.caption2)
                                    Slider(value: $brushWidth, in: 1...18)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Opacity \(brushOpacity, specifier: "%.2f")")
                                        .font(.caption2)
                                    Slider(value: $brushOpacity, in: 0.08...1)
                                }
                            }
                        }
                    }
                    .padding(10)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(12)
                }
            }
            .navigationTitle("InfiNote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Picker("Template", selection: $backgroundTemplate) {
                        ForEach(CanvasBackgroundTemplate.allCases) { template in
                            Text(template.title).tag(template)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") {
                        clearToken &+= 1
                    }
                }
            }
        }
#else
        VStack(spacing: 8) {
            Text("InfiNote")
                .font(.title2)
            Text("Apple Pencil ink canvas is available on iPadOS / iOS.")
                .foregroundStyle(.secondary)
        }
        .padding(24)
#endif
    }
}

#Preview {
    ContentView()
}
