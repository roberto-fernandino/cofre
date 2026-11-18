import CofreCore
import CryptoKit
import Foundation

// Testes de ida-e-volta, adulteração, truncamento e chave errada + benchmark.

let fm = FileManager.default
let dir = fm.temporaryDirectory.appendingPathComponent("cofre-selftest-\(UUID().uuidString)")
try fm.createDirectory(at: dir, withIntermediateDirectories: true)
defer { try? fm.removeItem(at: dir) }

let cipher = CofreCipher(masterKey: SymmetricKey(size: .bits256))
let chunk = 4096
var failures = 0

func check(_ ok: Bool, _ msg: String) {
    print(ok ? "  ok   \(msg)" : "  FAIL \(msg)")
    if !ok { failures += 1 }
}

func randomData(_ n: Int) -> Data {
    var d = Data(count: n)
    if n > 0 { d.withUnsafeMutableBytes { _ = SecRandomCopyBytes(kSecRandomDefault, n, $0.baseAddress!) } }
    return d
}

func expectFailure(_ name: String, _ c: CofreCipher = cipher, _ file: URL) {
    let out = dir.appendingPathComponent("x.out")
    do {
        try c.decrypt(from: file, to: out)
        check(false, name)
    } catch {
        check(error as? CofreError == .authenticationFailed || error as? CofreError == .notCofreFile, "\(name) → \(error.localizedDescription)")
    }
}

print("Ida e volta:")
for size in [0, 1, chunk - 1, chunk, chunk + 1, 3 * chunk + 5, 5 * chunk] {
    let plain = dir.appendingPathComponent("p\(size)")
    let enc = dir.appendingPathComponent("p\(size).cofre")
    let dec = dir.appendingPathComponent("p\(size).dec")
    let data = randomData(size)
    try data.write(to: plain)
    try cipher.encrypt(from: plain, to: enc, chunkSize: chunk)
    try cipher.decrypt(from: enc, to: dec)
    check(try Data(contentsOf: dec) == data, "\(size) bytes")
}

print("Ataques:")
let sample = dir.appendingPathComponent("p\(3 * chunk + 5).cofre")
let original = try Data(contentsOf: sample)

var flipped = original
flipped[flipped.count / 2] ^= 0x01
let fFlip = dir.appendingPathComponent("flip.cofre"); try flipped.write(to: fFlip)
expectFailure("bit invertido detectado", cipher, fFlip)

let truncated = original.prefix(original.count - 5) // corta o fim do último bloco
let fTrunc = dir.appendingPathComponent("trunc.cofre"); try truncated.write(to: fTrunc)
expectFailure("truncamento detectado", cipher, fTrunc)

let headerSize = 6 + 1 + 4 + 32
let atBoundary = original.prefix(headerSize + 3 * (chunk + 16)) // remove o bloco final inteiro
let fBound = dir.appendingPathComponent("bound.cofre"); try atBoundary.write(to: fBound)
expectFailure("remoção do bloco final detectada", cipher, fBound)

var swapped = original
let a = headerSize, b = headerSize + chunk + 16
let blockA = original[a..<b], blockB = original[b..<(b + chunk + 16)]
swapped.replaceSubrange(a..<b, with: blockB)
swapped.replaceSubrange(b..<(b + chunk + 16), with: blockA)
let fSwap = dir.appendingPathComponent("swap.cofre"); try swapped.write(to: fSwap)
expectFailure("troca de blocos detectada", cipher, fSwap)

expectFailure("chave errada recusada", CofreCipher(masterKey: SymmetricKey(size: .bits256)), sample)

let notCofre = dir.appendingPathComponent("p1")
expectFailure("arquivo comum recusado", cipher, notCofre)

print("Chave de recuperação:")
let k = SymmetricKey(size: .bits256)
let text = RecoveryKey.encode(k)
let back = try RecoveryKey.decode("  \(text)\n")
check(back == k, "codifica/decodifica (\(text.prefix(12))…)")

print("Job (nomes):")
let doc = dir.appendingPathComponent("relatorio.pdf")
try randomData(10_000).write(to: doc)
let r1 = try CofreJob.process(doc, cipher: cipher, deleteOriginal: false)
check(r1.output.lastPathComponent == "relatorio.pdf.cofre", "criptografa → \(r1.output.lastPathComponent)")
let r2 = try CofreJob.process(r1.output, cipher: cipher, deleteOriginal: true)
check(r2.output.lastPathComponent == "relatorio (1).pdf", "descriptografa sem sobrescrever → \(r2.output.lastPathComponent)")
check(try Data(contentsOf: r2.output) == Data(contentsOf: doc), "conteúdo igual")
check(!fm.fileExists(atPath: r1.output.path), "apagou o .cofre original")
let leftovers = try fm.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".tmp") }
check(leftovers.isEmpty, "sem temporários sobrando")

print("Benchmark (512 MiB):")
let big = dir.appendingPathComponent("big.bin")
let mb = randomData(1 << 20)
fm.createFile(atPath: big.path, contents: nil)
let h = try FileHandle(forWritingTo: big)
for _ in 0..<512 { try h.write(contentsOf: mb) }
try h.close()
var t = Date()
let rb = try CofreJob.process(big, cipher: cipher, deleteOriginal: true)
let te = Date().timeIntervalSince(t)
t = Date()
_ = try CofreJob.process(rb.output, cipher: cipher, deleteOriginal: true)
let td = Date().timeIntervalSince(t)
print(String(format: "  criptografar: %.2fs (%.0f MB/s) · descriptografar: %.2fs (%.0f MB/s)", te, 512 / te, td, 512 / td))

print(failures == 0 ? "\nTudo certo." : "\n\(failures) falha(s).")
exit(failures == 0 ? 0 : 1)
