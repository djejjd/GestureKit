import XCTest
@testable import GestureKitCore

final class GestureRecognizerTests: XCTestCase {
    func testThreeFingerTapIsRecognized() {
        var recognizer = GestureRecognizer()

        XCTAssertEqual(
            recognizer.observe(.frame(time: 0.00, activeTouches: [.touch(1, 0.30, 0.40), .touch(2, 0.32, 0.40), .touch(3, 0.34, 0.40)])).count,
            1
        )
        let event = completed(&recognizer, .frame(time: 0.18, activeTouches: []))

        XCTAssertEqual(event?.gesture, .threeFingerTap)
        XCTAssertEqual(event?.centroidX ?? -1, 0.32, accuracy: 0.001)
    }

    func testPhysicalLeftSwipeIsRecognized() {
        var recognizer = GestureRecognizer()

        _ = recognizer.observe(.frame(time: 0.00, activeTouches: [.touch(1, 0.70, 0.40), .touch(2, 0.72, 0.40), .touch(3, 0.74, 0.40)]))
        _ = recognizer.observe(.frame(time: 0.20, activeTouches: [.touch(1, 0.48, 0.40), .touch(2, 0.50, 0.40), .touch(3, 0.52, 0.40)]))
        let event = completed(&recognizer, .frame(time: 0.34, activeTouches: []))

        XCTAssertEqual(event?.gesture, .threeFingerSwipeLeft)
    }

    func testPhysicalRightSwipeIsRecognized() {
        var recognizer = GestureRecognizer()

        _ = recognizer.observe(.frame(time: 0.00, activeTouches: [.touch(1, 0.30, 0.40), .touch(2, 0.32, 0.40), .touch(3, 0.34, 0.40)]))
        _ = recognizer.observe(.frame(time: 0.20, activeTouches: [.touch(1, 0.55, 0.40), .touch(2, 0.57, 0.40), .touch(3, 0.59, 0.40)]))
        let event = completed(&recognizer, .frame(time: 0.34, activeTouches: []))

        XCTAssertEqual(event?.gesture, .threeFingerSwipeRight)
    }

    func testShorterPhysicalSwipeIsRecognized() {
        var recognizer = GestureRecognizer()

        _ = recognizer.observe(.frame(time: 0.00, activeTouches: [.touch(1, 0.30, 0.40), .touch(2, 0.32, 0.40), .touch(3, 0.34, 0.40)]))
        _ = recognizer.observe(.frame(time: 0.16, activeTouches: [.touch(1, 0.40, 0.40), .touch(2, 0.42, 0.40), .touch(3, 0.44, 0.40)]))
        let event = completed(&recognizer, .frame(time: 0.26, activeTouches: []))

        XCTAssertEqual(event?.gesture, .threeFingerSwipeRight)
    }

    func testSlightlyDiagonalPhysicalSwipeIsRecognized() {
        var recognizer = GestureRecognizer()

        _ = recognizer.observe(.frame(time: 0.00, activeTouches: [.touch(1, 0.30, 0.40), .touch(2, 0.32, 0.40), .touch(3, 0.34, 0.40)]))
        _ = recognizer.observe(.frame(time: 0.16, activeTouches: [.touch(1, 0.42, 0.48), .touch(2, 0.44, 0.48), .touch(3, 0.46, 0.48)]))
        let event = completed(&recognizer, .frame(time: 0.26, activeTouches: []))

        XCTAssertEqual(event?.gesture, .threeFingerSwipeRight)
    }

    func testRobustSwipeSettingsRequireMoreDeliberateMovement() {
        var recognizer = GestureRecognizer(settings: .robust)

        _ = recognizer.observe(.frame(time: 0.00, activeTouches: [.touch(1, 0.30, 0.40), .touch(2, 0.32, 0.40), .touch(3, 0.34, 0.40)]))
        _ = recognizer.observe(.frame(time: 0.16, activeTouches: [.touch(1, 0.40, 0.40), .touch(2, 0.42, 0.40), .touch(3, 0.44, 0.40)]))
        let event = completed(&recognizer, .frame(time: 0.26, activeTouches: []))

        XCTAssertNil(event?.gesture)
        XCTAssertEqual(event?.status, .gestureUnstable)
        XCTAssertEqual(event?.reason, .distanceTooShort)
    }

