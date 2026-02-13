//
//  EmotionClassifier.swift
//  blubble
//
//  Created by Jeffrey Song on 2/12/26.
//

import Foundation
import CoreML
    
class EmotionClassifier {
    
    let model: DistilBERTEmotion
    let tokenizer = EmotionTokenizer()
    
    init() {
        do {
            let config = MLModelConfiguration()
            self.model = try DistilBERTEmotion(configuration: config)
            Task {
                print("Trying to load tokenizer...")
                try? await tokenizer.load()
                print("Tokenizer ready")
            }
        } catch {
            fatalError("Failed to load model")
        }
    }
    
    func predictEmotion(for text: String) -> String {
        print("predicting")
        guard let inputs = tokenizer.tokenize(text) else { return "unknown" }
        if let emotion = self.classify(inputIds: inputs.inputIds, attentionMask: inputs.attentionMask) {
            return emotion
        }
        return "unknown"
    }
    
    func classify(inputIds: [Int32], attentionMask: [Int32]) -> String? {
        print("classifying")
        do {
            let size = 128
            let shape = [1, NSNumber(value: size)]
            let inputIdsArr = try MLMultiArray(shape: shape, dataType: .int32)
            let attentionMaskArr = try MLMultiArray(shape: shape, dataType: .int32)
            
            for i in 0..<size {
                inputIdsArr[i] = 0
                attentionMaskArr[i] = 0
            }
            
            for i in 0..<min(inputIds.count, size) {
                inputIdsArr[i] = NSNumber(value: inputIds[i])
                attentionMaskArr[i] = NSNumber(value: attentionMask[i])
            }
            
            let output = try model.prediction(input_ids: inputIdsArr, attention_mask: attentionMaskArr)
            let probabilities = output.linear_37
            return interpretResults(probabilities)
        } catch {
            print("Prediction failed with \(error)")
            return nil
        }
    }
    
    private func interpretResults(_ logits: MLMultiArray) -> String? {
        let labels = ["sadness", "joy", "love", "anger", "fear", "surprise"]
        let count = logits.count
        var bestIndex = 0
        var highest = -Double.infinity
        for i in 0..<count {
            let score = logits[i].doubleValue
            if score > highest {
                highest = score
                bestIndex = i
            }
        }
        if bestIndex < labels.count {
            return labels[bestIndex]
        }
        return nil
    }
}
