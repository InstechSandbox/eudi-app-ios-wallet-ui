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
import logic_business
import EudiWalletKit
import OpenID4VP
import Security

protocol WalletKitConfig: Sendable {

  /**
   * VCI Configuration
   */
  var issuersConfig: [String: VciConfig] { get }

  /**
   * VP Configuration
   */
  var vpConfig: OpenId4VpConfiguration { get }

  /**
   * Reader Configuration
   */
  var trustedReaderRootCertificates: [x5chain] { get }

  /**
   * User authentication required accessing core's secure storage
   */
  var userAuthenticationRequired: Bool { get }

  /**
   * The name of the file to be created to store logs
   */
  var logFileName: String { get }

  /**
   * Document categories
   */
  var documentsCategories: DocumentCategories { get }

  /**
   * Logger For Transactions
   */
  var transactionLogger: TransactionLogger { get }

  /**
   * The interval (in seconds) at which revocations are checked.
   */
  var revocationIntervalSeconds: TimeInterval { get }

  /**
   * Configuration for document issuance, including default rules and specific overrides.
   */
  var documentIssuanceConfig: DocumentIssuanceConfig { get }
}

struct WalletKitConfigImpl: WalletKitConfig {

  private struct IssuerConfiguration {
    let credentialIssuerURL: String
    let order: Int
  }

  let configLogic: ConfigLogic
  let transactionLoggerImpl: TransactionLogger
  let walletKitAttestationProvider: WalletKitAttestationProvider

  init(
    configLogic: ConfigLogic,
    transactionLogger: TransactionLogger,
    walletKitAttestationProvider: WalletKitAttestationProvider
  ) {
    self.configLogic = configLogic
    self.transactionLoggerImpl = transactionLogger
    self.walletKitAttestationProvider = walletKitAttestationProvider
  }

  var userAuthenticationRequired: Bool {
    false
  }

  var issuersConfig: [String: VciConfig] {
    let authFlowRedirectionURI = URL(string: "eu.europa.ec.euidi://authorization")!
    let hostedConfigurations = issuerConfigurations.map { issuerConfiguration in
      VciConfig(
        config: .init(
          credentialIssuerURL: issuerConfiguration.credentialIssuerURL,
          clientId: "wallet-dev",
          keyAttestationsConfig: .init(walletAttestationsProvider: walletKitAttestationProvider),
          authFlowRedirectionURI: authFlowRedirectionURI,
          requirePAR: true,
          requireDpop: true,
          cacheIssuerMetadata: true
        ),
        order: issuerConfiguration.order
      )
    }

    let openId4VciConfigurations: [VciConfig]
    if let localIssuerUrl = configLogic.localIssuerUrl?.absoluteString {
      openId4VciConfigurations = hostedConfigurations + [
        .init(
          config: .init(
            credentialIssuerURL: localIssuerUrl,
            clientId: configLogic.localIssuerClientId,
            authFlowRedirectionURI: authFlowRedirectionURI,
            requirePAR: false,
            requireDpop: true,
            cacheIssuerMetadata: true
          ),
          order: 2
        )
      ]
    } else {
      openId4VciConfigurations = hostedConfigurations
    }

    return openId4VciConfigurations.reduce(
      into: [String: VciConfig]()
    ) { dict, config in
      guard
        let issuer = config.config.credentialIssuerURL,
        let url = URL(string: issuer),
        let host = url.host
      else {
        return
      }
      dict[host] = config
    }
  }

  var vpConfig: OpenId4VpConfiguration {
    var clientIdSchemes: [ClientIdScheme] = [.x509SanDns, .x509Hash]

    if let clientId = configLogic.localVerifierClientId,
       let verifierApiUri = configLogic.localVerifierUrl?.absoluteString {
      clientIdSchemes.append(
        .preregistered(
          [
            PreregisteredClient(
              clientId: clientId,
              legalName: configLogic.localVerifierUrl?.host ?? clientId,
              jarSigningAlg: JWSAlgorithm(.ES256),
              jwkSetSource: WebKeySource.fetchByReference(
                url: URL(string: "\(verifierApiUri)/wallet/public-keys.json")!
              )
            )
          ]
        )
      )
    }

    return .init(clientIdSchemes: clientIdSchemes)
  }

  var trustedReaderRootCertificates: [x5chain] {
    let certificates = [
      "pidissuerca_local_ut",
      "pidissuerca02_cz",
      "pidissuerca02_ee",
      "pidissuerca02_eu",
      "pidissuerca02_lu",
      "pidissuerca02_nl",
      "pidissuerca02_pt",
      "pidissuerca02_ut",
      "r45_staging"
    ]
    return certificates
      .compactMap { loadCertificate($0) }
      .map { [$0] }
  }

  var logFileName: String {
    return "eudi-ios-wallet-logs"
  }