    func testUnstableSwipeCarriesThresholdsForDiagnostics() {
        var recognizer = GestureRecognizer(settings: .standard)

        _ = recognizer.observe(.frame(time: 0.00, activeTouches: [.touch(1, 0.30, 0.40), .touch(2, 0.32, 0.40), .touch(3, 0.34, 0.40)]))
        _ = recognizer.observe(.frame(time: 0.16, activeTouches: [.touch(1, 0.37, 0.40), .touch(2, 0.39, 0.40), .touch(3, 0.41, 0.40)]))
        let event = completed(&recognizer, .frame(time: 0.26, activeTouches: []))

        XCTAssertEqual(event?.reason, .distanceTooShort)
        XCTAssertEqual(event?.thresholds, .standard)
    }

    func testSensitiveSwipeSettingsAllowShorterMovement() {
        var recognizer = GestureRecognizer(settings: .sensitive)

        _ = recognizer.observe(.frame(time: 0.00, activeTouches: [.touch(1, 0.30, 0.40), .touch(2, 0.32, 0.40), .touch(3, 0.34, 0.40)]))
        _ = recognizer.observe(.frame(time: 0.16, activeTouches: [.touch(1, 0.38, 0.40), .touch(2, 0.40, 0.40), .touch(3, 0.42, 0.40)]))
        let event = completed(&recognizer, .frame(time: 0.26, activeTouches: []))

        XCTAssertEqual(event?.gesture, .threeFingerSwipeRight)
    }

    func testGestureRecognizerCanUpdateSwipeSettings() {
        var recognizer = GestureRecognizer(settings: .robust)

        recognizer.updateSettings(.sensitive)
        _ = recognizer.observe(.frame(time: 0.00, activeTouches: [.touch(1, 0.30, 0.40), .touch(2, 0.32, 0.40), .touch(3, 0.34, 0.40)]))
        _ = recognizer.observe(.frame(time: 0.16, activeTouches: [.touch(1, 0.38, 0.40), .touch(2, 0.40, 0.40), .touch(3, 0.42, 0.40)]))
        let event = completed(&recognizer, .frame(time: 0.26, activeTouches: []))

        XCTAssertEqual(event?.gesture, .threeFingerSwipeRight)
    }

    func testUnclearGestureIsReported() {
        var recognizer = GestureRecognizer()

        _ = recognizer.observe(.frame(time: 0.00, activeTouches: [.touch(1, 0.30, 0.30), .touch(2, 0.32, 0.32), .touch(3, 0.34, 0.34)]))
        _ = recognizer.observe(.frame(time: 0.80, activeTouches: [.touch(1, 0.36, 0.42), .touch(2, 0.38, 0.44), .touch(3, 0.40, 0.46)]))
        let event = completed(&recognizer, .frame(time: 0.90, activeTouches: []))

        XCTAssertEqual(event?.status, .gestureUnstable)
    }

    func testSlowHorizontalSwipeIsReportedUnstable() {
        var recognizer = GestureRecognizer()

        _ = recognizer.observe(.frame(time: 0.00, activeTouches: [.touch(1, 0.70, 0.40), .touch(2, 0.72, 0.40), .touch(3, 0.74, 0.40)]))
        _ = recognizer.observe(.frame(time: 0.80, activeTouches: [.touch(1, 0.42, 0.40), .touch(2, 0.44, 0.40), .touch(3, 0.46, 0.40)]))
        let event = completed(&recognizer, .frame(time: 0.95, activeTouches: []))

        XCTAssertNil(event?.gesture)
        XCTAssertEqual(event?.status, .gestureUnstable)
    }

    func testFourFingerInterruptionInvalidatesThreeFingerSessionUntilAllTouchesLift() {
        var recognizer = GestureRecognizer()

        XCTAssertEqual(recognizer.observe(threeTouches(time: 0.00)).count, 1)
        let interruption = recognizer.observe(fourTouches(time: 0.05))
        guard case .primitiveRejected(let rejected)? = interruption.first else {
            return XCTFail("四指接管时必须终止三指候选，避免协调器保留陈旧 session")
        }
        XCTAssertEqual(rejected.status, .gestureUnstable)
        XCTAssertEqual(rejected.reason, .unknown)
        XCTAssertTrue(recognizer.observe(threeTouches(time: 0.10)).isEmpty)
        XCTAssertTrue(recognizer.observe(.frame(time: 0.15, activeTouches: [])).isEmpty)

        XCTAssertEqual(recognizer.observe(threeTouches(time: 0.20)).count, 1)
        XCTAssertEqual(completed(&recognizer, .frame(time: 0.30, activeTouches: []))?.gesture, .threeFingerTap)
    }

