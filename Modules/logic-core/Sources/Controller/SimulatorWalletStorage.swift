/*
 * Copyright (c) 2025 European Commission
 *
 * Licensed under the EUPL, Version 1.2 or - as soon they will be approved by the European
 * Commission - subsequent versions of the EUPL (the "Licence"); You may not use this work
 * except in compliance with the Licence.
 *
 * You may obtain a copy of the Licence at:
 * https://joinup.ec.europa.eu/software/page/eupl
 *
 * Unless required by applicable law or agreed to in writing, software distributed under
 * the Licence is distributed on an "AS IS" basis, WITHOUT WARRANTIES OR CONDITIONS OF
 * ANY KIND, either express or implied. See the Licence for the specific language
 * governing permissions and limitations under the Licence.
 */
import Foundation
import MdocDataModel18013
import WalletStorage
import logic_business

#if targetEnvironment(simulator)
private enum SimulatorWalletStorageError: Error {
  case documentAlreadyExists
  case documentNotFound
  case documentCredentialNotFound
}

private enum SimulatorWalletStoragePersistence {

  private static let encoder = PropertyListEncoder()
  private static let decoder = PropertyListDecoder()

  static let secureKeysURL = storageDirectory.appendingPathComponent("secure-keys.plist")

  private static let storageDirectory: URL = {
    let namespace = Bundle.getMainAppBundleID().nilIfEmpty
      ?? Bundle.main.bundleIdentifier?.nilIfEmpty
      ?? "eu.europa.ec.euidi.simulator"

    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("eudi-wallet-simulator-storage", isDirectory: true)
      .appendingPathComponent(namespace, isDirectory: true)

    try? FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )

    return directory
  }()

  static func loadSecureKeys() -> PersistedSecureKeys {
    load(PersistedSecureKeys.self, from: secureKeysURL) ?? PersistedSecureKeys()
  }

  static func saveSecureKeys(_ secureKeys: PersistedSecureKeys) {
    save(secureKeys, to: secureKeysURL)
  }

  private static func load<T: Decodable>(_ type: T.Type, from url: URL) -> T? {
    guard let data = try? Data(contentsOf: url) else {
      return nil
    }

    return try? decoder.decode(type, from: data)
  }

  private static func save<T: Encodable>(_ value: T, to url: URL) {
    guard let data = try? encoder.encode(value) else {
      return
    }

    try? data.write(to: url, options: .atomic)
  }
}

private struct PersistedSecureKeys: Codable {
  var keyInfoStorage: [String: [String: Data]] = [:]
  var keyDataStorage: [String: [String: Data]] = [:]
}

