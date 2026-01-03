class_name AwaitUtils

class _Awaiter:
	signal any_finished

	func call_async(callable: Callable) -> void:
		await callable.call()
		any_finished.emit()

static func await_any(callables: Array[Callable]) -> void:
	var awaiter := _Awaiter.new()

	for callable in callables:
		awaiter.call_async(callable)

	await awaiter.any_finished
