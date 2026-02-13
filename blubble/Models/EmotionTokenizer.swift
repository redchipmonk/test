//
//  EmotionTokenizer.swift
//  blubble
//
//  Created by Jeffrey Song on 2/13/26.
//

import Foundation
import Tokenizers
import Hub

class EmotionTokenizer {
    private var tokenizer: Tokenizer?
    
    func load() async throws {
        let bundleURL = Bundle.main.bundleURL
        self.tokenizer = try await AutoTokenizer.from(modelFolder: bundleURL)
    }
    
    func tokenize(_ text: String) -> (inputIds: [Int32], attentionMask: [Int32])? {
        guard let tokenizer = tokenizer else { return nil }
        let ids = tokenizer.encode(text: text)
        let mask = ids.map { _ in Int32(1) }
        let int32Ids = ids.map { Int32($0) }
            
        return (int32Ids, mask)
    }
}
