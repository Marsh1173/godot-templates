extends Area3D
class_name Interactable

enum ContextualId {
	None
}

@export var interact_prompt: String
@export var contextual_id: ContextualId = ContextualId.None

signal on_attempt_interact(interactor: InteractorComponent)
#signal on_attempt_stop_interact(interactor: InteractorComponent)

# Called on host only
func attempt_interact(interactor: InteractorComponent, _interact_context_key: String):
	on_attempt_interact.emit(interactor)

#func attempt_stop_interact(interactor: InteractorComponent):
	#if not MyUtils.is_authority(multiplayer):
		#assert(false, "request_interact must be called on authority")
		#return
	#on_attempt_stop_interact.emit(interactor)
