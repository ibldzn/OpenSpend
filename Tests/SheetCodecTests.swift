import XCTest

final class SheetCodecTests: XCTestCase {
    func testAmountParsing() {
        XCTAssertEqual(AmountParser.parse("12.5"), 12.5)
        XCTAssertEqual(AmountParser.parse("12,5"), 12.5)
        XCTAssertEqual(AmountParser.parse("1,234.56"), 1234.56)
        XCTAssertEqual(AmountParser.parse("1.234,56"), 1234.56)
        XCTAssertEqual(AmountParser.parse("1,234,567"), 1234567)
        XCTAssertEqual(AmountParser.parse("$ 9"), 9)
        XCTAssertNil(AmountParser.parse("abc"))
    }

    func testColumnLetters() {
        XCTAssertEqual(SheetCodec.columnLetter(0), "A")
        XCTAssertEqual(SheetCodec.columnLetter(25), "Z")
        XCTAssertEqual(SheetCodec.columnLetter(26), "AA")
        XCTAssertEqual(SheetCodec.columnLetter(701), "ZZ")
    }

    func testA1QuotesSheetNames() {
        XCTAssertEqual(SheetCodec.a1(sheet: "Bob's", "A1"), "'Bob''s'!A1")
    }

    func testRoundTripKeepsUnmappedCells() throws {
        var map = ColumnMap()
        map[.title] = "Name"
        map[.amount] = "Cost"
        map[.date] = "When"
        map[.category] = "Category"
        let header = ["When", "Name", "Memo", "Cost", "Category", SheetCodec.idHeader]
        let idx = try SheetCodec.indexes(header: header, map: map)
        let idIndex = try XCTUnwrap(SheetCodec.idIndex(header: header))

        let raw: [Any] = [NSNumber(value: 45000.5), "Coffee", "keep me", NSNumber(value: 4.5), "Food, Treats", "abc"]
        let row = try XCTUnwrap(SheetCodec.decode(row: raw, rowNumber: 2, indexes: idx, idIndex: idIndex, defaultCurrency: "EUR"))
        XCTAssertEqual(row.fields.title, "Coffee")
        XCTAssertEqual(row.fields.amount, 4.5)
        XCTAssertEqual(row.fields.categories, ["Food", "Treats"])
        XCTAssertEqual(row.fields.currency, "EUR")
        XCTAssertEqual(row.id, "abc")

        var f = row.fields
        f.title = "Tea"
        let out = SheetCodec.encode(f, id: "abc", indexes: idx, idIndex: idIndex, base: raw)
        XCTAssertEqual(out[1] as? String, "Tea")
        XCTAssertEqual(out[2] as? String, "keep me")
        XCTAssertEqual(out[4] as? String, "Food, Treats")
        XCTAssertEqual(out[5] as? String, "abc")
    }

    func testMissingMappedColumnThrows() {
        var map = ColumnMap()
        map[.title] = "Title"
        XCTAssertThrowsError(try SheetCodec.indexes(header: ["Amount"], map: map))
    }

    func testBlankRowsSkipped() throws {
        var map = ColumnMap()
        map[.title] = "Title"; map[.amount] = "Amount"; map[.date] = "Date"
        let idx = try SheetCodec.indexes(header: ["Title", "Amount", "Date"], map: map)
        XCTAssertNil(SheetCodec.decode(row: ["", "", ""], rowNumber: 3, indexes: idx, idIndex: nil, defaultCurrency: "USD"))
    }
}
