// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu
// SPDX-License-Identifier: MIT

import ZenTouchCore

public struct ReportStatistics: Equatable {
    public let reports: Int
    public let frames: Int
    public init(reports: Int = 0, frames: Int = 0) {
        self.reports = reports
        self.frames = frames
    }
    public var fields: [String: Int] { ["reports": reports, "frames": frames] }
}

public protocol TouchReading: AnyObject {
    var onFrame: ((TouchFrame) -> Void)? { get set }
    var onReport: ((ReportStatistics) -> Void)? { get set }
    var onDisconnect: (() -> Void)? { get set }
    var onError: ((String) -> Void)? { get set }
    var onMultitouchObserved: (() -> Void)? { get set }
    var statistics: ReportStatistics { get }
    var modeWarning: String? { get }
    func start(seize: Bool, multitouch: Bool) throws
    @discardableResult func stop() -> String?
}
