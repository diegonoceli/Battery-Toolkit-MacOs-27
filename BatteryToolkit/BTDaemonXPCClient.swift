//
// Copyright (C) 2022 - 2025 Marvin Häuser. All rights reserved.
// SPDX-License-Identifier: BSD-3-Clause
//

import BTPreprocessor
import Foundation
import os.log

@BTBackgroundActor
internal enum BTDaemonXPCClient {
    private static var connect: NSXPCConnection? = nil

    static func disconnectDaemon() {
        guard let connect = self.connect else {
            return
        }

        self.connect = nil
        connect.invalidate()
    }

    private final class SafeContinuation<T: Sendable>: @unchecked Sendable {
        private var continuation: CheckedContinuation<T, any Error>?
        private let lock = NSLock()

        init(_ continuation: CheckedContinuation<T, any Error>) {
            self.continuation = continuation
        }

        func resume(returning value: T) {
            lock.lock()
            defer { lock.unlock() }
            continuation?.resume(returning: value)
            continuation = nil
        }

        func resume(throwing error: any Error) {
            lock.lock()
            defer { lock.unlock() }
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }

    private static func withTimeout<T: Sendable>(
        seconds: Double = 3.0,
        operation: @BTBackgroundActor @escaping (SafeContinuation<T>) -> Void
    ) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            let safe = SafeContinuation(continuation)

            DispatchQueue.global().asyncAfter(deadline: .now() + seconds) {
                safe.resume(throwing: BTError.commFailed)
            }

