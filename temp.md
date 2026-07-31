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
