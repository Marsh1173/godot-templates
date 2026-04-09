extends Area3D
class_name Interactable

enum ContextualId {
	None
}

@export var interact_prompt: String
@export var contextual_id: ContextualId = ContextualId.None

# We can't specify `: InteractorComponent` because it would create a circular dependency
signal on_attempt_interact(interactor)

# Called on host only
# We can't specify `: InteractorComponent` because it would create a circular dependency
func attempt_interact(interactor, _interact_context_key: String):
	on_attempt_interact.emit(interactor)

#func attempt_stop_interact(interactor: InteractorComponent):
	#if not MyUtils.is_authority(multiplayer):
		#assert(false, "request_interact must be called on authority")
		#return
	#on_attempt_stop_interact.emit(interactor)
