//
//  CertificateTier.swift
//  TrainingKit
//

/// A grade of a certificate, and with the same numbering a level of ship mastery.
///
/// Mastery level `N` of a ship means every certificate it lists at grade `N`. `rawValue` is the
/// SDE value (0…4); the game shows one more ("Mastery I" is `basic`), see `displayNumber`.
public enum CertificateTier: Int, CaseIterable, Sendable, Hashable, Comparable {
    case basic = 0
    case standard = 1
    case improved = 2
    case advanced = 3
    case elite = 4

    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }

    /// The number the game writes as a Roman numeral: 1…5.
    public var displayNumber: Int { rawValue + 1 }

    /// The next grade up, `nil` past `elite`.
    public var next: CertificateTier? { CertificateTier(rawValue: rawValue + 1) }
}
