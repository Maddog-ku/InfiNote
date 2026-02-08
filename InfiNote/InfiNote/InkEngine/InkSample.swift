//
//  InkSample.swift
//  InfiNote
//

import CoreGraphics
import Foundation

struct InkSample {
    var location: CGPoint
    var timestamp: TimeInterval
    var normalizedForce: CGFloat
    var azimuth: CGFloat
    var altitude: CGFloat
    var estimationIndex: NSNumber?
    var isPredicted: Bool
}
