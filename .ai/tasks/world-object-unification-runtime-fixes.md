# Task: Fix Runtime Regressions From World Object Unification

## Goal

Fix the concrete runtime / script reload regressions reported after the world object unification pass, without changing the intended unified architecture.

The world-object migration itself should stay in place. This task is about correcting the implementation so the runtime path is clean and warnings/errors are resolved where appropriate.

## Reported Issues

### 1. Type mismatch in `WorldPropDefinition.build_collision_rects()`

Observed error:

```text
Trying to return an array of type "Array" where expected return type is "Array[Dictionary]".
world_prop_definition.gd:70 @ build_collision_rects()
```

This is reached through:
- `world_object_manager.gd:_spawn_world_object_visual()`
- `world_object_manager.gd:_register_world_object_instance()`
- `world_object_manager.gd:apply_chunk_objects()`
- `chunk_manager.gd:_apply_chunk()`

Required outcome:
- return typing must be correct
- no runtime type mismatch at this call site

### 2. Shadowed variable warning in `world_prop_definition.gd`

Observed warning:

```text
The local variable "placement_variants" is shadowing an already-declared variable at line 17 in the base class "WorldObjectDefinition".
```

Required outcome:
- remove the shadowing warning cleanly

### 3. Integer division warning in `world_object_manager.gd`

Observed warning:

```text
Integer division. Decimal part will be discarded.
world_object_manager.gd:374
```

Required outcome:
- make the intended numeric behavior explicit
- no ambiguous integer division warning

### 4. Unused signal warning in `chunk_manager.gd`

Observed warning:

```text
The signal "breakable_world_visual_detached" is declared but never explicitly used in the class.
chunk_manager.gd:4
```

Required outcome:
- either wire the signal into real behavior again, or remove it if the world-object path has made it obsolete
- do not leave dead compatibility artifacts behind without reason

## Constraints

- keep the unified world object architecture
- do not revert the world-object migration
- do not introduce parallel legacy code paths just to silence the warnings
- preserve break visuals and detached-break feedback behavior if it is still needed

## Validation

At minimum:
- headless Godot parse / boot checks should pass
- the reported runtime error must be gone
- the listed reload warnings should be resolved or intentionally removed

## Review Focus

Reviewer should prioritize:
- whether the fixes are minimal and correct
- whether any fix accidentally reintroduces old prop-vs-structure split logic
- whether break-visual behavior regressed when handling detached visuals
