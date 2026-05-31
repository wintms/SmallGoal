import Foundation

struct MXDataQuoteProvider: QuoteProvider {
    private let endpoint: URL
    private let apiKey: String?
    private let session: URLSession

    init(
        endpoint: URL = URL(string: "https://mkapi2.dfcfs.com/finskillshub/api/claw/query")!,
        apiKey: String? = nil,
        session: URLSession = .shared
    ) {
        self.endpoint = endpoint
        self.apiKey = apiKey
        self.session = session
    }

    private static let maxCodesPerRequest = 5

    func fetchQuotes(for codes: [String]) async throws -> [Quote] {
        guard !codes.isEmpty else { throw QuoteProviderError.emptyCodes }
        guard let apiKey, !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw QuoteProviderError.missingAPIKey
        }

        let batches = stride(from: 0, to: codes.count, by: Self.maxCodesPerRequest).map {
            Array(codes[$0..<min($0 + Self.maxCodesPerRequest, codes.count)])
        }

        var allQuotes: [Quote] = []
        for batch in batches {
            let quotes = try await fetchBatch(codes: batch, apiKey: apiKey)
            allQuotes.append(contentsOf: quotes)
        }
        return allQuotes
    }

    private func fetchBatch(codes: [String], apiKey: String) async throws -> [Quote] {
        let codesString = codes.joined(separator: " ")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "apikey")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "toolQuery": "\(codesString) 最新价、昨收、涨跌额、涨跌幅、证券名称"
        ])

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw QuoteProviderError.network(error.localizedDescription)
        }

        guard let httpResponse = response as? HTTPURLResponse, 200..<300 ~= httpResponse.statusCode else {
            if let httpResponse = response as? HTTPURLResponse {
                throw QuoteProviderError.httpStatus(httpResponse.statusCode)
            }
            throw QuoteProviderError.invalidResponse
        }

        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw QuoteProviderError.decoding(error.localizedDescription)
        }

        guard let payload = object as? [String: Any] else {
            throw QuoteProviderError.invalidResponse
        }
        return try Self.parseQuotes(from: payload)
    }

    static func parseQuote(from payload: [String: Any], fallbackCode: String) throws -> Quote {
        let status = intValue(payload["status"])
        guard status == nil || status == 0 else {
            let message = stringValue(payload["message"]) ?? "未知错误"
            throw QuoteProviderError.invalidPayload("妙想接口返回错误：\(message)")
        }

        let searchResult = (((payload["data"] as? [String: Any])?["data"] as? [String: Any])?["searchDataResultDTO"] as? [String: Any])
        guard let searchResult else { throw QuoteProviderError.invalidResponse }

        let entity = firstEntity(in: searchResult, fallbackCode: fallbackCode)
        let rows = rows(in: searchResult)
        guard !rows.isEmpty else {
            throw QuoteProviderError.invalidPayload("妙想接口未返回有效行情表格")
        }

        return try quoteFrom(fields: mergedFields(from: rows), code: entity.code, name: entity.name)
    }

    static func parseQuotes(from payload: [String: Any]) throws -> [Quote] {
        let status = intValue(payload["status"])
        guard status == nil || status == 0 else {
            let message = stringValue(payload["message"]) ?? "未知错误"
            throw QuoteProviderError.invalidPayload("妙想接口返回错误：\(message)")
        }

        let searchResult = (((payload["data"] as? [String: Any])?["data"] as? [String: Any])?["searchDataResultDTO"] as? [String: Any])
        guard let searchResult else { throw QuoteProviderError.invalidResponse }

        let dtos = searchResult["dataTableDTOList"] as? [[String: Any]] ?? []
        guard !dtos.isEmpty else {
            throw QuoteProviderError.invalidPayload("妙想接口未返回有效行情表格")
        }

        var entityByCode: [String: (code: String, name: String)] = [:]
        if let entityList = searchResult["entityTagDTOList"] as? [[String: Any]] {
            for entity in entityList {
                let rawCode = stringValue(entity["secuCode"]) ?? stringValue(entity["code"]) ?? ""
                guard let code = normalizedCode(rawCode), entityByCode[code] == nil else { continue }
                let name = stringValue(entity["fullName"])
                    ?? stringValue(entity["shortName"])
                    ?? stringValue(entity["name"])
                    ?? code
                entityByCode[code] = (code, name)
            }
        }

        let rawDTOCodes = dtos.compactMap { stringValue($0["code"]) }
        print("[MXData] API返回DTO代码: \(rawDTOCodes)")

        var dtosByCode: [String: [[String: Any]]] = [:]
        for dto in dtos {
            guard let dtoCode = stringValue(dto["code"]),
                  let normalized = normalizedCode(dtoCode) else {
                print("[MXData] ⚠️ 跳过DTO, code=\(stringValue(dto["code"]) ?? "nil")")
                continue
            }
            dtosByCode[normalized, default: []].append(dto)
        }
        print("[MXData] 分组后代码: \(Array(dtosByCode.keys).sorted())")

        var quotes: [Quote] = []
        for (code, groupedDTOs) in dtosByCode {
            let rows = groupedDTOs.flatMap { tableRows(from: $0) }
            guard !rows.isEmpty else { continue }
            let entity = entityByCode[code] ?? (code, code)
            do {
                let quote = try quoteFrom(fields: mergedFields(from: rows), code: entity.code, name: entity.name)
                quotes.append(quote)
            } catch {
                print("[MXData] ⚠️ 解析失败 code=\(code): \(error.localizedDescription)")
                continue
            }
        }

        guard !quotes.isEmpty else {
            throw QuoteProviderError.invalidPayload("妙想接口未返回有效行情数据")
        }
        return quotes
    }

    private static func quoteFrom(fields: [String: String], code: String, name: String) throws -> Quote {
        guard let latestPrice = firstDouble(in: fields, matching: latestPriceCandidates) else {
            let availableFields = fields.keys.sorted().prefix(12).joined(separator: "、")
            let suffix = availableFields.isEmpty ? "" : "。可用字段：\(availableFields)"
            throw QuoteProviderError.invalidPayload("妙想接口未返回最新价\(suffix)")
        }

        let changeAmountFromField = firstDouble(in: fields, matching: ["涨跌额", "涨跌", "涨跌值", "涨跌金额", "涨跌价", "区间单位净值增长", "净值增长"])
        let previousCloseFromField = firstDouble(in: fields, matching: ["昨收", "昨收价", "前收盘", "前收", "昨日收盘价"])

        let changeAmount: Double
        let previousClose: Double

        if let ca = changeAmountFromField, let pc = previousCloseFromField {
            changeAmount = ca
            previousClose = pc
        } else if let pc = previousCloseFromField {
            previousClose = pc
            changeAmount = latestPrice - pc
        } else if let ca = changeAmountFromField {
            changeAmount = ca
            previousClose = latestPrice - ca
        } else {
            changeAmount = 0
            previousClose = latestPrice
        }

        let changePercent = firstPercent(in: fields, matching: ["涨跌幅", "涨幅", "跌幅", "涨跌比例", "区间单位净值增长率", "净值增长率"])
            ?? (previousClose == 0 ? 0 : changeAmount / previousClose)
        let quoteTime = firstDate(in: fields, matching: ["date", "日期", "时间", "更新时间"]) ?? .now

        return Quote(
            code: code,
            name: name,
            latestPrice: latestPrice,
            previousClose: previousClose,
            changeAmount: changeAmount,
            changePercent: changePercent,
            quoteTime: quoteTime
        )
    }

    private static func rows(in searchResult: [String: Any]) -> [[String: String]] {
        guard let tables = searchResult["dataTableDTOList"] as? [[String: Any]] else { return [] }
        return tables.flatMap { tableRows(from: $0) }
    }

    private static func tableRows(from dto: [String: Any]) -> [[String: String]] {
        if let table = dto["table"] as? [[String: Any]] {
            return table.map { row in
                Dictionary(uniqueKeysWithValues: row.map { key, value in
                    (key, flatten(value))
                })
            }
        }

        guard var table = dto["table"] as? [String: Any] else { return [] }

        if let rawTable = dto["rawTable"] as? [String: Any] {
            for (key, value) in rawTable {
                let tableValue = table[key]
                let values = tableValue as? [Any] ?? [tableValue as Any]
                let hasPercentUnit = values.contains { flatten($0).contains("%") }
                if !hasPercentUnit {
                    table[key] = value
                }
            }
        }

        let headers = table["headName"] as? [Any] ?? []
        let dataKeys = table.keys.filter { $0 != "headName" }.sorted()
        let nameMap = normalizedNameMap(dto["nameMap"])
        let codeMap = returnCodeMap(dto)

        if headersLookLikeIndicators(headers) {
            return dataKeys.map { key in
                let label = indicatorLabel(for: key, nameMap: nameMap, codeMap: codeMap)
                let values = table[key] as? [Any] ?? [table[key] as Any]
                var row: [String: String] = [:]
                if !label.isEmpty {
                    row["标的"] = label
                }
                for (index, header) in headers.enumerated() {
                    let headerLabel = flatten(header)
                    guard !headerLabel.isEmpty else { continue }
                    row[headerLabel] = index < values.count ? flatten(values[index]) : ""
                }
                return row
            }
        }

        if !headers.isEmpty {
            return headers.enumerated().map { index, header in
                var row = ["date": flatten(header)]
                for key in dataKeys {
                    let label = indicatorLabel(for: key, nameMap: nameMap, codeMap: codeMap)
                    guard !label.isEmpty else { continue }
                    let values = table[key] as? [Any]
                    row[label] = values.flatMap { index < $0.count ? flatten($0[index]) : nil } ?? flatten(table[key])
                }
                return row
            }
        }

        return dataKeys.map { key in
            let label = indicatorLabel(for: key, nameMap: nameMap, codeMap: codeMap)
            return ["指标": label, "值": flatten(table[key])]
        }
    }

    private static func firstEntity(in searchResult: [String: Any], fallbackCode: String) -> (code: String, name: String) {
        guard
            let entities = searchResult["entityTagDTOList"] as? [[String: Any]],
            let entity = entities.first
        else {
            return (fallbackCode, fallbackCode)
        }

        let rawCode = stringValue(entity["secuCode"]) ?? stringValue(entity["code"]) ?? fallbackCode
        let code = normalizedCode(rawCode) ?? fallbackCode
        let name = stringValue(entity["fullName"])
            ?? stringValue(entity["name"])
            ?? stringValue(entity["shortName"])
            ?? code
        return (code, name)
    }

    private static func isPlaceholder(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed == "-" || trimmed == "--" || trimmed == "N/A" || trimmed.isEmpty
    }

    private static func mergedFields(from rows: [[String: String]]) -> [String: String] {
        var fields: [String: String] = [:]
        for row in rows {
            for (key, value) in row where !isPlaceholder(value) && fields[key] == nil {
                fields[key] = value
            }
        }
        return fields
    }

    private static func indicatorLabel(for key: String, nameMap: [String: Any], codeMap: [String: String]) -> String {
        if let mapped = nameMap[key] {
            return flatten(mapped)
        }
        if let mapped = codeMap[key] {
            return mapped
        }
        return key.allSatisfy(\.isNumber) ? "" : key
    }

    private static var latestPriceCandidates: [String] {
        ["最新价", "最新价格", "现价", "当前价", "最新", "价格", "收盘价", "收盘", "区间最高单位净值", "最高单位净值", "最新净值"]
    }

    private static func headersLookLikeIndicators(_ headers: [Any]) -> Bool {
        headers
            .map(flatten)
            .contains { header in
                latestPriceCandidates.contains { header.contains($0) }
                    || header.contains("昨收")
                    || header.contains("涨跌")
                    || header.contains("现价")
            }
    }

    private static func normalizedNameMap(_ rawValue: Any?) -> [String: Any] {
        if let dict = rawValue as? [String: Any] {
            return dict
        }
        if let list = rawValue as? [Any] {
            return Dictionary(uniqueKeysWithValues: list.enumerated().map { index, value in
                (String(index), value)
            })
        }
        return [:]
    }

    private static func returnCodeMap(_ dto: [String: Any]) -> [String: String] {
        for key in ["returnCodeMap", "returnCodeNameMap", "codeMap"] {
            if let dict = dto[key] as? [String: Any] {
                return Dictionary(uniqueKeysWithValues: dict.map { key, value in
                    (key, flatten(value))
                })
            }
        }
        return [:]
    }

    private static func firstDouble(in fields: [String: String], matching candidates: [String]) -> Double? {
        firstValue(in: fields, matching: candidates).flatMap(doubleValue)
    }

    private static func firstPercent(in fields: [String: String], matching candidates: [String]) -> Double? {
        guard let value = firstValue(in: fields, matching: candidates) else { return nil }
        if value.contains("%"), let number = doubleValue(value) {
            return number / 100
        }
        return doubleValue(value)
    }

    private static func firstDate(in fields: [String: String], matching candidates: [String]) -> Date? {
        guard let value = firstValue(in: fields, matching: candidates) else { return nil }
        return dateValue(value)
    }

    private static func firstValue(in fields: [String: String], matching candidates: [String]) -> String? {
        for candidate in candidates {
            if let exact = fields[candidate], !exact.isEmpty {
                return exact
            }
            if let match = fields.first(where: { $0.key.contains(candidate) && !$0.value.isEmpty }) {
                return match.value
            }
        }
        return nil
    }

    private static func flatten(_ value: Any?) -> String {
        guard let value else { return "" }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        if JSONSerialization.isValidJSONObject(value),
           let data = try? JSONSerialization.data(withJSONObject: value),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return String(describing: value)
    }

    private static func stringValue(_ value: Any?) -> String? {
        let string = flatten(value).trimmingCharacters(in: .whitespacesAndNewlines)
        return string.isEmpty ? nil : string
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let string = stringValue(value) { return Int(string) }
        return nil
    }

    private static func doubleValue(_ value: String) -> Double? {
        let normalized = value
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: ",", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if let value = Double(normalized) {
            return value
        }

        guard let range = normalized.range(
            of: #"[-+]?\d+(?:\.\d+)?"#,
            options: .regularExpression
        ) else {
            return nil
        }
        return Double(normalized[range])
    }

    private static func dateValue(_ value: String) -> Date? {
        let iso = ISO8601DateFormatter()
        if let date = iso.date(from: value) { return date }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.timeZone = .current
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm", "yyyy-MM-dd"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }

    private static func normalizedCode(_ rawCode: String) -> String? {
        let digits = rawCode.filter(\.isNumber)
        guard !digits.isEmpty else { return nil }
        return String(digits.suffix(6))
    }
}
