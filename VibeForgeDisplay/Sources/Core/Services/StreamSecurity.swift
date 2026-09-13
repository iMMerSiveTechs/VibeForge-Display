import Foundation
import Security

/// Cryptographically secure random helpers for stream access control.
enum SecureRandom {
    /// Returns `count` CSPRNG bytes (SecRandomCopyBytes, falling back to
    /// SystemRandomNumberGenerator which is also cryptographically secure).
    static func bytes(_ count: Int) -> [UInt8] {
        var buf = [UInt8](repeating: 0, count: count)
        if SecRandomCopyBytes(kSecRandomDefault, count, &buf) == errSecSuccess {
            return buf
        }
        var rng = SystemRandomNumberGenerator()
        for i in 0..<count { buf[i] = UInt8.random(in: .min ... .max, using: &rng) }
        return buf
    }

    /// A URL-safe token of `length` chars from a 36-char alphabet, drawn without
    /// modulo bias via rejection sampling (~5.17 bits/char).
    static func token(byteCount length: Int = 16) -> String {
        let alphabet = Array("abcdefghijklmnopqrstuvwxyz0123456789")  // 36
        var out = ""
        while out.count < length {
            for b in bytes(length) {
                if b < 252 {                       // 252 = 7*36, unbiased over 0..251
                    out.append(alphabet[Int(b) % 36])
                    if out.count == length { break }
                }
            }
        }
        return out
    }

    /// A numeric PIN of `digits` length, uniformly distributed (rejection sampling).
    static func pin(digits: Int = 6) -> String {
        var out = ""
        while out.count < digits {
            for b in bytes(digits) {
                if b < 250 { out.append(String(b % 10)) }   // 250 = 25*10, avoids modulo bias
                if out.count == digits { break }
            }
        }
        return out
    }
}

/// Constant-time string comparison to avoid leaking match length via timing.
enum ConstantTime {
    static func equals(_ a: String, _ b: String) -> Bool {
        let ab = Array(a.utf8), bb = Array(b.utf8)
        // Compare across the max length so timing doesn't reveal length either.
        let n = max(ab.count, bb.count)
        var diff = ab.count ^ bb.count
        for i in 0..<n {
            let x = i < ab.count ? Int(ab[i]) : 0
            let y = i < bb.count ? Int(bb[i]) : 0
            diff |= (x ^ y)
        }
        return diff == 0
    }
}

/// Per-launch access control for the streaming server. A high-entropy session
/// token gates every data endpoint; receivers obtain it either from the QR/link
/// (web) or by redeeming a short PIN the user opens on the Mac (Apple TV).
/// Thread-safe: touched from both the UI (main) and the HTTP queue.
final class SessionSecurity: @unchecked Sendable {
    struct PairingState: Sendable { let active: Bool; let pin: String?; let secondsLeft: Int; let paired: Bool }

    private let lock = NSLock()
    private let token: String
    private var pin: String?
    private var pinExpiry: Date?
    private var attemptsLeft = 0
    private var paired = false

    init() {
        token = SecureRandom.token(byteCount: 26)   // ~134 bits
    }

    var sessionToken: String {
        lock.lock(); defer { lock.unlock() }
        return token
    }

    /// Validates a token from a request path in constant time.
    func isValid(token candidate: String) -> Bool {
        lock.lock(); let t = token; lock.unlock()
        return ConstantTime.equals(candidate, t)
    }

    // MARK: Pairing (for Apple TV / manual receivers)

    @discardableResult
    func beginPairing() -> String {
        lock.lock(); defer { lock.unlock() }
        let p = SecureRandom.pin(digits: 6)
        pin = p
        pinExpiry = Date().addingTimeInterval(VFConstants.Security.pairingWindow)
        attemptsLeft = VFConstants.Security.maxPairingAttempts
        paired = false
        return p
    }

    func cancelPairing() {
        lock.lock(); pin = nil; pinExpiry = nil; attemptsLeft = 0; lock.unlock()
    }

    /// Exchanges a correct PIN for the session token during the pairing window.
    /// One-time use; wrong attempts are capped, expiry enforced.
    func redeem(pin candidate: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        guard let current = pin, let exp = pinExpiry, attemptsLeft > 0, Date() < exp else {
            // Constant-time dummy compare so timing doesn't reveal whether a
            // pairing window is currently open.
            _ = ConstantTime.equals(candidate, "000000")
            pin = nil; pinExpiry = nil
            return nil
        }
        if ConstantTime.equals(candidate, current) {
            pin = nil; pinExpiry = nil; attemptsLeft = 0; paired = true
            return token
        }
        attemptsLeft -= 1
        if attemptsLeft <= 0 { pin = nil; pinExpiry = nil }
        return nil
    }

    func snapshot() -> PairingState {
        lock.lock(); defer { lock.unlock() }
        if let exp = pinExpiry, Date() >= exp { pin = nil; pinExpiry = nil }
        let secs = pinExpiry.map { max(0, Int($0.timeIntervalSinceNow)) } ?? 0
        return PairingState(active: pin != nil, pin: pin, secondsLeft: secs, paired: paired)
    }
}
