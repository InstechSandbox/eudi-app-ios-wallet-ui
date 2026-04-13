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
import EudiRQESUi

public enum AppBuildType: String, Sendable {
  case RELEASE, DEBUG
}

public enum AppBuildVariant: String, Sendable {
  case DEMO, DEV
}

public protocol ConfigLogic: Sendable {

  /**
   * Build type.
   */
  var appBuildType: AppBuildType { get }

  /**
   * Build Variant.
   */
  var appBuildVariant: AppBuildVariant { get }

  /**
   * App version.
   */
  var appVersion: String { get }

  /**
   * RQES Config
   */
  var rqesConfig: EudiRQESUiConfig { get }

  /**
   * Changelog URL
   */
  var changelogUrl: URL? { get }

  /**
   * Local issuer override.
   */
  var localIssuerUrl: URL? { get }

  /**
   * Local issuer client id.
   */
  var localIssuerClientId: String { get }

  /**
   * Local wallet attestation override.
   */
  var localWalletAttestationUrl: URL? { get }

  /**
   * Local verifier override for preregistered OpenID4VP flows.
   */
  var localVerifierUrl: URL? { get }

  /**
   * Local verifier preregistered client id.
   */
  var localVerifierClientId: String? { get }

  /**
   * Hosts allowed to use local self-signed TLS.
   */
  var localTlsTrustedHosts: [String] { get }

  /**
   * Wallet requires PID Activation
   */
  var forcePidActivation: Bool { get }

  /**
   * Keychain Configuration
   */
  var keyChainConfig: KeyChainConfig { get }
}

struct ConfigLogicImpl: ConfigLogic {

  public var appBuildType: AppBuildType {
    getBuildType()
  }

  public var appVersion: String {
    getBundleValue(key: "CFBundleShortVersionString")
  }

  public var appBuildVariant: AppBuildVariant {
    getBuildVariant()
  }

  public var rqesConfig: EudiRQESUiConfig {
    RQESConfig(buildVariant: appBuildVariant, buildType: appBuildType)
  }

  public var changelogUrl: URL? {
    guard
      let value = getBundleNullableValue(key: "Changelog Url"),
      let url = URL(string: value)
    else {
      return nil
    }
    return url
  }

  public var localIssuerUrl: URL? {
    guard
      let value = getBundleNullableValue(key: "Local Issuer Url"),
      let url = URL(string: value)
    else {
      return nil
    }
    return url
  }

  public var localIssuerClientId: String {
    getBundleNullableValue(key: "Local Issuer Client Id") ?? "wallet-dev-local"
  }

  public var localWalletAttestationUrl: URL? {
    guard
      let value = getBundleNullableValue(key: "Local Wallet Attestation Url"),
      let url = URL(string: value)
    else {
      return nil
    }
    return url
  }

  public var localVerifierUrl: URL? {
    guard
      let value = getBundleNullableValue(key: "Local Verifier Url"),
      let url = URL(string: value)
    else {
      return nil
    }
    return url
  }

  public var localVerifierClientId: String? {
    getBundleNullableValue(key: "Local Verifier Client Id")
  }

  public var localTlsTrustedHosts: [String] {
    var trustedHosts = Set<String>()

    [localIssuerUrl?.host, localWalletAttestationUrl?.host, localVerifierUrl?.host]
      .compactMap { $0?.lowercased() }
      .forEach { trustedHosts.insert($0) }

    getBundleNullableValue(key: "Local Trusted Hosts")?
      .split(separator: ",")
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
      .filter { !$0.isEmpty }
      .forEach { trustedHosts.insert($0) }

    return trustedHosts.sorted()
  }

  var forcePidActivation: Bool {
    false
  }

  var keyChainConfig: KeyChainConfig {
    KeyChainConfig(
      documentStorageServiceName: Bundle.getDocumentStorageServiceName(),
      keychainAccessGroup: Bundle.getKeychainAccessGroup()
    )
  }
}
