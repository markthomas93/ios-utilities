//
//  CoalescingAction.swift
//  FueledUtils
//
//  Created by Stéphane Copin on 4/22/16.
//  Copyright © 2016 Fueled. All rights reserved.
//

import ReactiveSwift

///
/// Similar to `Action`, except if the action is already executing, subsequent `apply()` call will not fail,
/// and will be completed with the same output when the initial executing action completes.
/// Disposing any of the `SignalProducer` returned by 'apply()` will cancel the action.
///
public class CoalescingAction<Output, Error: Swift.Error>: ActionProtocol {
	public typealias Input = Void

	private let action: Action<Input, Output, Error>
	private var observer: Signal<Output, Error>.Observer?

	private class DisposableContainer {
		private let disposable: Disposable
		private var count = Atomic(0) {
			willSet {
				if self.count.value == 0 {
					self.disposable.dispose()
				}
			}
		}

		init(_ disposable: Disposable) {
			self.disposable = disposable
		}

		func add(_ lifetime: Lifetime) {
			lifetime.observeEnded {
				self.count.value -= 1
			}
		}
	}
	private var disposableContainer: DisposableContainer?

	///
	/// Whether the action is currently executing.
	///
	public var isExecuting: Property<Bool> {
		return self.action.isExecuting
	}

	///
	/// Whether the action is currently executing.
	///
	public let isEnabled = Property<Bool>(value: true)

	///
	/// A signal of all events generated from all units of work of the `Action`.
	///
	/// In other words, this sends every `Event` from every unit of work that the `Action`
	/// executes.
	///
	public var events: Signal<Signal<Output, Error>.Event, Never> {
		return self.action.events
	}

	///
	/// A signal of all values generated from all units of work of the `Action`.
	///
	/// In other words, this sends every value from every unit of work that the `Action`
	/// executes.
	///
	public var values: Signal<Output, Never> {
		return self.action.values
	}

	///
	/// A signal of all errors generated from all units of work of the `Action`.
	///
	/// In other words, this sends every error from every unit of work that the `Action`
	/// executes.
	///
	public var errors: Signal<Error, Never> {
		return self.action.errors
	}

	///
	/// The lifetime of the `Action`.
	///
	public var lifetime: Lifetime {
		return self.action.lifetime
	}

	///
	/// Initializes a `CoalescingAction`.
	///
	/// When the `Action` is asked to start the execution with an input value, a unit of
	/// work — represented by a `SignalProducer` — would be created by invoking
	/// `execute` with the input value.
	///
	/// - parameters:
	///   - execute: A closure that produces a unit of work, as `SignalProducer`, to be
	///              executed by the `Action`.
	///
	public init(execute: @escaping () -> SignalProducer<Output, Error>) {
		self.action = Action(execute: execute)
	}

	///
	/// Create a `SignalProducer` that would attempt to create and start a unit of work of
	/// the `Action`. The `SignalProducer` would forward only events generated by the unit
	/// of work it created.
	///
	/// - Parameters:
	///   - input: Must be `()`.
	///
	/// - Returns: A producer that forwards events generated by its started unit of work. If the action was already executing, it will create a `SignalProducer`
	///   that will forward the events of the initially created `SignalProducer`.
	///
	public func apply(_ input: Input) -> SignalProducer<Output, Error> {
		if self.isExecuting.value {
			return SignalProducer { [disposableContainer, weak self] observer, lifetime in
				disposableContainer?.add(lifetime)
				lifetime += self?.action.events.observeValues { event in
					observer.send(event)
				}
			}
		}

		return SignalProducer<Output, Error> { observer, lifetime in
			self.observer = observer
			let disposable = self.action.apply(input).flatMapError { error in
				guard case .producerFailed(let innerError) = error else {
					return SignalProducer.empty
				}

				return SignalProducer(error: innerError)
			}.start(observer)
			let disposableContainer = DisposableContainer(disposable)
			disposableContainer.add(lifetime)
			self.disposableContainer = disposableContainer
		}
	}
}