    func testFewerTouchesCompleteSessionButDoNotReenterUntilAllTouchesLift() {
        var recognizer = GestureRecognizer()

        XCTAssertEqual(recognizer.observe(threeTouches(time: 0.00)).count, 1)
        XCTAssertEqual(recognizer.observe(twoTouches(time: 0.05)).compactMap(\.recognizedGesture).first?.gesture, .threeFingerTap)
        XCTAssertTrue(recognizer.observe(threeTouches(time: 0.10)).isEmpty)
        XCTAssertTrue(recognizer.observe(.frame(time: 0.15, activeTouches: [])).isEmpty)

        XCTAssertEqual(recognizer.observe(threeTouches(time: 0.20)).count, 1)
        XCTAssertEqual(completed(&recognizer, .frame(time: 0.30, activeTouches: []))?.gesture, .threeFingerTap)
    }

    func testFiveFingerInterruptionInvalidatesThreeFingerSessionUntilAllTouchesLift() {
        var recognizer = GestureRecognizer()

        XCTAssertEqual(recognizer.observe(threeTouches(time: 0.00)).count, 1)
        let interruption = recognizer.observe(fiveTouches(time: 0.05))
        guard case .primitiveRejected(let rejected)? = interruption.first else {
            return XCTFail("五指接管时必须终止三指候选，避免协调器保留陈旧 session")
        }
        XCTAssertEqual(rejected.status, .gestureUnstable)
        XCTAssertEqual(rejected.reason, .unknown)
        XCTAssertTrue(recognizer.observe(threeTouches(time: 0.10)).isEmpty)
        XCTAssertTrue(recognizer.observe(.frame(time: 0.15, activeTouches: [])).isEmpty)

        XCTAssertEqual(recognizer.observe(threeTouches(time: 0.20)).count, 1)
        XCTAssertEqual(completed(&recognizer, .frame(time: 0.30, activeTouches: []))?.gesture, .threeFingerTap)
    }

    // MARK: - V2.5 预设手势集：二指 / 四指识别

    func testTwoFingerSwipeLeftIsRecognized() {
        var recognizer = GestureRecognizer()

        XCTAssertEqual(recognizer.observe(.frame(time: 0.00, activeTouches: [.touch(1, 0.60, 0.40), .touch(2, 0.62, 0.40)])).count, 1)
        _ = recognizer.observe(.frame(time: 0.20, activeTouches: [.touch(1, 0.38, 0.40), .touch(2, 0.40, 0.40)]))
        let event = completed(&recognizer, .frame(time: 0.34, activeTouches: []))

        XCTAssertEqual(event?.gesture, .twoFingerSwipeLeft)
    }

    func testTwoFingerSwipeRightIsRecognized() {
        var recognizer = GestureRecognizer()

        XCTAssertEqual(recognizer.observe(twoTouches(time: 0.00)).count, 1)
        _ = recognizer.observe(.frame(time: 0.20, activeTouches: [.touch(1, 0.55, 0.40), .touch(2, 0.57, 0.40)]))
        let event = completed(&recognizer, .frame(time: 0.34, activeTouches: []))

        XCTAssertEqual(event?.gesture, .twoFingerSwipeRight)
    }

    func testTwoFingerTapIsRejectedWhenNoTapDefinitionActive() {
        var recognizer = GestureRecognizer()

        // 二指属于活跃定义集（有滑动定义），因此会启动候选；
        // 但二指没有 tap 定义，点按动作应收敛为不稳定（不被分类）。
        XCTAssertEqual(recognizer.observe(twoTouches(time: 0.00)).count, 1)
        _ = recognizer.observe(.frame(time: 0.16, activeTouches: [.touch(1, 0.32, 0.40), .touch(2, 0.34, 0.40)]))
        let event = completed(&recognizer, .frame(time: 0.26, activeTouches: []))

        XCTAssertNil(event?.gesture)
        XCTAssertEqual(event?.status, .gestureUnstable)
    }

    func testFourFingerTapIsRecognized() {
        var recognizer = GestureRecognizer()

        XCTAssertEqual(recognizer.observe(fourTouches(time: 0.00)).count, 1)
        let event = completed(&recognizer, .frame(time: 0.18, activeTouches: []))

        XCTAssertEqual(event?.gesture, .fourFingerTap)
    }

