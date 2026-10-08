// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import Foundation
import ZenTouchCore

struct CheckFailure: Error, CustomStringConvertible {
    let description: String
}

func expect(_ condition: @autoclosure () throws -> Bool, file: StaticString = #filePath, line: UInt = #line) throws {
    guard try condition() else { throw CheckFailure(description: "\(file):\(line): expectation failed") }
}
func require<T>(_ value: T?, file: StaticString = #filePath, line: UInt = #line) throws -> T {
    guard let value else { throw CheckFailure(description: "\(file):\(line): required value is nil") }
    return value
}
func expectThrows<E: Error>(_ type: E.Type, _ body: () throws -> Any?) throws {
    do { _ = try body() } catch is E { return }
    throw CheckFailure(description: "Expected error of type \(type)")
}

@main struct Checks {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.first == "--log-worker", args.count == 3 {
            let logger = DiagnosticLog(directory: URL(fileURLWithPath: args[1]), maxBytes: 1024)
            for index in 0..<200 {
                guard logger.record("test.processWriter", ["writer": args[2], "index": index]) else { exit(1) }
            }
            logger.flush()
            return
        }
        let checks: [(String, () throws -> Void)] = [
            ("login item first registration and bundle boundary", loginItemFirstRegistrationIsAvailableInAppBundle),
            ("login item system status and approval", loginItemUsesSystemStatusAndHandlesApproval),
            ("login item registration/removal failures", loginItemFailuresNeverPretendRegistrationSucceeded),
            ("coordinates and lifts", decodesCoordinatesAndLiftContacts),
            ("ten-contact hybrid frames", assemblesTenContactHybridFrames),
            ("incomplete scan recovery", dropsIncompleteFramesWhenScanChanges),
            ("malformed reports", rejectsMalformedReportsAndDuplicates),
            ("packaged profile", profileIsPackaged),
            ("packaged model catalog and verification status", bundledModelCatalogSeparatesVerifiedSupport),
            ("exact model names and ambiguity", modelNamesRequireExactTokensAndRejectAmbiguity),
            ("unverified model selection boundaries", candidateModelsNeverBecomeAutomaticInputTargets),
            ("catalog schema and conflicting entries", catalogRejectsInvalidAndConflictingEntries),
            ("live EXC3200 contacts and lift", decodesLiveEXC3200Packets),
            ("tap lifecycle", tapDoesNotPressUntilLift),
            ("cancelled drag release", cancelledDragAlwaysReleasesButton),
            ("scroll lifecycle", twoFingerScrollHasPhasesAndNoAccidentalClick),
            ("sequential two-finger lift", sequentialTwoFingerLiftRightClicksOnce),
            ("pinch lifecycle", pinchIsOptInAndLatchesUntilLift),
            ("disabled pinch suppression", disabledPinchCannotBecomeRightClick),
            ("third-finger cancellation", addedThirdFingerCancelsDragWithoutClick),
            ("three-finger cumulative phases and axis lock", threeFingerSwipeHasCumulativePhasesAndAxisLock),
            (
                "sequential three-finger placement and lift",
                threeFingerSwipePromotesSequentialPlacementAndSuppressesLift
            ),
            ("scroll-to-swipe suppression", thirdFingerNeverConvertsActiveScrollToNavigation),
            ("three-finger coherence, taps and opt-out", incoherentThreeFingerMotionAndTapsDoNothing),
            ("swipe unexpected contact cancellation", swipeCancelsOnFourthFingerAndContactReplacement),
            ("swipe reversal and paused lift", swipeReversalAndPausedLiftHaveNoStaleVelocity),
            ("packed swipe HID layout", swipeHIDPayloadHasPackedLayoutAndVelocityChild),
            ("Dock event compatibility round trips", dockSwipeEventsRoundTripBothCompatibilityPaths),
            ("Dock event invalid input rejection", dockSwipeRejectsInvalidValuesAndUnknownSerialization),
            ("swipe event routing and display location", swipePostsPairedSessionEventsAtMappedDisplayLocation),
            ("vertical native Dock action commits", verticalSwipeCommitsNativeDockActionsOnceOnLift),
            ("vertical Dock action cancellation", verticalSwipeAbortShortTravelAndInvalidInputDoNotToggleDock),
            ("concurrent JSON logging", loggerWritesCompleteConcurrentJSONRecords),
            ("bounded log rotation", loggerRotationRetainsReadableBoundedFiles),
            ("concurrent log rotation", loggerCoordinatesMultipleWritersAcrossRotation),
            ("multi-process log rotation", loggerCoordinatesProcessWriters),
            ("oversized log records and recovery", loggerBoundsOversizedRecordsAndRecoversFromInvalidFields),
            ("session permission gates", sessionPermissionsAreCheckedBeforeOpening),
            ("session display validation", sessionRejectsUnsupportedGeometry),
            ("duplicate session start", duplicateStartPreservesActiveDrag),
            ("failed session startup", failedStartClearsReaderAndCallbacks),
            ("idempotent stop and drag release", sessionStopIsIdempotentAndReleasesDrag),
            ("permission revocation", revokedPermissionsStopBeforeNewInput),
            ("display configuration change", displayChangesStopBeforeNewInput),
            ("stalled gesture suppression", stalledGestureCannotBecomeAnotherClick),
            ("idle timeout", idleTimeoutDoesNotSuppressFirstTouch),
            ("decode failure suppression", decodeErrorReleasesAndSuppressesResidualContacts),
            ("disconnect restoration error", disconnectKeepsRestoreFailureVisible),
            ("native swipe lifecycle failures and opt-out", sessionFailuresCancelNativeSwipeExactlyOnce),
            ("monitor sleep input recovery", inputRecoversAfterControllerSleepWithoutAppRestart),
            ("recovery Stop/contact/suspension boundaries", recoveryRespectsStopContactTestsAndSuspension),
            ("bounded reopen retry", recoveryBacksOffTransientReopenFailures),
            ("recovery environment validation", recoveryRevalidatesPermissionsAndDisplayBeforeResuming),
            ("stable display identity", displayUUIDSurvivesChangedIDAndRejectsReusedIDs),
            ("hardware loss before session snapshots", hardwareLossStopsInputBeforeSessionSnapshotsChange),
            ("display/USB attachment ordering", attachOrdersRequireBothDisplayAndController),
            ("independent sleep and lock suspension", independentSuspensionReasonsMustAllClear),
            ("display coordinate mapping", eventCoordinatesRespectDisplayOriginAndEdges),
            ("click count boundaries", clickCountsDoNotLeakAcrossRightClickAndDrag),
            ("scroll event fields", scrollEventsRetainPhaseAndFractionalDeltas),
            ("window drag capture and moved geometry", windowRoutingLocksDragsAndTracksMovedWindows),
            ("window disappearance and ID reuse", windowRoutingDoesNotRetargetMissingOrReusedWindows),
            ("window scroll capture and cancellation", windowRoutingLocksScrollAndRequiresNewBeginAfterCancel),
            ("window activation ordering and revalidation", windowRoutingActivationPreservesOrderAndRevalidates),
            ("window hit order and click boundaries", windowRoutingHitOrderClickCountsAndInvalidGeometry),
            ("stationary input bypasses global pointer", stationarySinkBypassesGlobalPointerPosting),
            ("window pinch capture and event boundaries", windowRoutingLocksPinchAndIgnoresUnexpectedEventTypes),
            ("quick cross-app activation ordering", windowRoutingSerializesQuickTouchesAcrossApplications),
            ("stop discards queued stationary input", windowRoutingCancelsQueuedInputWhenSessionIsReleased),
        ]
        var failures = 0
        for (name, check) in checks {
            do {
                try check()
                print("PASS \(name)")
            } catch {
                failures += 1
                print("FAIL \(name): \(error)")
            }
        }
        print("\(checks.count - failures)/\(checks.count) checks passed")
        if failures > 0 { exit(1) }
    }
}
