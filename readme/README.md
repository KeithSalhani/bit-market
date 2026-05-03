# Bit Market

Name: Keith Salhani

Student Number: C22322811

Class Group: TU984

# Description

Bit Market is a 3D restaurant management and automation simulation built in Godot 4.6. The project is set inside a low-poly/PSX-style burger restaurant where customers arrive, queue at cash registers, place orders, sit down, wait for food, eat, pay, and leave.

The main gameplay focus is the worker-driven restaurant pipeline. Workers can be hired and assigned roles such as cashier, meat griller, burger prepper, fries fryer, and caterer. Each worker pulls tasks from a shared task manager and uses navigation, station reservations, hand IK, food props, and kitchen station logic to complete the customer order flow.

The simulation includes burger assembly, meat grilling, fries frying, register queues, seat assignment, food storage, delivery, eating animations, money tracking, day/time progression, and a HUD/debug interface for observing the running system.

## Video

[![YouTube video placeholder](docs/screenshots/video-placeholder.png)](https://www.youtube.com/watch?v=TODO)

TODO: Replace this placeholder with the final demo video link.

## Screenshots

TODO: Add final screenshots to `readme/docs/screenshots/`.

![Main restaurant overview](docs/screenshots/main-restaurant-overview.png)

![Kitchen stations](docs/screenshots/kitchen-stations.png)

![Register queue and customers](docs/screenshots/register-queue.png)

![Worker activity HUD](docs/screenshots/worker-activity-hud.png)

![Customer eating flow](docs/screenshots/customer-eating-flow.png)

## Animations

TODO: Add final GIFs or short captured clips to `readme/docs/animations/`.

![Worker kitchen loop placeholder](docs/animations/worker-kitchen-loop.gif)

![Burger assembly placeholder](docs/animations/burger-assembly.gif)

![Fries frying placeholder](docs/animations/fries-frying.gif)

![Customer seating and eating placeholder](docs/animations/customer-seating-eating.gif)

## Audio

TODO: Add final audio demonstration clips to `readme/docs/audio/`.

- [Register payment sound placeholder](docs/audio/apple-pay-register.mp3)
- [Grill sound placeholder](docs/audio/grill-sizzle.mp3)
- [Fryer sound placeholder](docs/audio/fryer-oil.mp3)
- [Restaurant ambience placeholder](docs/audio/restaurant-ambience.mp3)

# Instructions

1. Install Godot `4.6.1` or a compatible Godot 4.6 build.
2. Open the project folder in Godot.
3. Run the default scene:

```text
res://scenes/world/burger_level.tscn
```

The main scene is already configured in `project.godot`.

## Controls

- `Open Restaurant`: starts the day and begins customer spawning.
- `Close Restaurant`: stops the restaurant from accepting new time progression.
- `Hire Worker ($100)`: hires another worker. The first worker is free.
- `Spawn Customer`: manually spawns a customer for testing.
- `Workers`: opens the worker activity panel.
- Worker role dropdowns: assign workers to Auto, Cashier, Meat Griller, Burger Prepper, Fries Fryer, or Caterer.

Free camera controls:

- `WASD`: move camera
- Right mouse drag: rotate camera
- `Space`: move up
- `Ctrl` or `C`: move down
- `Shift`: move faster
- `Esc`: release mouse / toggle debug behavior

# How It Works

The restaurant simulation is built around a set of managers and station scripts.

`RestaurantManager` tracks the restaurant state: money, day number, time of day, and whether the restaurant is open. Customers pay `$15.50` after they finish eating.

`CustomerManager` spawns customers, randomises their visual character, assigns them to available register slots, and manages register queue positions when all registers are occupied.

`CustomerAI` controls the full customer lifecycle. Customers enter, queue for a register, request an order task, show their selected order, find a seat, wait for delivery, receive food, eat, pay, and leave.

`TaskManager` is the central task queue. It creates and assigns tasks for processing orders, cooking meat, frying fries, assembling burgers, and delivering food. It also checks worker roles, station availability, station reservations, food availability, and delivery reservations.

`WorkerAI` runs on each worker NPC. Workers request tasks, travel to the correct station, snap into workstation positions, perform reach/IK interactions, carry food, stock the food table, and deliver the correct food type to customers.

Kitchen stations provide the physical food production logic:

- `GrillStation`: cooks batches of meat, shows meat props, and emits smoke particles while cooking.
- `BurgerAssemblyStation`: builds burgers from individual ingredient props, requires cooked meat stock, stores finished burgers, and exposes finished food for transport.
- `FryerStation`: lowers baskets, shows oil, spawns raw fries, emits oil bubble particles, and creates bagged fries.
- `FoodTableStation`: stores prepared food by type and exposes food lookup for delivery tasks.

Movement and interaction use Godot navigation, station markers, seat/register markers, and `SkeletonIK3D`-based reaching. Workers and customers use separate movement scripts so the simulation can run autonomously once the restaurant is open.

## RK/IK Worker Interaction

The worker kitchen interactions use a combination of regular keyframed character movement and procedural inverse kinematics. The worker still moves around the restaurant with the normal navigation and locomotion animations, but when they arrive at a workstation the right arm is controlled by a dedicated reach controller.

The main script for this is `src/movement/worker_reach_controller.gd`. It creates a `SkeletonIK3D` node at runtime, targets the worker skeleton from `RightUpperArm` to `RightHand`, and moves a hidden `RightHandIKTarget` node to world-space interaction points. The target is animated with tweens so the arm reaches smoothly rather than snapping.

This is used heavily at the prep station. The burger prep station has reach targets for ingredients such as meat, cheese, pickles, onion, lettuce, buns, and the final burger assembly point. For each ingredient, the worker reaches to the ingredient location, moves to the burger stack position, places the layer, and returns to a rest pose. The prep station also passes a custom hand rotation so the hand faces down toward the burger while placing ingredients.

The same reaching system is reused across other stations:

- At the grill, the worker reaches to pick/place raw meat and later reaches back to collect cooked meat.
- At the fryer, the worker reaches to basket handle markers before lowering and raising the baskets.
- At the food table, the worker reaches to place burgers/fries into storage slots.
- During delivery, food is attached to the worker hand with `BoneAttachment3D`, carried to the customer, then handed over.

I refer to this as RK/IK in the project notes because the final motion is a blend of authored/regular character motion and runtime IK correction. The body and navigation are driven normally, while the arm pose is procedurally solved toward exact station markers. This made the kitchen loop more convincing without needing a unique baked animation for every ingredient, station, and food item.

## Code Examples

### Role-Based Task Assignment

Workers do not directly decide what job to perform. Instead, `TaskManager` checks the worker's assigned role, station ownership, station availability, and task dependencies before assigning work.

```gdscript
func get_next_task(worker: Node) -> Task:
	if pending_tasks.is_empty():
		return null
	
	var ai = worker.get_node("WorkerAI") if worker.has_node("WorkerAI") else null
	var role = ai.job_role if ai else ROLE_AUTO
	
	var i := 0
	while i < pending_tasks.size():
		var task = pending_tasks[i]
		if _can_worker_do_task(role, task.type):
			if not _task_matches_worker_station(worker, role, task):
				i += 1
				continue
			_assign_task_station_for_worker(worker, role, task)
			if _station_has_active_task(task):
				i += 1
				continue
			if _task_station_is_unavailable(task):
				i += 1
				continue

			pending_tasks.remove_at(i)
			task.assigned_worker = worker
			task.status = "in_progress"
			active_tasks.append(task)
			return task
		i += 1
	return null
```

This means a cashier only takes register tasks, a meat griller only takes grill tasks, and Auto workers only take tasks that are not already reserved for a specialist worker.

### Customer Ordering Flow

Customers request a register slot, wait until they reach their assigned register marker, then create a process-order task. After the cashier takes the order, the customer chooses either burger or fries and creates the correct kitchen task.

```gdscript
func take_order(worker: Node) -> void:
	if _has_ordered: return
	_has_ordered = true
	ordered_food_type = _choose_order_type()
	_show_order_label()
	
	var level = customer.get_tree().current_scene
	var prep_station = level.find_child("BurgerPrepStation", true, false)
	var fryer_station = level.find_child("Fryer_1", true, false)
	var food_table = level.find_child("FoodTable", true, false)
	
	if food_table != null:
		if ordered_food_type == FOOD_BURGER and prep_station != null:
			tm.add_task(tm.TaskType.ASSEMBLE_BURGER, {"station": prep_station, "food_table": food_table, "customer": self, "food_type": ordered_food_type})
		elif ordered_food_type == FOOD_FRIES and fryer_station != null:
			tm.add_task(tm.TaskType.FRY_FRIES, {"station": fryer_station, "food_table": food_table, "customer": self, "food_type": ordered_food_type})
```

### Worker Execution Loop

Each worker continuously asks the task manager for work. When a task is assigned, the worker runs the correct task routine and then returns to an idle station.

```gdscript
func _start_task_loop() -> void:
	var task_manager = get_node("/root/TaskManager")
	while is_inside_tree():
		if not _is_executing:
			var task = task_manager.get_next_task(_worker)
			if task != null:
				_is_executing = true
				_current_task = task
				_set_task_status(task, "Starting", "Task assigned")
				await _execute_task(task)
				task_manager.complete_task(task)
				_current_task = null
				_is_executing = false
				_set_idle_status()
				_move_to_assigned_idle_station()
			else:
				_set_idle_status()
				_move_to_assigned_idle_station()
				await get_tree().create_timer(0.5).timeout
		else:
			await get_tree().process_frame
```

### Burger Assembly Dependency

The burger prep station requires cooked meat. If no cooked meat is available, the task manager requests a cook-meat task for the linked grill station instead of letting the burger task fail permanently.

```gdscript
func request_cooked_meat_for_prep(prep_station: Node) -> void:
	if prep_station == null or not is_instance_valid(prep_station):
		return
	if _has_pending_or_active_cook_meat_task(prep_station):
		return

	var grill_station: Node = null
	if prep_station.has_method("get_grill_station"):
		grill_station = prep_station.call("get_grill_station") as Node
	if grill_station == null or not is_instance_valid(grill_station):
		return

	add_task(TaskType.COOK_MEAT, {"station": grill_station, "prep_station": prep_station})
```

### Kitchen Station Interaction

The fryer station animates baskets down into the oil, waits for the cook timer, then raises the baskets and creates bagged fries output.

```gdscript
func fry_fries(worker: Node, reach_controller: Node = null) -> Array[Node3D]:
	var outputs: Array[Node3D] = []
	if _is_busy and _reserved_worker != worker:
		return outputs

	_is_busy = true
	_reserved_worker = null
	_set_oil_visible(true)
	_spawn_raw_fries()
	_set_particles_emitting(oil_particles_enabled)

	for index in range(_baskets.size()):
		await reach_controller.call("reach_to", _handle_positions[index].global_position)
		await _move_basket(index, _basket_start_positions[index] + Vector3.DOWN * basket_lower_offset)

	await get_tree().create_timer(cook_seconds).timeout

	for index in range(_baskets.size()):
		await reach_controller.call("reach_to", _handle_positions[index].global_position)
		await _move_basket(index, _basket_start_positions[index])

	_set_particles_emitting(false)
	_clear_raw_fries()
	_set_oil_visible(false)
	outputs = _create_bagged_fries_outputs()
	_is_busy = false
	return outputs
```

### Worker Right-Hand IK

The reach controller configures a runtime `SkeletonIK3D` from the upper arm to the hand. The controller exposes simple `reach_to` and `pick_and_place` methods so station scripts do not need to know the skeleton details.

```gdscript
func _configure_ik() -> bool:
	_skeleton = _resolve_skeleton()
	if _skeleton == null:
		push_warning("Worker reach controller cannot find a Skeleton3D.")
		return false

	var root_index := _skeleton.find_bone(root_bone)
	var tip_index := _skeleton.find_bone(tip_bone)
	if root_index == -1 or tip_index == -1:
		push_warning("Worker reach controller cannot find right-hand IK bones '%s' -> '%s'." % [root_bone, tip_bone])
		return false
	_tip_bone_index = tip_index

	_target = Node3D.new()
	_target.name = "RightHandIKTarget"
	add_child(_target)
	_target.position = rest_local_position

	_ik = SkeletonIK3D.new()
	_ik.name = "RightHandSkeletonIK"
	_ik.root_bone = root_bone
	_ik.tip_bone = tip_bone
	_skeleton.add_child(_ik)
	_ik.target_node = _ik.get_path_to(_target)
	_ik.interpolation = 1.0
	_ik.stop()
	return true
```

The `pick_and_place` method is what the prep station uses for most ingredient interactions.

```gdscript
func pick_and_place(
	pickup_position: Vector3,
	place_position: Vector3,
	requested_return_position: Variant = null,
	requested_hand_rotation_degrees: Variant = null
) -> bool:
	if not _ready_for_reach:
		push_warning("Worker reach controller cannot run: right-hand IK is not configured.")
		return false

	_ik.start()
	var rest_position := _get_rest_global_position()
	var return_position := rest_position
	if requested_return_position is Vector3:
		return_position = requested_return_position
	var target_rotation_degrees := hand_target_rotation_degrees
	if requested_hand_rotation_degrees is Vector3:
		target_rotation_degrees = requested_hand_rotation_degrees
	_apply_target_pose(rest_position, target_rotation_degrees)
	await _tween_target(pickup_position, reach_duration, target_rotation_degrees)
	await get_tree().create_timer(hold_duration).timeout
	await _tween_target(place_position, place_duration, target_rotation_degrees)
	await get_tree().create_timer(hold_duration).timeout
	reach_completed.emit(place_position)
	await _tween_target(return_position, reach_duration, target_rotation_degrees)
	_ik.stop()
	return true
```

At the prep station, each ingredient calls into that controller with a pickup position and a burger-layer placement position.

```gdscript
var pickup_position := target.global_position if _using_explicit_reach_target else _get_ingredient_contact_position(target)
var place_position := _get_burger_place_position(layer_index)
if reach_controller.has_method("pick_and_place"):
	await reach_controller.call("pick_and_place", pickup_position, place_position, place_position, prep_hand_target_rotation_degrees)
else:
	await reach_controller.call("reach_to", pickup_position)
	await reach_controller.call("reach_to", place_position)
```

### Payment After Eating

Money is collected only after the customer has received food, sat down, eaten, and finished their eating timer.

```gdscript
elif state == State.EATING:
	_wait_timer -= delta
	if _wait_timer <= 0:
		var rm = get_node("/root/RestaurantManager")
		rm.add_money(15.50)
		_leave()
```

# List Of Classes/Assets

| Class/asset | Source |
| --- | --- |
| `src/core/restaurant_manager.gd` | Self written |
| `src/core/customer_manager.gd` | Self written |
| `src/core/customer_ai.gd` | Self written |
| `src/core/task_manager.gd` | Self written |
| `src/core/worker_ai.gd` | Self written |
| `src/core/employee_manager.gd` | Self written |
| `src/core/hud.gd` | Self written |
| `src/core/debug_menu.gd` | Self written |
| `src/world/grill_station.gd` | Self written |
| `src/world/fryer_station.gd` | Self written |
| `src/world/burger_assembly_station.gd` | Self written |
| `src/world/food_table_station.gd` | Self written |
| `src/world/worker_menu.gd` | Self written |
| `src/world/crt_tv_display.gd` | Self written |
| `src/world/seating_map_debugger.gd` | Modified project tool for seat/register/workstation marker generation |
| `src/movement/worker_npc_movement.gd` | Self written |
| `src/movement/worker_reach_controller.gd` | Self written |
| `src/movement/customer_eating_controller.gd` | Self written |
| `src/movement/npc_movement.gd` | Modified existing NPC movement script |
| `src/movement/character_npc_movement.gd` | Modified existing NPC movement script |
| `scenes/world/burger_level.tscn` | Self assembled Godot scene using imported assets |
| `scenes/characters/worker.tscn` | Self assembled Godot scene using imported character asset |
| `scenes/characters/worker_npc.tscn` | Self assembled Godot scene using imported character asset |
| `scenes/characters/character_npc.tscn` | Modified existing NPC scene |
| `scenes/ui/hud.tscn` | Self written/assembled |
| `scenes/props/food/*.tscn` | Self assembled Godot scenes using imported food assets |
| `scenes/props/misc/crt_tv.tscn` | Self assembled Godot scene using imported CRT asset |
| `assets/map/BurgerPiz*` | BurgerPiz map by PlomadillaInc |
| `assets/objects/low-poly_burger*` | Third-party food asset imported into Godot |
| `assets/objects/lowpoly_french_fries*` | Third-party food asset imported into Godot |
| `assets/objects/low_poly_psx_soda_can*` | Third-party prop asset imported into Godot |
| `assets/objects/crt_tv*` | CRT TV model from Sketchfab |
| `assets/characters/psx/*` | Characters PSX pack by Elbolilloduro |
| `assets/characters/Rogue*` | Third-party character asset imported into Godot |
| `assets/characters/psx/psx_prop_-_restaurant_cook*` | PSX restaurant cook model from Sketchfab |
| `assets/animations/Rig_Medium/animations/*` | Universal Animation Library by Quaternius |
| `assets/animations/Base/carla*` | Carla Sitting Idle model/animation from Sketchfab |
| `assets/animations/Base/man_sitting*` | Man Sitting model/animation from Sketchfab |
| `assets/animations/Base/women_sitting_animated*` | Women Sitting Animated model/animation from Sketchfab |

# Personal Contribution

I built the simulation logic, scene integration, and gameplay systems for the restaurant prototype. My work focused on making the restaurant operate as a complete chain of autonomous events rather than a static scene. This included customer spawning and queues, the task manager, worker role assignment, worker AI, order taking, kitchen stations, burger assembly, fries frying, meat grilling, food storage, delivery, customer seating/eating, and payment collection.

The part I am most proud of is the worker task pipeline. A customer order can trigger several dependent systems: a cashier processes the order, a burger prepper may need cooked meat, the task manager can request grill work, the worker carries the completed food to storage, and a caterer then delivers the correct item to the customer. Each step has to coordinate with station availability, role assignment, navigation, animation, and food state.

I also learned a lot about building larger Godot systems from smaller reusable nodes. The project uses Godot scenes for physical objects and station markers, while scripts expose simple methods such as `fry_fries`, `cook_meat`, `store_food_item`, and `receive_food`. This made it easier to connect AI behavior to the world without hardcoding every interaction.

# References

- Godot Engine Documentation: https://docs.godotengine.org/
- Godot NavigationServer3D Documentation: https://docs.godotengine.org/en/stable/classes/class_navigationserver3d.html
- Godot SkeletonIK3D Documentation: https://docs.godotengine.org/en/stable/classes/class_skeletonik3d.html
- Godot Tween Documentation: https://docs.godotengine.org/en/stable/classes/class_tween.html
- README submission template reference: https://github.com/skooter500/miniature-rotary-phone/tree/main/readme
- Carla Sitting Idle: https://sketchfab.com/3d-models/carla-sitting-idle-9734fc2bb56e4ebeb90eb6929ba84d64
- Man Sitting: https://sketchfab.com/3d-models/man-sitting-b46bceb164b74346897c7a62691a1d5c
- Women Sitting Animated: https://sketchfab.com/3d-models/women-sitting-animated-f967d0a021b649ba80e1c452b368c8e8
- Universal Animation Library by Quaternius: https://quaternius.itch.io/universal-animation-library
- BurgerPiz map by PlomadillaInc: https://plomadillainc.itch.io/burgerpiz
- CRT TV: https://sketchfab.com/3d-models/crt-tv-7e19d474af4449e69c03dc661e7967dc
- Characters PSX pack by Elbolilloduro: https://elbolilloduro.itch.io/characters-psx
- PSX Prop Restaurant Cook: https://sketchfab.com/3d-models/psx-prop-restaurant-cook-6cb111c432854de08c8aca9ee09d806c
