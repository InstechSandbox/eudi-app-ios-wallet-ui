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

public protocol NetworkSessionProvider: Sendable {
  var urlSession: URLSession { get }
}

final class NetworkSessionProviderImpl: NetworkSessionProvider {

  let urlSession: URLSession
  private let sessionDelegate: URLSessionDelegate?

  init(configLogic: ConfigLogic) {
    let trustedHosts = Set(configLogic.localTlsTrustedHosts)

    guard !trustedHosts.isEmpty else {
      self.sessionDelegate = nil
      self.urlSession = URLSession.shared
      return
    }

    let sessionDelegate = LocalTLSTrustDelegate(trustedHosts: trustedHosts)
    self.sessionDelegate = sessionDelegate
    self.urlSession = URLSession(
      configuration: .default,
      delegate: sessionDelegate,
      delegateQueue: nil
    )
  }
}

private final class LocalTLSTrustDelegate: NSObject, URLSessionDelegate {

  private let trustedHosts: Set<String>

  init(trustedHosts: Set<String>) {
    self.trustedHosts = trustedHosts
  }

  func urlSession(
    _ session: URLSession,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    guard
      challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
      let serverTrust = challenge.protectionSpace.serverTrust,
      trustedHosts.contains(challenge.protectionSpace.host.lowercased())
    else {
      completionHandler(.performDefaultHandling, nil)
      return
    }

    completionHandler(.useCredential, URLCredential(trust: serverTrust))
  }
}
