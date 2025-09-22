//
//  Habit+Extensions.swift
//  joy_thief
//
//  Created by Jiarong Zhang on 4/30/25.
//

extension Habit {
    /// We’ll shield apps only if the habit supplies a non-empty list
    var requiresShielding: Bool { !(restrictedApps?.isEmpty ?? true) }
}
