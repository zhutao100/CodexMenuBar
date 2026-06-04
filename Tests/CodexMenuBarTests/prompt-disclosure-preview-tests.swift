import XCTest

@testable import CodexMenuBar

final class PromptDisclosurePreviewTests: XCTestCase {
  func testFoldedPreviewShowsFirstFiveLinesByDefault() {
    let preview = PromptDisclosurePreview(
      text: """
        Line 1
        Line 2
        Line 3
        Line 4
        Line 5
        Line 6
        """)

    XCTAssertTrue(preview.isExpandable)
    XCTAssertEqual(
      preview.VisibleText(isExpanded: false),
      """
      Line 1
      Line 2
      Line 3
      Line 4
      Line 5
      """)
    XCTAssertTrue(preview.VisibleText(isExpanded: true).contains("Line 6"))
  }

  func testFiveLinePromptDoesNotNeedExpansion() {
    let prompt = """
      Line 1
      Line 2
      Line 3
      Line 4
      Line 5
      """
    let preview = PromptDisclosurePreview(text: prompt)

    XCTAssertFalse(preview.isExpandable)
    XCTAssertEqual(preview.VisibleText(isExpanded: false), prompt)
  }
}
