//
//  Item.swift
//  Newston
//
//  Created by Martin Ingvar Kofoed Jensen on 28/04/2026.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
