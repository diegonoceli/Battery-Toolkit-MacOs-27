//
// Copyright (C) 2022 - 2025 Marvin Häuser. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

public extension SMCComm {
    @MainActor
    enum Power {
        private static let chargeKeys = [
            KeyControl.CHTE,
            KeyControl.CH0C
        ]
        private static let adapterKeys = [
            KeyControl.CHIE,
            KeyControl.CH0J
        ]

        private static var chargeKey: Int? = nil
        private static var adapterKey: Int? = nil

        static func supported() -> Bool {
            //
            // Ensure power adapter control key (e.g. CHIE / CH0J) is present and well-formed.
            //
            let adapterKey = self.adapterKeys.firstIndex { key in
                SMCComm.keySupported(keyInfo: key.keyInfo)
            }
            guard let adapterKey = adapterKey else {
                return false
            }
            self.adapterKey = adapterKey

            //
            // Check if a dedicated charge gating key (CHTE / CH0C) is available.
            // If absent (such as on Apple Silicon M2 under macOS 27 firmware),
            // adapter control (CHIE) is used to gate charging and power adapter state.
            //
            self.chargeKey = self.chargeKeys.firstIndex { key in
                SMCComm.keySupported(keyInfo: key.keyInfo)
            }

            return true
        }

        static func enableCharging() -> Bool {
            if let chargeKey = self.chargeKey {
                return SMCComm.writeKey(
                    key: self.chargeKeys[chargeKey].keyInfo.key,
                    bytes: self.chargeKeys[chargeKey].onBytes
                )
            } else {
                return self.enablePowerAdapter()
            }
        }

        static func disableCharging() -> Bool {
            if let chargeKey = self.chargeKey {
                return SMCComm.writeKey(
                    key: self.chargeKeys[chargeKey].keyInfo.key,
                    bytes: self.chargeKeys[chargeKey].offBytes
                )
            } else {
                return true
            }
        }

        static func isChargingDisabled() -> Bool {
            if let chargeKey = self.chargeKey {
                let value = SMCComm.readKey(
                    key: self.chargeKeys[chargeKey].keyInfo.key,
                    dataSize: self.chargeKeys[chargeKey].onBytes.count
                )
                guard let value else {
                    return false
                }

                return value != self.chargeKeys[chargeKey].onBytes
            } else {
                return false
            }
        }

        static func enablePowerAdapter() -> Bool {
            guard let adapterKey = self.adapterKey else {
                return false
            }
            return SMCComm.writeKey(
                key: self.adapterKeys[adapterKey].keyInfo.key,
                bytes: self.adapterKeys[adapterKey].onBytes
            )
        }

        static func disablePowerAdapter() -> Bool {
            guard let adapterKey = self.adapterKey else {
                return false
            }
            return SMCComm.writeKey(
                key: self.adapterKeys[adapterKey].keyInfo.key,
                bytes: self.adapterKeys[adapterKey].offBytes
            )
        }

        static func isPowerAdapterDisabled() -> Bool {
            guard let adapterKey = self.adapterKey else {
                return false
            }
            let value = SMCComm.readKey(
                key: self.adapterKeys[adapterKey].keyInfo.key,
                dataSize: self.adapterKeys[adapterKey].onBytes.count
            )
            guard let value else {
                return false
            }

            return value != self.adapterKeys[adapterKey].onBytes
        }
    }
}

private extension SMCComm.Power {
    private enum Keys {
        static let CHTE = SMCComm.KeyInfo(
            key: SMCComm.Key("C", "H", "T", "E"),
            info: SMCComm.KeyInfoData(
                dataSize: 4,
                dataType: SMCComm.KeyTypes.ui32,
                dataAttributes: 0xD4
            )
        )
        static let CH0C = SMCComm.KeyInfo(
            key: SMCComm.Key("C", "H", "0", "C"),
            info: SMCComm.KeyInfoData(
                dataSize: 1,
                dataType: SMCComm.KeyTypes.hex,
                dataAttributes: 0xD4
            )
        )
        static let CHIE = SMCComm.KeyInfo(
            key: SMCComm.Key("C", "H", "I", "E"),
            info: SMCComm.KeyInfoData(
                dataSize: 1,
                dataType: SMCComm.KeyTypes.hex,
                dataAttributes: 0xD4
            )
        )
        static let CH0J = SMCComm.KeyInfo(
            key: SMCComm.Key("C", "H", "0", "J"),
            info: SMCComm.KeyInfoData(
                dataSize: 1,
                dataType: SMCComm.KeyTypes.ui8,
                dataAttributes: 0xD4
            )
        )
    }
    
    private struct KeyControl {
        let keyInfo: SMCComm.KeyInfo
        let onBytes: [UInt8]
        let offBytes: [UInt8]

        static let CHTE = KeyControl(
            keyInfo: Keys.CHTE,
            onBytes: [0x00, 0x00, 0x00, 0x00],
            offBytes: [0x01, 0x00, 0x00, 0x00]
        )
        static let CH0C = KeyControl(
            keyInfo: Keys.CH0C,
            onBytes: [0x00],
            offBytes: [0x01]
        )
        static let CHIE = KeyControl(
            keyInfo: Keys.CHIE,
            onBytes: [0x00],
            offBytes: [0x08]
        )
        static let CH0J = KeyControl(
            keyInfo: Keys.CH0J,
            onBytes: [0x00],
            offBytes: [0x20]
        )
    }
}