    func testFourFingerSwipeLeftIsRecognized() {
        var recognizer = GestureRecognizer()

        XCTAssertEqual(recognizer.observe(.frame(time: 0.00, activeTouches: [.touch(1, 0.70, 0.40), .touch(2, 0.72, 0.40), .touch(3, 0.74, 0.40), .touch(4, 0.76, 0.40)])).count, 1)
        _ = recognizer.observe(.frame(time: 0.20, activeTouches: [.touch(1, 0.38, 0.40), .touch(2, 0.40, 0.40), .touch(3, 0.42, 0.40), .touch(4, 0.44, 0.40)]))
        let event = completed(&recognizer, .frame(time: 0.34, activeTouches: []))

        XCTAssertEqual(event?.gesture, .fourFingerSwipeLeft)
    }

    func testFourFingerSwipeRightIsRecognized() {
        var recognizer = GestureRecognizer()

        XCTAssertEqual(recognizer.observe(fourTouches(time: 0.00)).count, 1)
        _ = recognizer.observe(.frame(time: 0.20, activeTouches: [.touch(1, 0.55, 0.40), .touch(2, 0.57, 0.40), .touch(3, 0.59, 0.40), .touch(4, 0.61, 0.40)]))
        let event = completed(&recognizer, .frame(time: 0.34, activeTouches: []))

        XCTAssertEqual(event?.gesture, .fourFingerSwipeRight)
    }

    func testFingerCountIncreaseInterruptsTwoFingerSessionUntilAllTouchesLift() {
        var recognizer = GestureRecognizer()

        XCTAssertEqual(recognizer.observe(twoTouches(time: 0.00)).count, 1)
        let interruption = recognizer.observe(threeTouches(time: 0.05))
        guard case .primitiveRejected(let rejected)? = interruption.first else {
            return XCTFail("三指接管时必须终止二指候选，避免协调器保留陈旧 session")
        }
        XCTAssertEqual(rejected.status, .gestureUnstable)
        XCTAssertTrue(recognizer.observe(twoTouches(time: 0.10)).isEmpty)
        XCTAssertTrue(recognizer.observe(.frame(time: 0.15, activeTouches: [])).isEmpty)

        XCTAssertEqual(recognizer.observe(twoTouches(time: 0.20)).count, 1)
        _ = recognizer.observe(.frame(time: 0.24, activeTouches: [.touch(1, 0.50, 0.40), .touch(2, 0.52, 0.40)]))
        XCTAssertEqual(completed(&recognizer, .frame(time: 0.30, activeTouches: []))?.gesture, .twoFingerSwipeRight)
    }

    func testRecognizerUsesActiveDefinitionSetForFingerCountMatching() {
        // 活跃定义集仅含二指滑动；三指不应启动候选。
        var recognizer = GestureRecognizer(definitions: [
            .init(id: "two-finger-swipe-left", primitive: .swipe, fingers: 2, repetitions: 1, maxIntervalMs: nil, direction: .left, region: .any, maxDurationMs: 300),
            .init(id: "two-finger-swipe-right", primitive: .swipe, fingers: 2, repetitions: 1, maxIntervalMs: nil, direction: .right, region: .any, maxDurationMs: 300)
        ])

        XCTAssertTrue(recognizer.observe(threeTouches(time: 0.00)).isEmpty)
        XCTAssertTrue(recognizer.observe(threeTouches(time: 0.20)).isEmpty)

        XCTAssertEqual(recognizer.observe(twoTouches(time: 0.00)).count, 1)
        _ = recognizer.observe(.frame(time: 0.20, activeTouches: [.touch(1, 0.50, 0.40), .touch(2, 0.52, 0.40)]))
        XCTAssertEqual(completed(&recognizer, .frame(time: 0.34, activeTouches: []))?.gesture, .twoFingerSwipeRight)
    }

    func testPrimitiveWithoutActiveDefinitionIsNotClassified() {
        // 仅声明四指轻点，未声明四指滑动：滑动动作应收敛为不稳定（不被分类）。
        var recognizer = GestureRecognizer(definitions: [
            .init(id: "four-finger-tap", primitive: .tap, fingers: 4, repetitions: 1, maxIntervalMs: nil, direction: nil, region: .any, maxDurationMs: 180)
        ])

        XCTAssertEqual(recognizer.observe(fourTouches(time: 0.00)).count, 1)
        _ = recognizer.observe(.frame(time: 0.20, activeTouches: [.touch(1, 0.70, 0.40), .touch(2, 0.72, 0.40), .touch(3, 0.74, 0.40), .touch(4, 0.76, 0.40)]))
        let event = completed(&recognizer, .frame(time: 0.34, activeTouches: []))

        XCTAssertNil(event?.gesture)
        XCTAssertEqual(event?.status, .gestureUnstable)
    }

