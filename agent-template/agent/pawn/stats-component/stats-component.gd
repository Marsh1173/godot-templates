extends Node
class_name StatsComponent

# Movement
@onready var move_speed: Stat = $MoveSpeed
@onready var max_health: Stat = $MaxHealth
@onready var jump_height: Stat = $JumpHeight
@onready var sprint_speed_multiplier: Stat = $SprintSpeedMultiplier

# Stamina
@onready var max_stamina: Stat = $MaxStamina
@onready var stamina_regen_rate: Stat = $StaminaRegenRate
@onready var stamina_regen_interrupt_length: Stat = $StaminaRegenInterruptLength

# Inventory
@onready var inventory_size: Stat = $InventorySize
