//
//  AnnotationColor.swift
//  Pantrix
//
//  The annotation pen palette. Android ships black + yellow; iOS adds red — the canonical "mark this" colour,
//  and yellow alone is invisible on a light screenshot. Defined in the Kit as pure RGB so the choices are
//  tested and stable; the view maps each to a `UIColor` for the PencilKit ink.
//

import Foundation

public enum AnnotationColor: String, CaseIterable, Sendable {
    case red, black, yellow

    /// sRGB components in 0…1. Alpha is always 1 (opaque ink).
    public var rgb: (red: Double, green: Double, blue: Double) {
        switch self {
        case .red:    return (0.90, 0.16, 0.22)
        case .black:  return (0.0, 0.0, 0.0)
        case .yellow: return (1.0, 0.80, 0.0)
        }
    }

    /// The pen colour a fresh editor starts on.
    public static let `default`: AnnotationColor = .red
}
