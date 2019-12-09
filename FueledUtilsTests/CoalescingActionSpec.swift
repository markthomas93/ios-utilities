//
//  CoalescingActionSpec.swift
//  FueledUtilsTests
//
//  Created by Stéphane Copin on 10/15/19.
//  Copyright © 2019 Fueled. All rights reserved.
//

import Quick
import Nimble
import FueledUtils
import ReactiveSwift
import XCTest

class CoalescingActionSpec: QuickSpec {
	override func spec() {
		describe("CoalescingAction") {
			describe("apply().start()") {
				it("should start the action once for each apply() until completed") {
					var counter = 0
					let producer = SignalProducer<Void, Never> { observer, lifetime in
						counter += 1
						lifetime += SignalProducer(value: ()).delay(0.1, on: QueueScheduler.main).startWithValues { _ in
							observer.send(value: ())
							observer.sendCompleted()
						}
					}
					let action = CoalescingAction { producer }
					expect(counter) == 0
					action.apply().start()
					expect(counter) == 1
					action.apply().start()
					expect(counter) == 1
					action.apply().start()
				}
				it("should support chaining calls") {
					let action = InputCoalescingAction<Int, Int, Never> { input in
						SignalProducer<Int, Never> { observer, lifetime in
							lifetime += SignalProducer(value: ()).delay(0.1, on: QueueScheduler.main).startWithValues { _ in
								observer.send(value: input + 1)
								observer.sendCompleted()
							}
						}
					}
					var finalValue: Int?
					action.apply(0)
						.observe(on: QueueScheduler.main)
						.flatMap(.latest) {
							action.apply($0)
						}.startWithValues {
							finalValue = $0
						}

					// Input should be ignored and returns 1
					action.apply(2).startWithValues {
						expect($0) == 1
					}

					expect(finalValue).toEventually(equal(2))
				}
			}
			describe("apply.dispose()") {
				it("should dispose of all created signal producers") {
					var startCounter = 0
					var disposeCounter = 0
					var interruptedCounter = 0
					let coalescingAction = CoalescingAction {
						SignalProducer(value: 2.0)
							.delay(1.0, on: QueueScheduler.main)
							.on(
								started: {
									startCounter += 1
								},
								interrupted: {
									interruptedCounter += 1
								},
								disposed: {
									disposeCounter += 1
								}
							)
					}

					expect(startCounter) == 0

					let producersCount = 5
					let disposables = (0..<producersCount).map { _ in coalescingAction.apply().start() }

					expect(startCounter) == 1

					disposables[0].dispose()

					expect(disposeCounter) == 0
					expect(interruptedCounter) == 0

					disposables[1..<producersCount].forEach { $0.dispose() }

					expect(disposeCounter).toEventually(equal(1))
					expect(interruptedCounter).toEventually(equal(1))
				}
			}
		}
	}
}
