import XCTest

@testable import CodexMenuBar

final class PlanParsingTests: XCTestCase {
  func testParsePlanStepsUsesCodexdStepField() {
    let steps = ParsePlanSteps([
      [
        "step": "Inspect codexd bridge",
        "status": "completed",
      ],
      [
        "step": "Patch menu bar parser",
        "status": "inProgress",
      ],
    ])

    XCTAssertEqual(
      steps,
      [
        PlanStepInfo(description: "Inspect codexd bridge", status: .completed),
        PlanStepInfo(description: "Patch menu bar parser", status: .inProgress),
      ])
  }

  func testParsePlanStepsKeepsLegacyDescriptionFallbacks() {
    let steps = ParsePlanSteps([
      [
        "description": "Legacy description",
        "status": "pending",
      ],
      [
        "title": "Legacy title",
        "status": "completed",
      ],
    ])

    XCTAssertEqual(
      steps,
      [
        PlanStepInfo(description: "Legacy description", status: .pending),
        PlanStepInfo(description: "Legacy title", status: .completed),
      ])
  }
}
