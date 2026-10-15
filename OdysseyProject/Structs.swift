//
//  RecognizedTextItem.swift
//  OdysseyProject
//
//  Created by Claudia Garofalo on 01/10/2026.
//

import Foundation
internal import CoreGraphics

struct RecognizedTextItem: Identifiable {
    let id = UUID()
    let text: String
    let boundingBox: CGRect //coordinates of the recognized text
    var translatedText: String?
}

struct TextBlock: Identifiable {
    let id = UUID()
    var lines: [RecognizedTextItem]
    
    var fullText: String {
        lines.map { $0.text }.joined(separator: " ")
    }
    
    var boundingBox: CGRect {
        lines.dropFirst().reduce(lines.first?.boundingBox ?? .zero) { $0.union($1.boundingBox) }
    }
}
