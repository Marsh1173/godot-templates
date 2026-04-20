# Hex WFC Map Generator

A procedural hex-based terrain generator for Godot 4.6 using **Wave Function Collapse (WFC)**. Based on [felixturner/hex-map-wfc](https://github.com/felixturner/hex-map-wfc).

---

## Table of Contents

1. [What is WFC?](#what-is-wfc)
2. [Quick Start](#quick-start)
3. [Architecture Overview](#architecture-overview)
4. [Complete Algorithm Flow](#complete-algorithm-flow)
5. [File Structure](#file-structure)
6. [How Tiles Work](#how-tiles-work)
7. [How Edges and Constraints Work](#how-edges-and-constraints-work)
8. [How the Solver Works (Detailed)](#how-the-solver-works-detailed)
9. [Multi-Chunk Generation](#multi-chunk-generation)
10. [Threading Model](#threading-model)
11. [Adding New Tiles](#adding-new-tiles)
12. [Adding New Edge Types](#adding-new-edge-types)
13. [Tuning Generation](#tuning-generation)
14. [Doodads and Decorations](#doodads-and-decorations)
15. [Troubleshooting](#troubleshooting)

---

## What is WFC?

Wave Function Collapse is a procedural generation algorithm inspired by quantum mechanics. Imagine each cell on the map starts as a "superposition" of every possible tile -- grass, water, road, forest, etc. The algorithm repeatedly:

1. **Observes** the most constrained cell (fewest options) and "collapses" it to one tile.
2. **Propagates** that choice to neighbors: removes any neighbor options that don't match the chosen tile's edges.
3. **Repeats** until every cell has exactly one tile.
4. **Backtracks** if it hits a dead end (a cell with zero options).

The result is a fully coherent map where every tile's edges match its neighbors -- roads connect to roads, coasts transition between land and water, rivers flow through grass, etc.

---

## Quick Start

1. Open your Godot scene.
2. Instance `hex-wfc-manager.tscn` (or add an `HexWFCManager` node and attach `hex-wfc-manager.gd`).
3. Configure in the Inspector:
   - `generation_seed`: Set a specific seed, or leave at 0 for random.
   - `grid_radius`: Number of rings from center (5 = 91 tiles, 10 = 331 tiles).
   - `chunk_count`: 1 (single grid), 7 (center + ring), or 19 (center + 2 rings).
   - `auto_generate`: If true, generates on scene load.
4. Run the scene. Hex tiles should appear.

Or add it to the existing `map-demo.tscn`:
- Add `HexWFCManager` as a child of `MapDemo`.
- Optionally hide the existing `Ground` plane.

---

## Architecture Overview

```
HexWFCManager (Node3D)          <-- Add this to your scene
├── HexTileRegistry             <-- Loads all tile definitions from data/tiles/
├── HexTileRenderer (Node3D)    <-- Renders solved grid as 3D scene nodes
│   └── [tile instances...]     <-- One Node3D per hex tile
├── Thread                      <-- Background solver thread
│   └── HexWFCSolver            <-- The WFC algorithm
│       ├── HexGrid             <-- Cell storage (Dictionary[Vector3i, Cell])
│       ├── HexWFCAdjacency     <-- Precomputed edge compatibility index
│       ├── HexWFCBacktracker   <-- Trail-based undo system
│       └── SeededRandom        <-- Deterministic PRNG
└── HexDoodadPlacer             <-- Post-solve decoration placement
```

---

## Complete Algorithm Flow

Here's the full flow from "scene enters tree" to "map visible on screen":

```
1. SCENE LOAD
   HexWFCManager._ready()
   ├── Create HexTileRegistry
   │   └── Scan data/tiles/ directory
   │   └── Load each .tres as HexTileType
   │   └── Build lookup maps (by_id, by_name)
   ├── Create HexTileRenderer (add as child node)
   └── Call generate() (if auto_generate is true)

2. GENERATE
   HexWFCManager.generate()
   ├── Pick seed (use generation_seed, or system time if 0)
   ├── Compute chunk offsets (hex layout for 1/7/19 chunks)
   ├── For each chunk: create HexWFCSolver
   │   └── HexWFCSolver._init()
   │       ├── Create SeededRandom with chunk-specific seed
   │       ├── Create HexGrid with configured radius
   │       ├── Create HexWFCBacktracker
   │       └── Build HexWFCAdjacency index:
   │           ├── For each tile type:
   │           │   For each valid rotation:
   │           │     For each valid level:
   │           │       ├── Create state key (packed int)
   │           │       ├── Compute edge type + level for all 6 directions
   │           │       └── Add to index: edge_type -> direction -> level -> [state_keys]
   │           └── Store state weights for entropy calculation
   └── Start background Thread running _thread_solve()

3. SOLVE (on background thread)
   HexWFCSolver.solve()
   ├── Initialize cells: each cell gets ALL possible state keys
   ├── Apply boundary constraints (multi-chunk only)
   └── Main loop:
	   │
	   ├── OBSERVE: Find lowest-entropy uncollapsed cell
	   │   ├── Iterate all cells, skip collapsed ones
	   │   ├── Compute entropy with noise tie-breaking
	   │   └── Return cell with minimum entropy (or null if all collapsed = SUCCESS)
	   │
	   ├── COLLAPSE: Pick a state for the chosen cell
	   │   ├── Push decision onto backtrack stack (save cell's possibilities)
	   │   ├── Build weight array from cell's remaining possibilities
	   │   ├── Weighted random choice via SeededRandom
	   │   ├── Record all removed states in backtrack trail
	   │   └── Set cell to collapsed with chosen state
	   │
	   ├── PROPAGATE: Cascade constraints to neighbors
	   │   ├── Push collapsed cell onto propagation queue
	   │   └── While queue not empty:
	   │       ├── Pop cell from queue
	   │       ├── For each of 6 directions:
	   │       │   ├── Get neighbor cell (skip if null/collapsed)
	   │       │   ├── Build "allowed set":
	   │       │   │   For each state in current cell's possibilities:
       │       │   │     Get edge info (type + level) in this direction
       │       │   │     Look up all compatible states in adjacency index
       │       │   │     Add them to allowed set
       │       │   ├── Remove neighbor states NOT in allowed set
       │       │   │   (record each removal in backtrack trail)
       │       │   ├── If neighbor has 0 possibilities: CONTRADICTION -> backtrack
       │       │   └── If neighbor was modified: push to queue (cascade)
       │       └── Return success (no contradictions)
       │
       └── BACKTRACK (if contradiction):
           ├── Pop last decision from stack
           ├── Undo all trail entries since that decision (restore removed states)
           ├── Restore collapsed cell to pre-collapse possibilities
           ├── Exclude the tried state
           ├── Pick a new untried state (weighted random)
           ├── Re-propagate from new choice
           └── If no untried states remain: backtrack further up the stack
               If stack is empty: FAIL (restart with new seed)

4. RENDER (back on main thread)
   HexWFCManager._on_solve_complete()
   ├── Thread.wait_to_finish()
   ├── For each chunk result:
   │   └── HexTileRenderer.render_grid(result, offset)
   │       ├── For each cell in result:
   │       │   ├── Look up tile type by ID -> get mesh_scene
   │       │   ├── Instantiate the PackedScene
   │       │   ├── Position via HexCoords.cube_to_world()
   │       │   ├── Rotate by rotation * 60 degrees
   │       │   └── Add as child of renderer node
   │       └── Store node reference in _tile_nodes dictionary
   └── Emit generation_completed signal
```

---

## File Structure

```
map-generator/
│
├── hex-wfc-manager.gd          # Top-level orchestrator (add to scene)
├── hex-wfc-manager.tscn        # Ready-to-use scene
├── README.md                   # This file
│
├── core/                       # WFC algorithm implementation
│   ├── hex-wfc-solver.gd       # Main solve loop (observe/propagate/backtrack)
│   ├── hex-wfc-cell.gd         # Cell state: possibilities, entropy, collapse
│   ├── hex-wfc-adjacency.gd    # Precomputed edge compatibility index
│   ├── hex-wfc-backtracker.gd  # Trail-based undo system
│   └── seeded-random.gd        # Mulberry32 deterministic PRNG
│
├── data/                       # Tile definitions
│   ├── hex-tile-type.gd        # Resource class for tile definitions
│   ├── hex-tile-state.gd       # State key encoding/decoding
│   ├── hex-edge-type.gd        # Edge type enum
│   ├── hex-tile-registry.gd    # Auto-loads all .tres files
│   └── tiles/                  # One .tres file per tile type
│       ├── grass.tres
│       ├── water.tres
│       ├── coast-1.tres        # 1 water edge (concave coast)
│       ├── coast-2.tres        # 2 water edges (straight coast)
│       ├── coast-3.tres        # 3 water edges (convex coast)
│       ├── road-straight.tres
│       ├── road-curve.tres
│       ├── road-t.tres         # T-junction
│       ├── forest.tres
│       ├── forest-edge.tres    # Transition between forest and grass
│       ├── cliff.tres          # Elevation change
│       └── river-straight.tres
│
├── hex/                        # Hex grid math utilities
│   ├── hex-direction.gd        # Direction enum (NE,E,SE,SW,W,NW)
│   ├── hex-coords.gd           # Cube coordinates, world position conversion
│   └── hex-grid.gd             # Grid data structure
│
├── render/                     # 3D rendering
│   ├── hex-tile-renderer.gd    # Instantiates tile scenes from solve result
│   └── hex-doodad-placer.gd    # Places decorations on tiles
│
└── meshes/                     # Placeholder 3D hex tile scenes
    ├── hex-grass.tscn          # Green hexagon
    ├── hex-water.tscn          # Blue hexagon
    ├── hex-coast.tscn          # Sandy hexagon
    ├── hex-road.tscn           # Gray hexagon
    ├── hex-forest.tscn         # Dark green hexagon
    ├── hex-cliff.tscn          # Brown hexagon (taller)
    └── hex-river.tscn          # Blue-green hexagon
```

---

## How Tiles Work

Each tile type is defined as a Godot Resource (`.tres` file) with these properties:

| Property | Type | Description |
|----------|------|-------------|
| `tile_name` | StringName | Unique name (e.g., `&"grass"`) |
| `tile_id` | int | Unique integer ID (used in state key encoding) |
| `edges` | Dictionary | 6 entries mapping direction -> edge type at rotation 0 |
| `weight` | float | How common this tile is (higher = more frequent) |
| `mesh_scene` | PackedScene | The 3D scene to instantiate |
| `level_increment` | int | Elevation change (0=flat, 1=slope) |
| `high_edges` | Array[int] | Which edges are at the elevated level |
| `prevent_chaining` | bool | Prevent adjacent same-type tiles |
| `symmetry` | int | Rotational symmetry (6=uniform, 3=180-deg, 1=all unique) |
| `walkable` | bool | For future navigation mesh generation |

### Edge Dictionary Format

The `edges` dictionary maps HexDirection.Dir values to HexEdgeType.Type values:

```
edges = { 0: 0, 1: 2, 2: 0, 3: 0, 4: 2, 5: 0 }
         NE:GRASS E:ROAD SE:GRASS SW:GRASS W:ROAD NW:GRASS
```

This defines the tile at rotation 0. The solver rotates the edges to create
rotated variants (e.g., at rotation=1, the E:ROAD becomes SE:ROAD).

### Symmetry

Symmetry reduces the number of rotations the solver considers:
- `symmetry=6`: All rotations look the same (e.g., all-grass). Only rotation 0 is used.
- `symmetry=3`: 180-degree symmetric (e.g., straight road E-W). Rotations 0,1,2 are unique.
- `symmetry=1`: All 6 rotations are different (e.g., curved road). All used.

---

## How Edges and Constraints Work

### The Core Rule

**Two adjacent tiles are compatible if their touching edges have the same type AND the same level.**

Exception: **GRASS edges match at any level** (level-agnostic), allowing natural elevation changes.

### Edge Types

| Type | Value | Description |
|------|-------|-------------|
| GRASS | 0 | Basic terrain. Level-agnostic. |
| WATER | 1 | Open water. |
| ROAD | 2 | Paths/roads. |
| RIVER | 3 | Flowing water. |
| COAST | 4 | Land-water transition. |
| CLIFF | 5 | Vertical terrain drop. |
| CLIFF_ROAD | 6 | Cliff with road. |
| FOREST | 7 | Dense tree coverage. |

### Example: How Coast Tiles Bridge Land and Water

```
GRASS tile (all grass edges) -- can neighbor:
  ├── Another GRASS tile (grass-grass match)
  ├── COAST_1 tile on its grass side (grass-grass match)
  ├── ROAD tile on its grass sides (grass-grass match)
  └── FOREST_EDGE on its grass side (grass-grass match)

COAST_1 tile (3 grass, 1 water, 2 coast edges) -- can neighbor:
  ├── GRASS on its grass sides
  ├── WATER on its water side (water-water match)
  ├── Other COAST tiles on its coast sides (coast-coast match)
  └── Cannot neighbor ROAD on its water side (water ≠ road)

WATER tile (all water edges) -- can neighbor:
  ├── Another WATER tile (water-water match)
  └── COAST tiles on their water sides (water-water match)
```

This creates natural terrain transitions without explicit transition rules.

---

## How the Solver Works (Detailed)

### State Keys

A "state" is a (tile_type_id, rotation, level) triple, packed into a single integer:

```
state_key = tile_type_id * 48 + rotation * 8 + level
```

With 12 tile types, 6 rotations, and 5 levels (0-4), that's up to 360 states per cell.

### Entropy

Shannon entropy measures uncertainty. The solver always collapses the cell with the **lowest entropy** first (most constrained). This minimizes contradictions.

Formula: `entropy = log(sum_of_weights) - sum(w * log(w)) / sum_of_weights`

Tiles with higher weights contribute more entropy. A cell with only low-weight options has low entropy and gets collapsed first.

### Propagation

When a cell is collapsed, its neighbors must be updated. For each neighbor:

1. For each state the current cell *could* be, get the edge it exposes toward the neighbor.
2. For each such edge, look up all states that have a compatible opposite edge (from the precomputed adjacency index).
3. The union of all those compatible states is the "allowed set."
4. Remove any neighbor state NOT in the allowed set.
5. If the neighbor changed, propagate to ITS neighbors too (cascade).

This cascading effect is what makes WFC produce globally-coherent output from local rules.

### Backtracking

When propagation creates a cell with zero possibilities (contradiction):

1. **Pop** the last collapse decision from the stack.
2. **Undo** all state removals recorded in the trail since that decision.
3. **Restore** the cell to its pre-collapse possibilities.
4. **Exclude** the state that failed and pick a different one.
5. If no states remain, pop further up the stack.

The trail records every individual state removal, so undoing is just replaying in reverse.

---

## Multi-Chunk Generation

For large maps, the system generates multiple hex grid "chunks":

```
chunk_count=1:   [C]              (1 chunk, just center)

chunk_count=7:   [1][2]           (7 chunks: center + 6 ring-1)
				[6][C][3]
				 [5][4]

chunk_count=19:  [7][8][9]        (19 chunks: center + 6 + 12)
			   [18][1][2][10]
			  [17][6][C][3][11]
			   [16][5][4][12]
				[15][14][13]
```

Chunks are solved **sequentially**. Each chunk's boundary cells are constrained to match the already-solved neighbors from previous chunks. This ensures seamless terrain across chunk boundaries.

---

## Threading Model

The solver runs on a **background thread** so the game doesn't freeze:

- **Main thread**: Creates solver, starts thread, polls progress, renders result.
- **Background thread**: Runs `solver.solve()` (pure computation, no scene tree access).
- **Communication**: `solver.progress` (float) is polled by main thread's `_process()`. When done, `call_deferred()` returns to the main thread for rendering.

Thread safety: The solver operates on its own data structures with no shared state. Only the progress float is read cross-thread.

---

## Adding New Tiles

1. **Create a .tres file** in `data/tiles/`. Copy an existing one as a template.

2. **Set a unique `tile_id`**. Check existing tiles to avoid duplicates.

3. **Define edges** at rotation 0. Use HexEdgeType values:
   ```
   GRASS=0, WATER=1, ROAD=2, RIVER=3, COAST=4, CLIFF=5, CLIFF_ROAD=6, FOREST=7
   ```

4. **Set weight** based on desired frequency. Compare to existing tiles:
   - Grass: 500 (very common), Forest: 150, Water: 200, Road: 20-30, Coast: 30-50

5. **Set symmetry** to avoid redundant rotations:
   - All edges the same? symmetry=6
   - Opposite edges mirror? symmetry=3
   - All different? symmetry=1

6. **Point `mesh_scene`** to a 3D scene in `meshes/` (or create a new one).

7. **Restart the game** -- the registry auto-discovers new .tres files.

### Example: Adding a River Curve Tile

```
tile_name = &"river_curve"
tile_id = 12
edges = { 0: 0, 1: 0, 2: 3, 3: 0, 4: 0, 5: 3 }   # River on SE and NW
weight = 20.0
symmetry = 1   # All 6 rotations are unique
```

---

## Adding New Edge Types

1. Add a new value to the `Type` enum in `data/hex-edge-type.gd`.
2. Add its name to the `NAMES` array.
3. If it should be level-agnostic (like GRASS), update `is_level_agnostic()`.
4. Create tiles that use the new edge type in their `edges` dictionary.

---

## Tuning Generation

### More of a specific terrain:
Increase its `weight` in the .tres file. Weight is relative -- doubling FOREST's weight doubles its frequency relative to other tiles.

### Less backtracking:
- Ensure every edge type has at least 2-3 tiles that expose it. If only one tile has RIVER edges, the solver will struggle to complete river connections.
- Reduce `max_level` to decrease the state space.
- Add "transition" tiles that bridge different terrain types.

### Bigger maps:
- Increase `grid_radius` (10 = 331 tiles, 20 = 1261 tiles).
- Use `chunk_count=7` or `chunk_count=19` for very large maps.

### Deterministic maps:
Set `generation_seed` to a specific non-zero value. Same seed + same tile definitions = identical map every time.

---

## Doodads and Decorations

The `HexDoodadPlacer` adds 3D decorations after the solve:

```gdscript
# In your scene script or manager customization:
var placer = HexDoodadPlacer.new()
placer.register_doodad(&"forest", [tree_scene_1, tree_scene_2], 0.8)  # 80% of forest tiles get a tree
placer.register_doodad(&"grass", [flower_scene, rock_scene], 0.3)     # 30% of grass tiles
placer.place_doodads(result, registry, parent_node, rng, hex_size, level_height)
```

Doodads get a random Y rotation and a small random XZ offset within the hex.

---

## Troubleshooting

### "HexTileRegistry: Cannot open tiles directory"
The path `res://map-template/map-generator/data/tiles/` must exist and contain .tres files.

### Solver fails / "Exceeded max backtrack count"
- Your tile set may have impossible constraint combinations.
- Make sure every edge type can be "terminated" -- e.g., if you have ROAD edges, include road-end tiles or make sure roads can loop.
- Try a different seed (set `generation_seed = 0` for random).

### All tiles are the same type
- Check that `prevent_chaining` is true for the dominant tile.
- Lower the dominant tile's weight or raise others.

### Tiles look misaligned
- Ensure all mesh scenes have their hexagon centered at origin.
- Mesh size should match `hex_size` (default outer radius = 1.0).
- CylinderMesh with 6 radial segments gives a flat-top hex.

### Performance is poor
- For grids over 500 tiles, consider implementing the MultiMesh rendering path.
- The solver itself is fast; rendering many individual scenes is the bottleneck.
- Reduce `grid_radius` or `chunk_count` for testing.
