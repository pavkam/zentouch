// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import Foundation

public struct TouchDisplayModel: Decodable, Equatable {
    public enum Status: String, Decodable { case verified, unverified }
    public let model: String
    public let family: String
    public let displayNames: [String]
    public let touchPoints: Int
    public let source: URL
    public let status: Status
    public let controllerProfile: String?
    public var isSupported: Bool { status == .verified && controllerProfile == DeviceProfile.identifier }
}

/// The data file owns model names and support status. ASUS specifications do
/// not establish compatibility with our captured controller protocol.
public struct ModelCatalog {
    public enum CatalogError: LocalizedError {
        case missingOrInvalid, unsupportedOrEmpty, invalidEntry, invalidAlias
        public var errorDescription: String? {
            switch self {
            case .missingOrInvalid: return "ZenTouch's model catalog is missing or invalid. Reinstall the app."
            case .unsupportedOrEmpty: return "Unsupported or empty model catalog."
            case .invalidEntry: return "Invalid model catalog entry."
            case .invalidAlias: return "Invalid or duplicate model display name."
            }
        }
    }
    public static let current = try? loadBundled()
    public let models: [TouchDisplayModel]
    public var supportedModels: [TouchDisplayModel] { models.filter(\.isSupported) }
    private let aliases: [String: TouchDisplayModel]

    public static func loadBundled() throws -> ModelCatalog {
        guard let data = HardwareResources.data(named: "supported-models", extension: "json") else {
            throw CatalogError.missingOrInvalid
        }
        do { return try ModelCatalog(data: data) } catch {
            throw CatalogError.missingOrInvalid
        }
    }

    public init(data: Data) throws {
        struct Document: Decodable {
            let schemaVersion: Int
            let models: [TouchDisplayModel]
        }
        let document = try JSONDecoder().decode(Document.self, from: data)
        guard document.schemaVersion == 1, !document.models.isEmpty else {
            throw CatalogError.unsupportedOrEmpty
        }
        var names: Set<String> = []
        var aliases: [String: TouchDisplayModel] = [:]
        for model in document.models {
            let host = model.source.host?.lowercased() ?? ""
            guard !model.model.isEmpty, names.insert(model.model.uppercased()).inserted,
                !model.family.isEmpty, !model.displayNames.isEmpty, (1...10).contains(model.touchPoints),
                model.source.scheme == "https", host == "asus.com" || host.hasSuffix(".asus.com"),
                model.status == .verified ? model.isSupported : model.controllerProfile == nil
            else {
                throw CatalogError.invalidEntry
            }
            for alias in model.displayNames {
                let key = alias.uppercased()
                guard !key.isEmpty, key.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }),
                    aliases.updateValue(model, forKey: key) == nil
                else {
                    throw CatalogError.invalidAlias
                }
            }
        }
        models = document.models
        self.aliases = aliases
    }

    public func model(matchingDisplayName name: String) -> TouchDisplayModel? {
        let tokens = name.uppercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
        let matches = tokens.compactMap { aliases[$0] }
        guard let first = matches.first, matches.allSatisfy({ $0.model == first.model }) else { return nil }
        return first
    }
}
