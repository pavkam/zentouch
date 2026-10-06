// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import Foundation
import ZenTouchCore
import ZenTouchMac

func bundledModelCatalogSeparatesVerifiedSupport() throws {
    let catalog = try ModelCatalog.loadBundled()
    try expect(!catalog.supportedModels.isEmpty && catalog.models.count > catalog.supportedModels.count)
    for model in catalog.models {
        try expect(catalog.model(matchingDisplayName: "ASUS \(model.model)") == model)
        try expect((model.status == .verified) == model.isSupported)
        if model.status == .unverified { try expect(model.controllerProfile == nil) }
    }
}

func modelNamesRequireExactTokensAndRejectAmbiguity() throws {
    let catalog = try ModelCatalog.loadBundled()
    let verified = try require(catalog.supportedModels.first)
    let candidate = try require(catalog.models.first { $0.status == .unverified })
    try expect(catalog.model(matchingDisplayName: "asus (\(verified.model.lowercased()))") == verified)
    try expect(catalog.model(matchingDisplayName: verified.model + "2") == nil)
    try expect(catalog.model(matchingDisplayName: "X" + verified.model) == nil)
    try expect(catalog.model(matchingDisplayName: String(verified.model.dropLast()))?.isSupported != true)
    try expect(catalog.model(matchingDisplayName: verified.model + "/" + candidate.model) == nil)
    try expect(catalog.model(matchingDisplayName: verified.model + " " + verified.model) == verified)
}

func candidateModelsNeverBecomeAutomaticInputTargets() throws {
    let catalog = try ModelCatalog.loadBundled()
    let supported = ScreenTarget(id: 1, name: try require(catalog.supportedModels.first?.model))
    let candidate = ScreenTarget(id: 2, name: try require(catalog.models.first { $0.status == .unverified }?.model))
    let unrelated = ScreenTarget(id: 3, name: "Built-in Retina Display")
    try expect(candidate.model != nil && !candidate.isSupportedTouchDisplay)
    try expect(DisplaySelection.resolve(id: nil, uuid: nil, in: [candidate, unrelated]) == nil)
    try expect(DisplaySelection.resolve(id: nil, uuid: nil, in: [candidate, unrelated, supported]) == supported)
    // A stale saved UUID may not silently fall back to another catalog model.
    try expect(DisplaySelection.resolve(id: 1, uuid: "unattached", in: [supported]) == nil)
}

func catalogRejectsInvalidAndConflictingEntries() throws {
    let valid: [String: Any] = [
        "model": "TEST100", "family": "Synthetic", "displayNames": ["TEST100"], "touchPoints": 10,
        "source": "https://www.asus.com/", "status": "verified", "controllerProfile": DeviceProfile.identifier,
    ]
    func data(_ models: [[String: Any]], version: Int = 1) throws -> Data {
        try JSONSerialization.data(withJSONObject: ["schemaVersion": version, "models": models])
    }
    try expect(try ModelCatalog(data: data([valid])).supportedModels.count == 1)
    try expectThrows(ModelCatalog.CatalogError.self) { try ModelCatalog(data: data([], version: 1)) }
    try expectThrows(ModelCatalog.CatalogError.self) { try ModelCatalog(data: data([valid], version: 2)) }
    try expectThrows(ModelCatalog.CatalogError.self) { try ModelCatalog(data: data([valid, valid])) }
    for (key, value) in [
        ("touchPoints", 11 as Any), ("displayNames", [""] as Any), ("source", "https://example.com/" as Any),
        ("source", "http://www.asus.com/" as Any), ("controllerProfile", "unknown" as Any),
        ("controllerProfile", NSNull() as Any), ("status", "unverified" as Any),
    ] {
        var invalid = valid
        invalid[key] = value
        try expectThrows(ModelCatalog.CatalogError.self) { try ModelCatalog(data: data([invalid])) }
    }
    var overlapping = valid
    overlapping["model"] = "TEST101"
    try expectThrows(ModelCatalog.CatalogError.self) { try ModelCatalog(data: data([valid, overlapping])) }
}
