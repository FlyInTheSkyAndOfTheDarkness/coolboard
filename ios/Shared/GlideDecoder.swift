import Foundation

struct TracePoint: Equatable {
    let x: Double
    let y: Double
    func distance(to other: TracePoint) -> Double { hypot(x - other.x, y - other.y) }
}

enum GlideDecoder {
    static func resample(_ points: [TracePoint], count: Int = 24) -> [TracePoint] {
        guard let first = points.first else { return [] }
        var lengths = [0.0]
        for i in 1..<points.count { lengths.append(lengths.last! + points[i - 1].distance(to: points[i])) }
        let length = lengths.last!
        guard length > 0 else { return Array(repeating: first, count: count) }
        var segment = 1
        return (0..<count).map { index in
            let target = length * Double(index) / Double(count - 1)
            while segment < lengths.count - 1 && lengths[segment] < target { segment += 1 }
            let t = (target - lengths[segment - 1]) / max(0.000001, lengths[segment] - lengths[segment - 1])
            let a = points[segment - 1], b = points[segment]
            return TracePoint(x: a.x + t * (b.x - a.x), y: a.y + t * (b.y - a.y))
        }
    }

    static func rank(trace: [TracePoint], centers: [String: TracePoint], words: [String]) -> [String] {
        guard trace.count >= 2, centers.count >= 3 else { return [] }
        let keys = Array(centers.values)
        let unit = keys.map { point in keys.filter { $0 != point }.map { point.distance(to: $0) }.min() ?? 1 }.reduce(0, +) / Double(keys.count)
        let pathLength = zip(trace, trace.dropFirst()).map { pair in pair.0.distance(to: pair.1) }.reduce(0, +)
        guard unit > 0, pathLength >= unit * 0.7 else { return [] }
        let sample = resample(trace)
        var ranked: [(String, Double)] = []
        var seen = Set<String>()
        for (index, original) in words.enumerated() {
            let word = original.lowercased()
            guard word.count >= 2, word.count <= 24, seen.insert(word).inserted else { continue }
            var chars: [Character] = []
            for char in word where chars.last != char { chars.append(char) }
            let path = chars.compactMap { centers[String($0)] }
            guard path.count == chars.count, path.count >= 2,
                  trace.first!.distance(to: path.first!) <= unit * 0.9,
                  trace.last!.distance(to: path.last!) <= unit * 0.9 else { continue }
            let expected = resample(path)
            var rows = Array(repeating: Array(repeating: Double.infinity, count: expected.count + 1), count: sample.count + 1)
            rows[0][0] = 0
            for i in 1...sample.count {
                for j in 1...expected.count {
                    rows[i][j] = sample[i - 1].distance(to: expected[j - 1]) / unit + min(rows[i - 1][j], rows[i][j - 1], rows[i - 1][j - 1])
                }
            }
            let endpoints = trace.first!.distance(to: path.first!) + trace.last!.distance(to: path.last!)
            let score = rows[sample.count][expected.count] / Double(sample.count) + endpoints / unit + Double(index) * 0.000002
            if score < 2.5 { ranked.append((original, score)) }
        }
        return ranked.sorted { $0.1 < $1.1 }.prefix(3).map(\.0)
    }
}

final class LocalPredictionEngine {
    private struct Pack: Decodable { let languages: [String: [String]] }
    private let vocabulary: [String: [String]]
    private let seeds: [String: [String: [String]]]
    init() {
        vocabulary = Bundle.main.url(forResource: "prediction", withExtension: "json").flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode(Pack.self, from: $0) }?.languages ?? [:]
        seeds = Bundle.main.url(forResource: "predictive-seeds", withExtension: "json").flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder().decode([String: [String: [String]]].self, from: $0) } ?? [:]
    }
    func words(language: String) -> [String] { vocabulary[language] ?? [] }
    func completions(word: String, language: String) -> [String] {
        Array(words(language: language).lazy.filter { $0.hasPrefix(word.lowercased()) && $0 != word.lowercased() }.prefix(3))
    }
    func next(context: String, language: String) -> [String] {
        guard let range = context.range(of: "[\\p{L}\\p{M}]+[\\s.!?,:;]+$", options: .regularExpression) else { return [] }
        let previous = context[range].trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters)).lowercased()
        return seeds[language]?[previous] ?? []
    }
}
