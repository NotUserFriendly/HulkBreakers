##### First Hunt
Bugs:
Sniper rifle consistently shooting wide left of where I aim. Edit: Chaingun and sniper rifle consistently shoot left of where I aim when aiming at a goo barrel.
Set Part HP has no way to target parts not on a unit.
Misses still happening when there is something for a bullet to hit; damage should drop outside of range but the bullet should still hit something.
Killing a unit while it's their turn doesn't end their turn.
Cannot select a dead/prone unit, this may be related to the bug above.

Design Notes:
Debug Panel: Set Cell Level : Level should increment by 0.5

Responses:
No obvious cutout behaviors when firing shots near a dead body.
Can't check goo barrel, set part hp can't target it and can't shoot one consistently.
Setting level doesn't affect cutout misbehavior: A proposed fix, cut out is a 2d projection at camera angle. If that could be tilted to vertical and aligned with grid tiles it would bypass this problem.

##### Second Hunt
Rseponses:
51.01: Camera for shooting is fixed angle, can't troubleshoot this the way you propose. HOWEVER, you're leaning the right way. The fixed camera is back and right of the shooter, and shots are landing left, which is a possibly matching angle.
34.04: Sniper camera still frames from a high angle. Camera should probably be a short distance from the target, in line between shooter and target.
33.01: Still happening, no new info. However, this feature is not what I originally intended, more likely to be obsoleted than fixed.
27.04: I don't see this happening, however I don't remember reporting this bug this way, likely a misfile. Mark it resolved, if it shows again we'll move it back to active.
34.01: skipping for now
27.07/32.09: Indicator moves to next unit before animation completes when AI is controlling. Indicator moves with unit correctly when player is controlling.

New Bug:
Debug panel: the 'pick' button under several tools ALSO sets the active item. It should suspend selecting the active while pick is in use, UNLESS they do the same thing, in which case pick should likely be removed.

Design Notes:
Dart board and aiming system should likely be detached from locking to a unit. Instead, clicking a unit gives you the aim dart board, but mousing off that unit onto something else targetable lets you cycle to that other thing. 
