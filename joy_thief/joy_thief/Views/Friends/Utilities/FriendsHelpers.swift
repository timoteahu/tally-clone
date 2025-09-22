////
//  FriendsHelpers.swift
//  joy_thief
//
//  Created by RefactorBot on 2025-06-18.
//
//  Shared helper functions for FriendsView.
//

import Foundation

// Shared helper to derive a user's initials from their full name. Kept here so all Friends-related views can access it without importing the massive FriendsView file.
func initials(for name: String) -> String {
    let comps = name.split(separator: " ")
    let initials = comps.prefix(2).compactMap { $0.first }.map { String($0) }
    return initials.joined().uppercased()
} 
