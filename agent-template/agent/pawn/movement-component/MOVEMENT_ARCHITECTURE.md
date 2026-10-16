# Multiplayer Movement Architecture

This document describes how player movement is synchronized between the host and connected clients.

---

## Overview

The system uses **server-authoritative tick-based reconciliation** for standard WASD movement and jump, and **server-authoritative forced movement** for abilities like Roll, knockback, or teleports.

There are two design pillars:

1. **Client predicts WASD + Jump immediately** so local movement feels instant regardless of ping.
2. **The server is the single source of truth** for all position, velocity, and ability state.

---

## Key Files

| File                                                                  | Role                                                                                              |
| :-------------------------------------------------------------------- | :------------------------------------------------------------------------------------------------ |
| `agent/controller/local-player-controller/local-player-controller.gd` | Polls hardware input, manages camera, sends actions                                               |
| `agent/controller/controller.gd`                                      | Serializes and routes Actions to host via reliable RPC                                            |
| `agent/controller/state-replicator/state-replicator.gd`               | Replicates look direction (pitch/yaw) from owning client to all peers via MultiplayerSynchronizer |
| `agent/pawn/pawn.gd`                                                  | Receives Actions on host; dispatches ability logic (e.g. Roll cooldown, stamina cost)             |
| `agent/pawn/movement-component/movement_component.gd`                 | Pure physics + network reconciliation engine                                                      |

---

## Two Input Channels

### Channel 1 — Tick Input Packets (WASD + Jump)

Sent every physics tick from `MovementComponent` via **unreliable RPC** directly to the host:

```
{ id, vector, yaw, jump }
```

- Unreliable because a newer packet always supersedes an older one.
- Each packet carries a monotonically incrementing `id` used for reconciliation.
- The host queues these in a **jitter buffer** and processes exactly one per tick to maintain smooth playback.

### Channel 2 — Actions (Sprint, Roll, Interact, Abilities)

Sent via **reliable RPC** through `Controller.queue_action()` when a key event fires:

```
Action.Name.StartSprint / StopSprint / Roll / StartPrimaryAbility / ...
```

- Reliable because these are discrete events that must not be dropped.
- The host validates and executes them (e.g., checks stamina and cooldowns before allowing a Roll).
- The client does **not** predict these locally, avoiding stamina desync and ability replay bugs.

---

## Client Prediction (WASD + Jump)

Every physics tick on the local client:

1. Sample `Input.get_vector()` and `Input.is_action_pressed("jump")`.
2. Tag the input with an incrementing `current_input_id`.
3. Send to host via unreliable RPC.
4. Run `simulate_step(input, delta)` locally — identical physics math to the server.
5. Record `{ id, input, position, velocity }` in `input_history`.

This means the client's character moves instantly with no perceived ping.

---

## Server Simulation

The server maintains a **jitter buffer** of incoming client inputs and processes them one at a time. One input consumed = one snapshot broadcast.

This protects against network delivery jitter (packets arriving in bursts) causing visible stuttering. If the queue builds up, the server processes 2 inputs in a single tick to catch up.

The server broadcasts an authoritative snapshot after each processed tick:

```
[ pos.x, pos.y, pos.z, vel.x, vel.y, vel.z, rot_y, ack_input_id, is_sprinting, is_forced_movement ]
```

---

## Reconciliation (Rollback & Replay)

When a snapshot arrives on the client:

1. Look up `ack_input_id` in `input_history`.
2. Compare server position against the historically predicted position for that tick.
3. **If difference ≤ 20 cm:** Prediction was good enough. Discard acknowledged history. No visual change.
4. **If difference > 20 cm:** Genuine desync (wall collision, packet loss, lag spike).
   - Snap position and velocity to the server's state (rollback).
   - Re-simulate all remaining unacknowledged inputs forward to the present (replay).
   - Update saved history positions from the replay.

The 20 cm threshold filters out normal floating-point variance from `move_and_slide()` while still catching true desyncs.

---

## Server-Authoritative Forced Movement

For any movement the server needs to drive directly (Roll, TNT knockback, launch pads, teleports):

1. The host calls `movement_component.start_forced_movement(velocity, duration)`.
2. The host replicates `is_forced_movement = true` in the snapshot.
3. On the client, prediction is **suspended** while `is_forced_movement` is active:
   - The client adopts the server's position and velocity directly each snapshot.
   - `input_history` is cleared to prevent stale WASD replays from fighting the forced trajectory.
4. When `is_forced_movement` ends on the server, the client snaps to the final landing state and resumes normal prediction.

This is how Roll, and any future abilities with physics, are implemented without jitter.

### Adding a New Movement Ability

In `Pawn.handle_action()`, handle the new `Action.Name`, check costs/cooldowns, then call:

```gdscript
movement_component.start_forced_movement(direction * speed, duration)
```

`MovementComponent` does not need to know anything about the ability itself.

---

## Look Direction (Pitch / Yaw)

The camera pivot is driven locally by mouse input in `LocalPlayerController`. The current yaw is included in every tick input packet so the server can orient the pawn for movement and ability direction calculations. Pitch and yaw are also replicated via `ControllerStateReplicator` (MultiplayerSynchronizer) so all peers see the pawn facing the right way.

---

## Remote Observers (Other Players' Pawns)

Peers who do not own a pawn receive snapshots and apply them directly — no prediction, no reconciliation. Forced movement is also applied directly.

---

## Sprint

Sprint is server-authoritative. Pressing Shift sends a reliable `StartSprint` action to the host. The host checks stamina and sets `is_sprinting`, which is included in the snapshot. The client does not speed up until the host confirms. This prevents stamina desync where the host runs out of stamina before the client receives the updated value.

# More notes from Nate

### What is_forced_movement Is Actually For

The timer isn't what makes forced movement special. The critical thing is overriding apply_movement() for its duration. Look at what apply_movement() does every tick:
var final_pawn_v = flattened_pawn_v.move_toward(velocity_vector, delta \* accel)

move_toward() aggressively decelerates the character back toward WASD input every single tick at 70 m/s². If you set velocity to 14 m/s for a roll and don't suppress apply_movement(), it's killed
back to walking speed within 2 frames. The timer exists purely to keep apply_movement() from fighting the roll while it lasts.
──────

### TNT / Instant Impulse — No Forced Movement Needed

For an instant blast, you just do on the server:
pawn.velocity = explosion_direction \* explosion_force

Then broadcast the snapshot normally with is_forced_movement = false. The client receives it, reconciles to the blast velocity, replays its unacknowledged WASD inputs — and during that replay,
apply_movement() naturally decelerates from the blast trajectory. That's exactly the right behavior! The character gets launched and stumbles back to normal speed as they regain control.

No need for start_forced_movement() at all.
──────

### When You DO Need is_forced_movement

Only when you need to sustain a specific velocity trajectory against what WASD physics would do:

• Roll / Dash — maintain a fixed direction + speed for N frames
• Grapple hook — pull toward a point over time
• Conveyor / wind zone — constantly push while the player is inside

If it's a one-shot velocity set (TNT, jump pad, knockback), skip it entirely.