    func testUpdateDefinitionsReconfiguresActiveFingerCountSet() {
        var recognizer = GestureRecognizer()

        recognizer.updateDefinitions([
            .init(id: "two-finger-swipe-right", primitive: .swipe, fingers: 2, repetitions: 1, maxIntervalMs: nil, direction: .right, region: .any, maxDurationMs: 300)
        ])

        XCTAssertTrue(recognizer.observe(threeTouches(time: 0.00)).isEmpty)
        XCTAssertEqual(recognizer.observe(twoTouches(time: 0.00)).count, 1)
    }

    // MARK: - V2.5 预设手势集：枚举与定义集映射

    func testPresetGestureDefinitionsExistInDefaultRules() {
        let ids = Set(DefaultRules.defaultGestureDefinitions.map(\.id))

        XCTAssertTrue(ids.contains("two-finger-swipe-left"))
        XCTAssertTrue(ids.contains("two-finger-swipe-right"))
        XCTAssertTrue(ids.contains("four-finger-tap"))
        XCTAssertTrue(ids.contains("four-finger-swipe-left"))
        XCTAssertTrue(ids.contains("four-finger-swipe-right"))
    }

    func testComposedGestureDefinitionIDsMapToPresetGestureDefinitions() {
        XCTAssertEqual(ComposedGesture.twoFingerSwipeLeft.gestureDefinitionID, "two-finger-swipe-left")
        XCTAssertEqual(ComposedGesture.twoFingerSwipeRight.gestureDefinitionID, "two-finger-swipe-right")
        XCTAssertEqual(ComposedGesture.fourFingerTap.gestureDefinitionID, "four-finger-tap")
        XCTAssertEqual(ComposedGesture.fourFingerSwipeLeft.gestureDefinitionID, "four-finger-swipe-left")
        XCTAssertEqual(ComposedGesture.fourFingerSwipeRight.gestureDefinitionID, "four-finger-swipe-right")
    }

    func testGestureTypeRawValuesForNewPresets() {
        XCTAssertEqual(GestureType.twoFingerSwipeLeft.rawValue, "two_finger_swipe_left")
        XCTAssertEqual(GestureType.twoFingerSwipeRight.rawValue, "two_finger_swipe_right")
        XCTAssertEqual(GestureType.fourFingerTap.rawValue, "four_finger_tap")
        XCTAssertEqual(GestureType.fourFingerSwipeLeft.rawValue, "four_finger_swipe_left")
        XCTAssertEqual(GestureType.fourFingerSwipeRight.rawValue, "four_finger_swipe_right")
    }
}

private extension TouchSample {
    static func touch(_ id: Int32, _ x: Float, _ y: Float) -> TouchSample {
        TouchSample(id: id, x: x, y: y)
    }
}

private func completed(_ recognizer: inout GestureRecognizer, _ frame: TouchFrame) -> RecognizedGesture? {
    recognizer.observe(frame).compactMap(\.recognizedGesture).first
}

private func threeTouches(time: TimeInterval) -> TouchFrame {
    .frame(time: time, activeTouches: [.touch(1, 0.30, 0.40), .touch(2, 0.32, 0.40), .touch(3, 0.34, 0.40)])
}

private func twoTouches(time: TimeInterval) -> TouchFrame {
    .frame(time: time, activeTouches: [.touch(1, 0.30, 0.40), .touch(2, 0.32, 0.40)])
}

private func fourTouches(time: TimeInterval) -> TouchFrame {
    .frame(time: time, activeTouches: [.touch(1, 0.30, 0.40), .touch(2, 0.32, 0.40), .touch(3, 0.34, 0.40), .touch(4, 0.36, 0.40)])
}

private func fiveTouches(time: TimeInterval) -> TouchFrame {
    .frame(time: time, activeTouches: [.touch(1, 0.30, 0.40), .touch(2, 0.32, 0.40), .touch(3, 0.34, 0.40), .touch(4, 0.36, 0.40), .touch(5, 0.38, 0.40)])
}
