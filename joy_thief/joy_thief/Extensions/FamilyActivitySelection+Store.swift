// //
// //  FamilyActivitySelection+Store.swift
// //  joy_thief
// //
// //  Created by Jiarong Zhang on 4/30/25.
// //

// import Foundation
// import FamilyControls

// /// Persist the user’s last picker result so it can be reused for shielding
// extension FamilyActivitySelection {
//     static var shared: FamilyActivitySelection {
//         get {
//             if let data = UserDefaults.standard.data(forKey: "FamilyActivitySelection"),
//                let sel  = try? JSONDecoder().decode(Self.self, from: data) {
//                 return sel
//             }
//             return FamilyActivitySelection()
//         }
//         set {
//             if let data = try? JSONEncoder().encode(newValue) {
//                 UserDefaults.standard.set(data, forKey: "FamilyActivitySelection")
//             }
//         }
//     }
// }