actor SimulatorDataStorageService: DataStorageService {

  private var documents: [String: [WalletStorage.Document]] = [:]

  func loadDocument(id: String, status: DocumentStatus) async throws -> WalletStorage.Document? {
    let key = makeKey(id: id, status: status)
    guard let docs = documents[key], !docs.isEmpty else { return nil }

    let placeholder = docs[0]
    guard let keyInfo = DocKeyInfo(from: placeholder.docKeyInfo) else { return placeholder }

    let secureArea = SecureAreaRegistry.shared.get(name: keyInfo.secureAreaName)
    let keyBatchInfo = try await secureArea.getKeyBatchInfo(id: id)

    guard keyBatchInfo.batchSize > 1 else {
      return keyBatchInfo.credentialPolicy == .oneTimeUse && keyBatchInfo.usedCounts[0] > 0 ? nil : placeholder
    }

    guard let indexToUse = keyBatchInfo.findIndexToUse() else { return nil }
    let batchKey = makeKey(id: "\(id)_\(indexToUse)", status: status)
    guard let batchDocs = documents[batchKey], let document = batchDocs.first else { return nil }

    var mutableDocument = document
    mutableDocument.keyIndex = indexToUse
    mutableDocument.docKeyInfo = placeholder.docKeyInfo
    return mutableDocument
  }

  func loadDocumentMetadata(id: String) async throws -> DocMetadata? {
    let key = makeKey(id: id, status: .issued)
    guard let document = documents[key]?.first else { return nil }
    return DocMetadata(from: document.metadata)
  }

  func loadDocuments(status: DocumentStatus) async throws -> [WalletStorage.Document]? {
    let filteredEntries = documents.filter { key, _ in
      key.hasSuffix(":\(status.rawValue)")
    }

    var documentsById: [String: (key: String, document: WalletStorage.Document)] = [:]

    for (key, storedDocuments) in filteredEntries {
      guard let document = storedDocuments.first else { continue }

      let primaryKey = makeKey(id: document.id, status: status)
      let isPrimaryEntry = key == primaryKey

      guard let existing = documentsById[document.id] else {
        documentsById[document.id] = (key, document)
        continue
      }

      let existingIsPrimaryEntry = existing.key == primaryKey
      let shouldReplace = (isPrimaryEntry && !existingIsPrimaryEntry)
        || (!existingIsPrimaryEntry && !isPrimaryEntry && document.createdAt > existing.document.createdAt)

      if shouldReplace {
        documentsById[document.id] = (key, document)
      }
    }

    let filteredDocuments = documentsById.values.map(\.document)
    return filteredDocuments.isEmpty ? nil : filteredDocuments
  }

  func saveDocument(_ document: WalletStorage.Document, batch: [WalletStorage.Document]?, allowOverwrite: Bool) async throws {
    let key = makeKey(id: document.id, status: document.status)

    if !allowOverwrite && documents[key] != nil {
      throw SimulatorWalletStorageError.documentAlreadyExists
    }

    documents[key] = [document]

    if let batch {
      for (index, batchDocument) in batch.enumerated() {
        let batchKey = makeKey(id: "\(document.id)_\(index)", status: document.status)
        documents[batchKey] = [batchDocument]
      }
    }

  }

  func deleteDocument(id: String, status: DocumentStatus) async throws {
    let key = makeKey(id: id, status: status)
    guard let document = documents[key]?.first else {
      throw SimulatorWalletStorageError.documentNotFound
    }

    let keyInfo = DocKeyInfo(from: document.docKeyInfo)
    documents.removeValue(forKey: key)

    if let keyInfo, status == .issued {
      for index in 0..<keyInfo.batchSize {
        documents.removeValue(forKey: makeKey(id: "\(id)_\(index)", status: status))
      }

      let secureArea = SecureAreaRegistry.shared.get(name: keyInfo.secureAreaName)
      try await secureArea.deleteKeyBatch(id: id, startIndex: 0, batchSize: keyInfo.batchSize)
      try await secureArea.deleteKeyInfo(id: id)
    }
  }

  func deleteDocuments(status: DocumentStatus) async throws {
    let keysToDelete = documents.keys.filter { $0.hasSuffix(":\(status.rawValue)") }

    for key in keysToDelete {
      guard let document = documents[key]?.first else { continue }
      let id = document.id
      documents.removeValue(forKey: key)

      guard let keyInfo = DocKeyInfo(from: document.docKeyInfo), status == .issued else { continue }
      for index in 0..<keyInfo.batchSize {
        documents.removeValue(forKey: makeKey(id: "\(id)_\(index)", status: status))
      }

      let secureArea = SecureAreaRegistry.shared.get(name: keyInfo.secureAreaName)
      try? await secureArea.deleteKeyBatch(id: id, startIndex: 0, batchSize: keyInfo.batchSize)
      try? await secureArea.deleteKeyInfo(id: id)
    }
  }

  func deleteDocumentCredential(id: String, index: Int) async throws {
    let batchKey = makeKey(id: "\(id)_\(index)", status: .issued)
    if documents[batchKey] == nil {
      throw SimulatorWalletStorageError.documentCredentialNotFound
    }
    documents.removeValue(forKey: batchKey)
  }

  private func makeKey(id: String, status: DocumentStatus) -> String {
    "\(id):\(status.rawValue)"
  }
}

actor SimulatorSecureKeyStorage: SecureKeyStorage {

  private var keyInfoStorage: [String: [String: Data]]
  private var keyDataStorage: [String: [String: Data]]

  init() {
    let persisted = SimulatorWalletStoragePersistence.loadSecureKeys()
    self.keyInfoStorage = persisted.keyInfoStorage
    self.keyDataStorage = persisted.keyDataStorage
  }

  func readKeyInfo(id: String) async throws -> [String: Data] {
    keyInfoStorage[id] ?? [:]
  }

  func readKeyData(id: String, index: Int) async throws -> [String: Data] {
    keyDataStorage[makeKey(id: id, index: index)] ?? [:]
  }

  func writeKeyInfo(id: String, dict: [String: Data]) async throws {
    keyInfoStorage[id] = dict
    persistSecureKeys()
  }

  func writeKeyDataBatch(id: String, startIndex: Int, dicts: [[String: Data]], keyOptions: KeyOptions?) async throws {
    for (offset, dict) in dicts.enumerated() {
      keyDataStorage[makeKey(id: id, index: startIndex + offset)] = dict
    }
    persistSecureKeys()
  }

  func deleteKeyBatch(id: String, startIndex: Int, batchSize: Int) async throws {
    for index in startIndex..<(startIndex + batchSize) {
      keyDataStorage.removeValue(forKey: makeKey(id: id, index: index))
    }
    persistSecureKeys()
  }

  func deleteKeyInfo(id: String) async throws {
    keyInfoStorage.removeValue(forKey: id)
    persistSecureKeys()
  }

  private func makeKey(id: String, index: Int) -> String {
    "\(id)_\(index)"
  }

  private func persistSecureKeys() {
    SimulatorWalletStoragePersistence.saveSecureKeys(
      PersistedSecureKeys(
        keyInfoStorage: keyInfoStorage,
        keyDataStorage: keyDataStorage
      )
    )
  }
}

private extension String {
  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}
#endif