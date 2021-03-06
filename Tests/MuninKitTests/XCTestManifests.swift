#if !canImport(ObjectiveC)
import XCTest

extension AlbumTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__AlbumTests = [
        ("test", test),
        ("testReadStateFromInputDirectory", testReadStateFromInputDirectory),
        ("testReadStateFromInputDirectoryMultipleTime", testReadStateFromInputDirectoryMultipleTime),
    ]
}

extension KeywordTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__KeywordTests = [
        ("test", test),
        ("testBuildKeywordsFromAlbum", testBuildKeywordsFromAlbum),
    ]
}

extension LocationDegreeTests {
    // DO NOT MODIFY: This is autogenerated, use:
    //   `swift test --generate-linuxmain`
    // to regenerate.
    static let __allTests__LocationDegreeTests = [
        ("test", test),
        ("testLocationDegreeFromDecimal", testLocationDegreeFromDecimal),
        ("testLocationDegreeFromString", testLocationDegreeFromString),
        ("testLocationDegreeToDecimal", testLocationDegreeToDecimal),
    ]
}

public func __allTests() -> [XCTestCaseEntry] {
    return [
        testCase(AlbumTests.__allTests__AlbumTests),
        testCase(KeywordTests.__allTests__KeywordTests),
        testCase(LocationDegreeTests.__allTests__LocationDegreeTests),
    ]
}
#endif
