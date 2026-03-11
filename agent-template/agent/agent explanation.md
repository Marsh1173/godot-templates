Peers always send each individual action to the host who processes/authenticates it and replicates the results to the peers.
The host replicates state (pos, velocity, rotation, movement mode) to peers, NOT input-layer concerns (is moving left)

How to keep the player rotating and moving with their controller?
* Only host and owner peer track movement state (is-moving-left etc)

MOVEMENT ACTION FLOW
Sends action to server
	and if it's a movement or a look action, apply locally instantly
Server gets action, applies, updates all peers
	if peer tries to update itself with a movement action, 
	else interpolate smoothly

NEXT UPS
	Death / spectating / spawning
	Inventory
	Health
