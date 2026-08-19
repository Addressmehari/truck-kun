---

kanban-plugin: board

---

## Feats

- [ ] **Speed Trap Events** 
	
	- [ ] A speed warning appears with a countdown (100m → 0m). Slow down before entering the speed check zone. Driving too fast adds a traffic fine, and unpaid fines can disable your truck until they are paid.
	- [ ] A shark warning appears with a countdown (100m → 0m). Wait untill shark gets into water, Avoid hitting or killing sharks in the protected water zone. Killing a shark gives you a heavy wildlife fine, and unpaid fines can disable your truck until they are paid.
- [ ] ## Mini Missions:
	
	- [x] 1.Deliver a crate
	- [x] 2.Tow a vehicle
	- [x] 3.Race
- [ ] ## Mini obstacles:
	
	- [x] Crushers will appear.Move at the right time to avoid getting crushed.  
	- [ ] Rain will blur screen. Wipe the windshield to see again.  
	- [x] Defend your truck from the convoy.
- [ ] # Truck elevator:
	there should be an end of the road, there will be elevator which will lift truck up, and we can continue. its like dark cave zone
	# Todos:
	- [x] Add condition
	- [x] Elevator
- [x] - [x] Add Spring to Wheels
	
	-Groove2DJoint
	-Mass for tyres to 2, so it wont bump often (Programmatically Physics included)
	
	![[truck-sideview-polygons.png|194]]
- [x] - [x] Distance meter and coin counter ui
	![[score and coin.png]]
- [x] - [x] Chaos After Mini-event wheel pickup:fix: removed wheel
- [x] - [x] Add font
- [x] - [x] Move acceleration script to Wheels script itself
- [x] - [x] Convoy
	![[convoy.png]]
- [x] - [x] Coins
- [x] - [x] Petrol
- [ ] Water biome:
	- [x] voronoi Shader, moving water
	- [x] Boat Physics
	- [x] ship is vehicle
	![[boat.png|179]]


## Changes

- [ ] - [x] i want to improve the experience in my game.  
	do u see the 3 houses in my game?  
	before the house comes in 100 metres before show a notification like bubble in the right side... which is like a squircle with arrow on right side.  
	racing - > race flag symbol  
	delivery - > 2 crates  
	tow - > link symbol
- [ ] - [x] To Add the AIR CONTROL
- [ ] - [x] UI after mission completed
- [ ] - [x] During TowJob, elevator should be large enough to life the towed vehicle too
- [ ] - [x] Reduce the opacity
	## Mechanic for race:
	- [ ] Sometimes it will prompt the QTE, completing that will improve the sped / give temporary buffs
- [ ] Sprite change: healthBased
	- [ ] Truck
	- [ ] Boat
- [ ] Towable Things:
	- [x] Added Duck
	 ![[tow-duck.png]]
- [ ] ## Racing:
	- [x] Add House
	- [x] UI
	- [x] Opponent
	- [x] Optimize
	- [ ] Environment: race flags
- [ ] - [x] change convoy from attacking to defending: convoy cars will shoot Glass Bottles. we have to tap or throw back to them
	
	Done Awesomelyyyyyyyy🥳🥳🥳
- [ ] - [x] HUD ui enhancement
	
	![[hud2.0.png]]
- [ ] - [x] Molotove Throw on Convoy
- [ ] Crusher:
	- [x] Add Crusher scene
	- [x] Adjust Cheat to spawn whole Event Area
	- [x] Arrange  3-5 crusher in row
	- [x] make the Progress Bar for that, add dots in it, those places are the crushers placed on.
	
	Add Variants to it:
	- [x] Saw
	- [x] Normal
	
	
	Addon:
	- [x] Treadmill
- [ ] - [x] Change Convoy Bar Also Increamental by distance isntead of the duration 30 sec, what if made like 300m, 250m like convoy
- [ ] Mini Missions:
	- [x] house
	
	Tasks:
	- [x] Crate Delivery: pressing that house will pop up a window, it will have accept / decline options. mainly it will tell, no of crates to transfer, how much they will give us. Time to complete delivery.
	- [x] Landing point
	- [x] Crates spawner.


## Bugs

- [ ] - [x] game just not spawning coins or whatever
- [ ] - [ ] When playing, sometimes i got struck into the bridge because of the width of the bridge, it seems so small i think... so wheels go below the bridge
- [ ] - [ ] When playing race with hopps infinite recursion error occurs
- [ ] - [x] ok aweosme, now small bugs in the bridge generation. sometimes the end point of the bridge is spikey, it maybe because i do catch mysteryboxes and got crusher..... can u fix the end of bridge to be on spike if it occured in that case?'
- [ ] - [ ] sometimes crushers spawn treadmill on top of the land
- [ ] - [ ] Convoy in Sea
- [ ] - [ ] in elevator, towed vehicle is not raising
- [ ] World Generation became poor after crusher feat added
	- [x] Crusher causes error
- [ ] - [x] towed item changing position if i switched from water to grass... also from grass to water... make it persistent across biomes
- [ ] - [x]  When Crusher Crush, Truck physiq just broken brutally
	- [x] After crusher ended, truck undergoes unexpected transformation in position
- [ ] Racecar not able to use the lift,
	- [x] fix: create 2 lift one for race car access
- [ ] Water biome:
	- [x] chaos screen after changing the biome from water -> grass
	- [x] sudden change to water biome while giving velocity breaks the game
	- [x] water biome to other biome leads truck to fall... been change in shape..
- [ ] - [x] the ruck tyre is seperated from opponent truck. body and tyre are going somewhere looking worst
- [ ] - [x] Boats not interacting with crushers
- [ ] - [x] truck health is not decreasing when bottle hits and ground is not breaking glass
	- [x] Optimize it
- [ ] - [x] the place i deliver the crates should not gimme orders?


## powerUps

- [ ] - [ ] 3D Spinning Donut
- [ ] - [ ] DNA Helix -> Tentacle possess the truck, gives invincibility for some seconds


## Composing

- [ ] - [x] Split silhoutte mode as seperate scene
- [ ] - [ ] anchor camera to a below level of the road. because the more it gets to down, the empty place below the road from editor is visible
- [ ] - [x] Slow truck on Autopilotting on convoy
- [ ] - [x] dont spawn the mystery box before the tunnel
- [ ] # World Generation State System
	
	## Task 1: Create Terrain States
	- [x] Implement a terrain state system with three predefined generation states.
	- [x] **State 1:** Mostly flat terrain.
	- [x] **State 2:** Current terrain generation parameters (existing).
	
	---
	
	## Task 2: State-Based Parameters
	- [x] Assign a fixed set of world generation parameters to each state.
	- [x] Keep parameters consistent while a state is active.
	
	---
	
	## Task 3: Distance-Based Progression
	- [x] Change the active terrain state based on the total distance traveled.
	- [x] Switch between only these 2 states throughout gameplay.
	
	---
	
	## Task 4: World Generation Integration
	- [x] Generate new chunks using the parameters of the current active state.
	- [x] Ensure terrain transitions remain smooth when changing states.
	
	---
	
	## Task 5: Future Extensibility
	- [x] Design the state system so additional terrain states can be added easily in the future.
- [ ] - [x] mini events trigger: added mystery box
- [ ] - [x] let the tunnel create a transformation with biomes
- [ ] mainmenu
	1. increase letterbox




%% kanban:settings
```
{"kanban-plugin":"board","list-collapse":[true,true,true,true,true],"full-list-lane-width":true,"move-tags":true}
```
%%