            Task { @BTBackgroundActor in
                operation(safe)
            }
        }
    }

    static func getUniqueId() async throws -> Data {
        try await withTimeout(seconds: 2.0) { safe in
            self.executeDaemon(command: { daemon in
                daemon.getUniqueId { data in
                    guard let data = data else {
                        safe.resume(throwing: BTError.malformedData)
                        return
                    }

                    safe.resume(returning: data)
                }
            }) { error in
                safe.resume(throwing: BTError.commFailed)
            }
        }
    }

    static func getState() async throws -> [String: NSObject & Sendable] {
        try await withTimeout(seconds: 3.0) { safe in
            self.executeDaemonRetry(safe: safe) { daemon in
                daemon.getState { state in
                    safe.resume(returning: state)
                }
            }
        }
    }

    static func disablePowerAdapter() async throws {
        let authData = try await BTAppXPCClient.getManageAuthorization()
        try await withTimeout(seconds: 5.0) { safe in
            self.runExecute(
                safe: safe,
                authData: authData,
                command: BTDaemonCommCommand.disablePowerAdapter
            )
        }
    }

    static func enablePowerAdapter() async throws {
        try await withTimeout(seconds: 5.0) { safe in
            self.runExecute(
                safe: safe,
                authData: nil,
                command: BTDaemonCommCommand.enablePowerAdapter
            )
        }
    }

    static func chargeToLimit() async throws {
        try await withTimeout(seconds: 5.0) { safe in
            self.runExecute(
                safe: safe,
                authData: nil,
                command: BTDaemonCommCommand.chargeToLimit
            )
        }
    }

    static func chargeToFull() async throws {
        try await withTimeout(seconds: 5.0) { safe in
            self.runExecute(
                safe: safe,
                authData: nil,
                command: BTDaemonCommCommand.chargeToFull
            )
        }
    }

    static func disableCharging() async throws {
        let authData = try await BTAppXPCClient.getManageAuthorization()
        try await withTimeout(seconds: 5.0) { safe in
            self.runExecute(
                safe: safe,
                authData: authData,
                command: BTDaemonCommCommand.disableCharging
            )
        }
    }

    static func pauseActivity() async throws {
        let authData = try await BTAppXPCClient.getManageAuthorization()
        try await withTimeout(seconds: 5.0) { safe in
            self.runExecute(
                safe: safe,
                authData: authData,
                command: BTDaemonCommCommand.pauseActivity
            )
        }
    }

    static func resumeActivity() async throws {
        let authData = try await BTAppXPCClient.getManageAuthorization()
        try await withTimeout(seconds: 5.0) { safe in
            self.runExecute(
                safe: safe,
                authData: authData,
                command: BTDaemonCommCommand.resumeActivity
            )
        }
    }

    static func getSettings() async throws -> [String: NSObject & Sendable] {
        try await withTimeout(seconds: 3.0) { safe in
            self.executeDaemonRetry(safe: safe) { daemon in
                daemon.getSettings { settings in
                    safe.resume(returning: settings)
                }
            }
        }
    }

    static func setSettings(settings: [String: NSObject & Sendable]) async throws {
        let authData = try await BTAppXPCClient.getManageAuthorization()
        try await withTimeout(seconds: 5.0) { safe in
            self.executeDaemonManageRetry(safe: safe) { daemon in
                daemon.setSettings(
                    authData: authData,
                    settings: settings,
                    reply: self.continuationStatusHandler(safe: safe)
                )
            }
        }
    }

    static func prepareUpdate() async throws {
        try await withTimeout(seconds: 1.5) { safe in
            self.executeDaemonRetry(safe: safe) { daemon in
                daemon.execute(
                    authData: nil,
                    command: BTDaemonCommCommand.prepareUpdate.rawValue,
                    reply: self.continuationStatusHandler(safe: safe)
                )
            }
        }
    }

    static func finishUpdate() {
        Task {
            do {
                try await withTimeout(seconds: 1.5) { safe in
                    self.runExecute(safe: safe, authData: nil, command: BTDaemonCommCommand.finishUpdate)
                }
            }
            catch {
                //
                // Deliberately ignore errors as this is an optional notification.
                //
            }
        }
    }

    static func removeLegacyHelperFiles(authData: Data) async throws {
        try await withTimeout(seconds: 5.0) { safe in
            self.executeDaemonRetry(safe: safe) { daemon in
                daemon.execute(
                    authData: authData,
                    command: BTDaemonCommCommand.removeLegacyHelperFiles.rawValue,
                    reply: self.continuationStatusHandler(safe: safe)
                )
            }
        }
    }

    static func prepareDisable(authData: Data) async throws {
        let manageAuthData = try await BTAppXPCClient.getManageAuthorization()
        try await withTimeout(seconds: 5.0) { safe in
            self.runExecute(safe: safe, authData: manageAuthData, command: BTDaemonCommCommand.prepareDisable)
        }
    }

    static func isSupported() async throws {
        try await withTimeout(seconds: 3.0) { safe in
            self.runExecute(safe: safe, authData: nil, command: BTDaemonCommCommand.isSupported)
        }
    }

    private static func continuationStatusHandler(safe: SafeContinuation<Void>) -> (@Sendable (BTError.RawValue) -> Void) {
        return { error in
            guard error == BTError.success.rawValue else {
                safe.resume(throwing: BTError.init(rawValue: error)!)
                return
            }
            safe.resume(returning: ())
        }
    }
    
    private static func connectDaemon() -> NSXPCConnection {
        if let connect = self.connect {
            return connect
        }

        let connect = NSXPCConnection(
            machServiceName: BT_DAEMON_CONN,
            options: .privileged
        )
        connect.remoteObjectInterface = NSXPCInterface(
            with: BTDaemonCommProtocol.self
        )

        BTXPCValidation.protectDaemon(connection: connect)

        connect.resume()
        self.connect = connect

        os_log("XPC client connected")

        return connect
    }

    private static func executeDaemon(
        command: @BTBackgroundActor @Sendable (BTDaemonCommProtocol) -> Void,
        errorHandler: @escaping @Sendable (any Error) -> Void
    ) {
        let connect = self.connectDaemon()
        let daemon = connect.remoteObjectProxyWithErrorHandler(
            errorHandler
        ) as! BTDaemonCommProtocol
        command(daemon)
    }

    private static func executeDaemonRetry<T>(
        safe: SafeContinuation<T>,
        command: @BTBackgroundActor @escaping @Sendable (BTDaemonCommProtocol) -> Void
    ) {
        self.executeDaemon(command: command) { error in
            os_log("XPC client remote error: \(error, privacy: .public))")
            os_log("Retrying...")
            Task { @BTBackgroundActor in
                self.disconnectDaemon()
                self.executeDaemon(command: command) { error in
                    os_log("XPC client remote error: \(error, privacy: .public))")
                    safe.resume(throwing: BTError.commFailed)
                }
            }
        }
    }

    private static func executeDaemonManageRetry<T>(
        safe: SafeContinuation<T>,
        command: @BTBackgroundActor @escaping @Sendable (BTDaemonCommProtocol) -> Void
    ) {
        self.executeDaemonRetry(safe: safe, command: command)
    }

    private static func runExecute(
        safe: SafeContinuation<Void>,
        authData: Data?,
        command: BTDaemonCommCommand
    ) {
        self.executeDaemonManageRetry(safe: safe) { daemon in
            daemon.execute(
                authData: authData,
                command: command.rawValue,
                reply: self.continuationStatusHandler(safe: safe)
            )
        }
    }
}
