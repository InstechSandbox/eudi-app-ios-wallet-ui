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
@preconcurrency import KeychainAccess

public protocol KeyChainWrapper {
  var value: String { get }
}

public protocol KeyChainController: Sendable {
  func storeValue(key: KeyChainWrapper, value: String)
  func storeValue(key: KeyChainWrapper, value: Data)
  func getValue(key: KeyChainWrapper) -> String?
  func getData(key: KeyChainWrapper) -> Data?
  func removeObject(key: KeyChainWrapper)
  func validateKeyChainBiometry() throws
  func clearKeyChainBiometry()
  func clear()
}

final class KeyChainControllerImpl: KeyChainController {

  private let biometryKey = "eu.europa.ec.euidi.biometric.access"
  private let configLogic: ConfigLogic
  private let keyChain: Keychain
  private let serviceName: String
  private let accessGroupName: String?

  public init(configLogic: ConfigLogic) {
    self.configLogic = configLogic
    let accessGroup = configLogic.keyChainConfig.keychainAccessGroup
    let service = configLogic.keyChainConfig.documentStorageServiceName
    self.serviceName = service
    self.accessGroupName = accessGroup
    if let accessGroup, !accessGroup.isEmpty {
      keyChain = Keychain(
        service: service,
        accessGroup: accessGroup
      )
      .accessibility(.afterFirstUnlock)
    } else {
      keyChain = Keychain(service: service)
        .accessibility(.afterFirstUnlock)
    }
    debugLogKeychainContext(action: "init", key: nil, hasValue: nil)
  }

  public func storeValue(key: KeyChainWrapper, value: String) {
    do {
      try keyChain.set(value, key: key.value)
      let storedValue = try keyChain.getString(key.value)
      debugLogKeychainContext(action: "store", key: key.value, hasValue: storedValue != nil)
    } catch {
      debugLogKeychainError(action: "store", key: key.value, error: error)
    }
  }

  public func storeValue(key: KeyChainWrapper, value: Data) {
    do {
      try keyChain.set(value, key: key.value)
      let storedValue = try keyChain.getData(key.value)
      debugLogKeychainContext(action: "storeData", key: key.value, hasValue: storedValue != nil)
    } catch {
      debugLogKeychainError(action: "storeData", key: key.value, error: error)
    }
  }

  public func getValue(key: KeyChainWrapper) -> String? {
    do {
      let value = try keyChain.getString(key.value)
      debugLogKeychainContext(action: "get", key: key.value, hasValue: value != nil)
      return value
    } catch {
      debugLogKeychainError(action: "get", key: key.value, error: error)
      return nil
    }
  }

  func getData(key: KeyChainWrapper) -> Data? {
    do {
      return try keyChain.getData(key.value)
    } catch {
      debugLogKeychainError(action: "getData", key: key.value, error: error)
      return nil
    }
  }

  public func removeObject(key: KeyChainWrapper) {
    do {
      try keyChain.remove(key.value)
      debugLogKeychainContext(action: "remove", key: key.value, hasValue: nil)
    } catch {
      debugLogKeychainError(action: "remove", key: key.value, error: error)
    }
  }

  public func validateKeyChainBiometry() throws {
    try setBiometricKey()
    try isBiometricKeyValid()
  }

  public func clearKeyChainBiometry() {
    try? self.keyChain.remove(self.biometryKey)
  }

  public func clear() {
    try? keyChain.removeAll()
    debugLogKeychainContext(action: "clear", key: nil, hasValue: nil)
  }

  private func debugLogKeychainContext(action: String, key: String?, hasValue: Bool?) {
    #if DEBUG && targetEnvironment(simulator)
    guard key == nil || key == "devicePin" else {
      return
    }
    NSLog(
      "[KeychainDebug] action=%@ key=%@ hasValue=%@ service=%@ accessGroup=%@ bundleID=%@ bundlePath=%@",
      action,
      key ?? "<nil>",
      hasValue.map { $0 ? "true" : "false" } ?? "n/a",
      serviceName,
      accessGroupName ?? "<nil>",
      Bundle.main.bundleIdentifier ?? "<nil>",
      Bundle.main.bundlePath
    )
    #endif
  }

  private func debugLogKeychainError(action: String, key: String, error: Error) {
    #if DEBUG && targetEnvironment(simulator)
    guard key == "devicePin" else {
      return
    }
    NSLog(
      "[KeychainDebug] action=%@ key=%@ error=%@ service=%@ accessGroup=%@ bundleID=%@ bundlePath=%@",
      action,
      key,
      String(describing: error),
      serviceName,
      accessGroupName ?? "<nil>",
      Bundle.main.bundleIdentifier ?? "<nil>",
      Bundle.main.bundlePath
    )
    #endif
  }
}

private extension KeyChainControllerImpl {
  func setBiometricKey() throws {
    try self.keyChain
      .accessibility(
        .whenPasscodeSetThisDeviceOnly,
        authenticationPolicy: [.biometryAny]
      )
      .set(UUID().uuidString, key: self.biometryKey)
  }

  func isBiometricKeyValid() throws {

    let item = try self.keyChain
      .get(self.biometryKey)

    if item != nil {
      clearKeyChainBiometry()
    }
  }
}
