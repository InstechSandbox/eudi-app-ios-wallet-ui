# Building the Reference apps to interact with issuing and verifying services

## Table of contents

* [Overview](#overview)
* [Setup Apps](#setup-apps)
* [How to work with self signed certificates on iOS](#how-to-work-with-self-signed-certificates-on-ios)
* [Document Provider extension configuration](configuration.md#document-provider-extension-configuration)

## Overview

This guide aims to assist developers in building the application.

## Setup Apps

## EUDI iOS Wallet reference application

You need [xcode](https://xcodereleases.com/) and its associated tools installed on your machine. We recommend the latest non-beta version.

Clone the [iOS repository](https://github.com/eu-digital-identity-wallet/eudi-app-ios-wallet-ui)

Open the project file in Xcode. The application has two schemes: "EUDI Wallet Dev" and "EUDI Wallet Demo".

* EUDI Wallet Dev: This target communicates with the services deployed in an environment based on the latest main branch.
* EUDI Wallet Demo: This target communicates with the services deployed in the latest stable environment.

For the Instech cloud-build workflow, interpret those variants as the intended local-versus-cloud split:

* `Dev`: local engineering build used from Xcode for the non-tester path
* `Demo`: shared cloud tester build intended for the public `test.instech-eudi-poc.com` issuer and verifier path, including TestFlight publication

The two variants should remain visually distinguishable on-device:

* `Dev` installs as `EUDI Wallet Local`
* `Demo` installs as `EUDI Wallet Test`

Each scheme has two configurations: Debug and Release.

* Debug: Used when running the app from within Xcode.
* Release: Used when running the app after it has been distributed via a distribution platform, currently TestFlight.

This setup results in a total of four configurations. All four configurations are defined in the xcconfig files located under the Config folder in the project.

To run the app on the simulator, select your app schema and press Run.

To run the app on a device, follow similar steps to running it on the simulator. Additionally, you need to supply your own provisioning profile and signing certificate in the Signing & Capabilities tab of your app target.

### Running with remote services

The app is configured to the type (debug/release) and variant (dev/demo) in the four xcconfig files. These are the contents of the xcconfig file, and you don't need to change anything if you don't want to:

```ini
BUILD_TYPE = RELEASE
BUILD_VARIANT = DEMO
```

The values defined in the `.xcconfig` files are utilized within instances of `WalletKitConfig` and `RQESConfig` to assign the appropriate configurations. These configurations are selected based on the specified build type and build variant defined in the `.xcconfig` files.

Reader and verifier behavior is environment-specific, not only distribution-specific:

* local document-reader and verifier testing should stay on the `Dev` variant because its bundle identifier and app name are reserved for the local path
* cloud document-reader and verifier testing should stay on the `Demo` variant because that is the tester-facing path that should align with TestFlight and the public verifier or issuer hosts
* mixing a local reader flow with the cloud build, or a cloud reader flow with the local build, is expected to fail even when the wallet itself installs correctly

The iOS wallet now reads its issuer hosts from the tracked variant xcconfig files through `Wallet.plist`, and `Modules/logic-core/Sources/Config/WalletKitConfig.swift` consumes those values. In this workspace that means:

* `Dev` defaults to the local issuer frontend and backend URLs (`https://127.0.0.1:5002` and `https://127.0.0.1:5003`)
* `Demo` defaults to the public cloud issuer frontend and backend URLs (`https://issuer.test.instech-eudi-poc.com` and `https://issuer-api.test.instech-eudi-poc.com`)

If you need the `Dev` variant on a physical device instead of the simulator, create a local untracked `Wallet/Config/WalletLocalOverrides.xcconfig` file and override `ISSUER_FRONTEND_URL` and `ISSUER_BACKEND_URL` there with your current LAN host. That avoids committing a machine-specific IP address into the repo.

Remote verifier flows still depend on the actual verifier URL opened in Safari or scanned from a QR code, so operators still need to use the matching local verifier page for `Dev` and the matching public verifier page for `Demo`.

Instances of `ConfigLogic` are responsible for interpreting the raw string values extracted from the `.xcconfig` files and converting them into appropriate data types.

```swift
/**
 * Build type.
 */
var appBuildType: AppBuildType { get }

/**
 * Build variant.
 */
var appBuildVariant: AppBuildVariant { get }
```

Using this parsed information, instances such as `WalletKitConfig` and `RQESConfig` can determine and assign their specific configurations based on the defined build type and variant.

For instance, here's how `WalletKitConfig` resolves its configuration for OpenID4VCI remote services based on the build variant:

```swift
var vciConfig: [String: OpenId4VciConfiguration] {
  let openId4VciConfigurations: [OpenId4VciConfiguration] = {
    switch configLogic.appBuildVariant {
    case .DEMO:
      return [
        .init(
          credentialIssuerURL: "https://issuer.eudiw.dev",
          clientId: "wallet-dev",
          keyAttestationsConfig: .init(walletAttestationsProvider: walletKitAttestationProvider),
          authFlowRedirectionURI: URL(string: "eu.europa.ec.euidi://authorization")!,
          requirePAR: true,
          requireDpop: true,
          cacheIssuerMetadata: true
        )
    case .DEV:
      return [
        .init(
          credentialIssuerURL: "https://ec.dev.issuer.eudiw.dev",
          clientId: "wallet-dev",
          keyAttestationsConfig: .init(walletAttestationsProvider: walletKitAttestationProvider),
          authFlowRedirectionURI: URL(string: "eu.europa.ec.euidi://authorization")!,
          requirePAR: true,
          requireDpop: true,
          cacheIssuerMetadata: true
        )
      ]
    }
  }()

  // ...
}
```

In this example, the `vciConfig` property dynamically assigns configurations, such as `issuerUrl`, `clientId`, `redirectUri`, `usePAR`, `useDpopIfSupported`, `keyAttestationsConfig`, and `cacheIssuerMetadata`, based on the current `appBuildVariant`. This ensures that the appropriate settings are applied for each variant (e.g., `.DEMO` or `.DEV`).

### Running with local services

The first step is to run all three services locally on your machine. You can follow these Repositories for further instructions:

* [Issuer](https://github.com/eu-digital-identity-wallet/eudi-srv-web-issuing-eudiw-py)
* [Web Verifier UI](https://github.com/eu-digital-identity-wallet/eudi-web-verifier)
* [Web Verifier Endpoint](https://github.com/eu-digital-identity-wallet/eudi-srv-web-verifier-endpoint-23220-4-kt)

### How to work with self-signed certificates on iOS

To enable the app to interact with a locally running service, a minor code change is required.

Before running the app in the simulator, add the following lines of code to the top of the `NetworkSessionProvider` file inside the `logic-api` module, directly below the import statements.

```swift
final class SelfSignedDelegate: NSObject, URLSessionDelegate {
  func urlSession(
    _ session: URLSession,
    didReceive challenge: URLAuthenticationChallenge,
    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
  ) {
    // Check if the challenge is for a self-signed certificate
    if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
       let trust = challenge.protectionSpace.serverTrust {
      // Create a URLCredential with the self-signed certificate
      let credential = URLCredential(trust: trust)
      // Call the completion handler with the credential to accept the self-signed certificate
      completionHandler(.useCredential, credential)
    } else {
      // For other authentication methods, call the completion handler with a nil credential to reject the request
      completionHandler(.cancelAuthenticationChallenge, nil)
    }
  }
}

let walletSession: URLSession = {
  let delegate = SelfSignedDelegate()
  let configuration = URLSessionConfiguration.default
  return URLSession(
    configuration: configuration,
    delegate: delegate,
    delegateQueue: nil
  )
}()
```

Once the above is in place, adjust the initializer:

```swift
init() {
  self.urlSession = walletSession
}
```

This change will allow the app to interact with web services that rely on self-signed certificates.

## Document Provider extension configuration

If you are enabling or troubleshooting the Identity Document Provider extension, including `SHARED_APP_GROUP_IDENTIFIER`, keychain-access-groups, and extension registration behavior, follow the dedicated configuration guide here:

[Document Provider extension configuration](configuration.md#document-provider-extension-configuration)

For all configuration options, please refer to [this document](configuration.md)
