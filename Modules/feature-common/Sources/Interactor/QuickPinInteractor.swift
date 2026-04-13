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
import logic_authentication

public enum QuickPinPartialState: Sendable {
  case success
  case failure(Error)
}

public protocol QuickPinInteractor: Sendable {
  func setPin(newPin: String) async
  func isPinValid(pin: String) async -> QuickPinPartialState
  func changePin(currentPin: String, newPin: String) async -> QuickPinPartialState
  func hasPin() async -> Bool
}

final actor QuickPinInteractorImpl: QuickPinInteractor {

  private let pinStorageController: PinStorageController

  init(pinStorageController: PinStorageController) {
    self.pinStorageController = pinStorageController
  }

  public func setPin(newPin: String) {
    let normalizedPin = newPin.normalizedQuickPin
    pinStorageController.setPin(with: normalizedPin)
    debugLogStoredPinUpdate(normalizedPin)
  }

  public func isPinValid(pin: String) -> QuickPinPartialState {
    if self.isCurrentPinValid(pin: pin) {
      return .success
    } else {
      return .failure(AuthenticationError.quickPinInvalid)
    }
  }

  public func changePin(currentPin: String, newPin: String) -> QuickPinPartialState {
    if self.isCurrentPinValid(pin: currentPin) {
      self.setPin(newPin: newPin)
      return .success
    } else {
      return .failure(AuthenticationError.quickPinInvalid)
    }
  }

  public func hasPin() -> Bool {
    pinStorageController.retrievePin()?.normalizedQuickPin.isEmpty == false
  }

  private func isCurrentPinValid(pin: String) -> Bool {
    let normalizedInput = pin.normalizedQuickPin
    let normalizedStoredPin = pinStorageController.retrievePin()?.normalizedQuickPin
    let isMatch = normalizedStoredPin == normalizedInput
    debugLogPinValidationAttempt(input: normalizedInput, stored: normalizedStoredPin, isMatch: isMatch)
    return isMatch
  }

  private func debugLogStoredPinUpdate(_ normalizedPin: String) {
    #if DEBUG && targetEnvironment(simulator)
    NSLog(
      "[QuickPinDebug] Stored simulator PIN updated length=%ld fingerprint=%@",
      normalizedPin.count,
      normalizedPin.debugFingerprint
    )
    #endif
  }

  private func debugLogPinValidationAttempt(input: String, stored: String?, isMatch: Bool) {
    #if DEBUG && targetEnvironment(simulator)
    NSLog(
      "[QuickPinDebug] Validate simulator PIN inputLength=%ld inputFingerprint=%@ storedLength=%ld storedFingerprint=%@ match=%@",
      input.count,
      input.debugFingerprint,
      stored?.count ?? 0,
      stored?.debugFingerprint ?? "<nil>",
      isMatch ? "true" : "false"
    )
    #endif
  }
}

private extension String {
  var normalizedQuickPin: String {
    self.compactMap(\.wholeNumberValue).map(String.init).joined()
  }

  var debugFingerprint: String {
    let checksum = self.utf8.reduce(UInt64(5381)) { partial, byte in
      ((partial << 5) &+ partial) &+ UInt64(byte)
    }
    return String(checksum, radix: 16, uppercase: false)
  }
}
