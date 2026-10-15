//
//  ContentView.swift
//  OdysseyProject
//
//  Created by Claudia Garofalo on 28/09/2026.
//

import SwiftUI
import Foundation
import AVFoundation
import Vision
import Translation

struct ContentView: View {
    @State private var panel = UIImage(named: "SpidermanPanel")
    @State private var translationConfig: TranslationSession.Configuration?
    @State private var blocks: [TextBlock] = []

    var body: some View {
        VStack {
            ZStack {
                Image("SpidermanPanel").resizable()

                GeometryReader { geometry in
                    ForEach(blocks) { block in
                        ForEach(block.lines) { line in
                            let rect = CGRect(
                                x: line.boundingBox.origin.x * geometry.size.width,
                                y: line.boundingBox.origin.y * geometry.size.height,
                                width: line.boundingBox.size.width * geometry.size.width,
                                height: line.boundingBox.size.height * geometry.size.height
                            )
                            
                            if let translated = line.translatedText {
                                Rectangle()
                                    .foregroundStyle(Color.white)
                                    .frame(width: rect.width, height: rect.height)
                                    .position(x: rect.midX, y: rect.midY)
                                
                                Text(line.translatedText ?? "")
                                    .bold()
                                    .foregroundStyle(Color.black)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.3)
                                    .frame(width: rect.width, height: rect.height)
                                    .position(x: rect.midX, y: rect.midY)
                            }
                        }
                    }
                }
            }
            .aspectRatio((panel?.size.width)! / (panel?.size.height)!, contentMode: .fit)

            HStack {
                Button {
                    textRecognition(image: panel!)
                } label: {
                    Image(systemName: "translate").font(.title)
                }
                
                Button {
                    blocks.removeAll()
                } label: {
                    Image(systemName: "arrow.uturn.backward.circle").font(.title)
                }.disabled(blocks.isEmpty)
            }
        }
        .translationTask(translationConfig) { session in
            do {
                try await session.prepareTranslation()

                let requests = blocks.map {
                    TranslationSession.Request(sourceText: $0.fullText,
                                               clientIdentifier: $0.id.uuidString)
                }

                let responses = try await session.translations(from: requests)

                await MainActor.run {
                    for response in responses {
                        guard let b = blocks.firstIndex(where: { $0.id.uuidString == response.clientIdentifier })
                        else { continue }

                        let pieces = distribute(response.targetText, over: blocks[b].lines)
                        for (l, piece) in pieces.enumerated() {
                            blocks[b].lines[l].translatedText = piece
                        }
                    }
                }
            } catch {
                print("Translation error: \(error)")
            }
        }
    }

    public func textRecognition(image: UIImage) {
        guard let cgImage = panel?.cgImage else { return }
        blocks.removeAll()

        let request = VNRecognizeTextRequest { request, error in
            guard let results = request.results as? [VNRecognizedTextObservation] else { return }

            var tempItems: [RecognizedTextItem] = []
            for observation in results {
                guard let readText = observation.topCandidates(1).first?.string else { continue }
                let box = observation.boundingBox
                let convertedBox = CGRect(x: box.origin.x,
                                          y: 1.0 - box.origin.y - box.size.height,
                                          width: box.size.width,
                                          height: box.size.height)
                tempItems.append(RecognizedTextItem(text: readText, boundingBox: convertedBox))
            }

            DispatchQueue.main.async {
                self.blocks = groupIntoBlocks(tempItems)     // ← il raggruppamento avviene qui

                if self.translationConfig == nil {
                    self.translationConfig = TranslationSession.Configuration(
                        source: Locale.Language(identifier: "en"),
                        target: Locale.Language(identifier: "it"))
                } else {
                    self.translationConfig?.invalidate()
                }
            }
        }

        request.recognitionLanguages = ["en", "it"]
        request.recognitionLevel = .accurate

        do {
            try VNImageRequestHandler(cgImage: cgImage, options: [:]).perform([request])
        } catch {
            print("Errore durante l'analisi: \(error)")
        }
    }
    
    func groupIntoBlocks(_ items: [RecognizedTextItem]) -> [TextBlock] {
        let sorted = items.sorted { $0.boundingBox.minY < $1.boundingBox.minY }

        var blocks: [TextBlock] = []

        for item in sorted {
            let box = item.boundingBox

            let index = blocks.firstIndex { block in
                guard let last = block.lines.last else { return false }
                let lastBox = last.boundingBox

                let verticalGap = box.minY - lastBox.maxY
                let lineHeight = max(box.height, lastBox.height)
                let closeVertically = verticalGap < lineHeight * 0.8

                let blockBox = block.boundingBox
                let overlapsHorizontally = box.minX < blockBox.maxX && box.maxX > blockBox.minX

                return closeVertically && overlapsHorizontally
            }

            if let index {
                blocks[index].lines.append(item)
            } else {
                blocks.append(TextBlock(lines: [item]))
            }
        }
        return blocks
    }
    
    func distribute(_ translated: String, over lines: [RecognizedTextItem]) -> [String] {
        let words = translated.split(separator: " ").map(String.init)
        let totalOriginal = max(1, lines.reduce(0) { $0 + $1.text.count })
        let totalTranslated = Double(translated.count)

        var result: [String] = []
        var wordIndex = 0

        for (i, line) in lines.enumerated() {
            if i == lines.count - 1 {
                result.append(words[wordIndex...].joined(separator: " "))
                break
            }

            let target = Double(line.text.count) / Double(totalOriginal) * totalTranslated

            var current = ""
            while wordIndex < words.count {
                let candidate = current.isEmpty ? words[wordIndex] : current + " " + words[wordIndex]
                if !current.isEmpty && abs(Double(candidate.count) - target) > abs(Double(current.count) - target) {
                    break
                }
                current = candidate
                wordIndex += 1
            }
            result.append(current)
        }
        return result
    }
}

#Preview {
    ContentView()
}