  var documentsCategories: DocumentCategories {
    [
      .Government: [
        .mDocPid,
        .sdJwtPid,
        .other(formatType: "org.iso.18013.5.1.mDL"),
        .other(formatType: "eu.europa.ec.eudi.pseudonym.age_over_18.1"),
        .other(formatType: "urn:eu.europa.ec.eudi:pseudonym_age_over_18:1"),
        .other(formatType: "eu.europa.ec.eudi.tax.1"),
        .other(formatType: "urn:eu.europa.ec.eudi:tax:1"),
        .other(formatType: "eu.europa.ec.eudi.pseudonym.age_over_18.deferred_endpoint"),
        .other(formatType: "eu.europa.ec.eudi.cor.1")
      ],
      .Travel: [
        .other(formatType: "org.iso.23220.2.photoid.1"),
        .other(formatType: "org.iso.23220.photoID.1"),
        .other(formatType: "org.iso.18013.5.1.reservation")
      ],
      .Finance: [
        .other(formatType: "eu.europa.ec.eudi.iban.1"),
        .other(formatType: "urn:eu.europa.ec.eudi:iban:1")
      ],
      .Education: [],
      .Health: [
        .other(formatType: "eu.europa.ec.eudi.hiid.1"),
        .other(formatType: "urn:eu.europa.ec.eudi:hiid:1"),
        .other(formatType: "eu.europa.ec.eudi.ehic.1"),
        .other(formatType: "urn:eu.europa.ec.eudi:ehic:1")
      ],
      .SocialSecurity: [
        .other(formatType: "eu.europa.ec.eudi.pda1.1"),
        .other(formatType: "urn:eu.europa.ec.eudi:pda1:1")
      ],
      .Retail: [
        .other(formatType: "eu.europa.ec.eudi.loyalty.1"),
        .other(formatType: "eu.europa.ec.eudi.msisdn.1"),
        .other(formatType: "urn:eu.europa.ec.eudi:msisdn:1")
      ],
      .Other: [
        .other(formatType: "eu.europa.ec.eudi.por.1"),
        .other(formatType: "urn:eu.europa.ec.eudi:por:1")
      ]
    ]
  }

  var transactionLogger: any TransactionLogger {
    return self.transactionLoggerImpl
  }

  var revocationIntervalSeconds: TimeInterval {
    300
  }

  var documentIssuanceConfig: DocumentIssuanceConfig {
    return switch configLogic.appBuildVariant {
    case .DEMO:
      DocumentIssuanceConfig(
        defaultRule: DocumentIssuanceRule(
          policy: .rotateUse,
          numberOfCredentials: 1
        ),
        documentSpecificRules: [
          // Local verifier presentation currently crashes if batched PID credentials
          // share the same document id during OpenID4VP setup.
          DocumentTypeIdentifier.mDocPid: DocumentIssuanceRule(
            policy: .oneTimeUse,
            numberOfCredentials: 1
          ),
          DocumentTypeIdentifier.sdJwtPid: DocumentIssuanceRule(
            policy: .rotateUse,
            numberOfCredentials: 1
          )
        ],
        reIssuanceRule: ReIssuanceRule(
          minNumberOfCredentials: 2,
          minExpirationHours: 14,
          backgroundIntervalSeconds: 300
        )
      )
    case .DEV:
      DocumentIssuanceConfig(
        defaultRule: DocumentIssuanceRule(
          policy: .rotateUse,
          numberOfCredentials: 1
        ),
        documentSpecificRules: [
          // Local verifier presentation currently crashes if batched PID credentials
          // share the same document id during OpenID4VP setup.
          DocumentTypeIdentifier.mDocPid: DocumentIssuanceRule(
            policy: .oneTimeUse,
            numberOfCredentials: 1
          ),
          DocumentTypeIdentifier.sdJwtPid: DocumentIssuanceRule(
            policy: .rotateUse,
            numberOfCredentials: 1
          )
        ],
        reIssuanceRule: ReIssuanceRule(
          minNumberOfCredentials: 2,
          minExpirationHours: 14,
          backgroundIntervalSeconds: 300
        )
      )
    }
  }
}

private extension WalletKitConfigImpl {
  var issuerConfigurations: [IssuerConfiguration] {
    let defaults: [IssuerConfiguration]

    switch configLogic.appBuildVariant {
    case .DEMO:
      defaults = [
        .init(credentialIssuerURL: "https://issuer.test.instech-eudi-poc.com", order: 1),
        .init(credentialIssuerURL: "https://issuer-api.test.instech-eudi-poc.com", order: 0),
      ]
    case .DEV:
      defaults = [
        .init(credentialIssuerURL: "https://127.0.0.1:5002", order: 1),
        .init(credentialIssuerURL: "https://127.0.0.1:5003", order: 0),
      ]
    }

    let configuredUrls = [
      "Issuer Frontend Url".optionalValueFromBundle,
      "Issuer Backend Url".optionalValueFromBundle,
    ]

    return zip(configuredUrls, defaults).map { configuredUrl, defaultConfiguration in
      IssuerConfiguration(
        credentialIssuerURL: configuredUrl ?? defaultConfiguration.credentialIssuerURL,
        order: defaultConfiguration.order
      )
    }
  }

  func loadCertificate(_ name: String) -> SecCertificate? {
    guard let data = Data(name: name, ext: "der") else { return nil }
    return SecCertificateCreateWithData(nil, data as CFData)
  }
}
