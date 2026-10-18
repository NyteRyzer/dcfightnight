# Manual Test Checklist

Use this alongside the automated runner (`res://tests/TestRunner.tscn`). It follows the bible's acceptance checklist.

## Launch
- [ ] The project opens in Godot 4.3+ from a clean checkout with no script errors in the Output panel.
- [ ] F5 shows the title screen. Menu music plays. The fighters on the title screen swap every 5 seconds.

## Menus
- [ ] Every main-menu item opens its screen. Back (K / Esc) returns from each one.
- [ ] Options: each volume slider changes the volume right away. Mute, Fullscreen, Window Scale and Pixel Scaling all apply. Settings are still set after restarting the game.
- [ ] Options → Player 1 Controls: rebind Light to another key. The new key works in a fight. If you rebind to a key that's already in use, the two actions swap.
- [ ] Credits scroll. Any button returns to the menu.

## Character / stage select
- [ ] Versus: P1 (WASD + J) and P2 (arrows + Num1) move their cursors independently, and back (K / Num2) un-picks.
- [ ] Y (controller) / U (keyboard) cycles through each fighter's suits, and the suit name updates under the preview. A mirror match with the same suit gives P2 the next suit automatically.
- [ ] Control Freak shows "?" until Story or Arcade is beaten.
- [ ] Random picks an unlocked fighter.
- [ ] Stage select previews each arena live. The locked boss stage can't be picked until it's unlocked.

## Fight
- [ ] The VS splash shows both fighters and the stage. Then ROUND 1 → FIGHT!
- [ ] Walk, back-walk, crouch, neutral/forward/back jump, and forward/back dash (double-tap) all work.
- [ ] Light, Medium and Heavy attacks, standing / crouching / in the air, visibly hit and show sparks.
- [ ] Chains work: L → M → H and cL → cM → cH. A normal that hits can be cancelled into a special.
- [ ] Block (I) stops high and mid attacks. Crouch-block (I + S) stops lows. Overheads (jump-ins) beat a crouch-block. Sweeps beat a standing block.
- [ ] Throw (K + L) works up close. Pressing K + L right after being grabbed breaks the throw ("THROW BREAK").
- [ ] Every special works for every fighter (check against `docs/MOVES.md`).
- [ ] The super needs a full meter. It plays the darkened-stage banner freeze, then hits.
- [ ] The combo counter shows hits and damage. Long juggles end, because the opponent becomes untouchable after 5 air hits.
- [ ] K.O. gives slow motion, then "<NAME> WINS". FLAWLESS VICTORY appears if the winner took no damage. TIME decides by remaining health.
- [ ] Best of 3 with round markers. The results menu offers Rematch, Character Select, Stage Select and Main Menu, and each one works.
- [ ] Neither fighter can leave the screen or the stage. The camera follows both.
- [ ] Pause (Esc) freezes the fight. Move List, Restart, Character Select and Main Menu all work. Resume works.

## Fighting systems
- [ ] The meter shows 3 bars. Pressing Block during a special's start-up with 1+ bar shows "AMPLIFIED" and the special hits harder.
- [ ] With 2+ bars, pressing Toward + Block while being comboed shows "BREAKER!" and knocks the attacker away. It works only once per round.
- [ ] Hitting during the opponent's start-up shows "COUNTER HIT". Hitting during their recovery shows "PUNISH".
- [ ] A hard launcher (e.g. an uppercut) into the screen edge shows "WALL BOUNCE".
- [ ] Pressing a button while knocked down gives "QUICK RISE". Holding back while doing it rolls away.
- [ ] Heavy hits, supers and KOs zoom the camera slightly. Strikes show a motion smear. Sword hits show slash arcs.

## Controllers
- [ ] Plugging in or unplugging a controller shows a notice at the top of the screen.
- [ ] In single-player modes, any connected controller controls Player 1.
- [ ] In 2-player Versus, controller 1 is P1 and controller 2 is P2. Swap Controllers reverses them.
- [ ] Options → Player N Controller: remap a button, and it works in a fight. Remapping a button that's already in use moves it.
- [ ] Vibration fires on hits, supers and KOs. It turns off with Vibration OFF, and Test Vibration works.
- [ ] Holding the stick or D-pad in menus scrolls repeatedly.
- [ ] Button prompts change between keyboard keys and controller buttons depending on the last device used.
- [ ] Unplugging a player's controller mid-fight pauses the game.

## Modes
- [ ] Story: the prologue plays, then chapters 1–9 in order. The finale asks you to choose a champion. Winning unlocks Control Freak and Freak's Studio, then shows the credits. Losing offers Retry or Quit. After quitting, Continue Story resumes at the reached chapter.
- [ ] Arcade: 6 random opponents, then Control Freak at Freak's Studio, then the fighter's ending text, then the credits.
- [ ] Survival: health carries over (+25% between fights). The win count goes up. The CPU gets harder every 3 wins.
- [ ] Training: the timer shows "--". Health regenerates. Dummy modes (Stand / Crouch / Jump / Block / CPU), the Hitboxes toggle and R (reset) all work. The frame-data line updates.

## Finishers, tutorial and banter
- [ ] Winning the deciding round shows FINISH IT! with Back / Forward / Special chips. Entering them in order plays the winner's finisher and announces its name. Waiting 5 seconds lets the loser collapse normally.
- [ ] The finish command follows facing: "Back" is away from the opponent on either side of the screen.
- [ ] CPU winners usually perform their finisher. Options > Gameplay > Finishers OFF skips the prompt.
- [ ] Before round 1, the two fighters trade speech bubbles (scripted for rivals such as Flash vs Reverse-Flash). Confirm skips a line. Options > Gameplay > Pre-Fight Banter OFF removes it.
- [ ] Tutorial (main menu) runs 11 lessons; each shows the real keys or buttons. The dummy attacks high, then low, in the blocking lessons. Pause > Skip Lesson works.

## Beat 'em Up
- [ ] Beat 'em Up (solo) picks one fighter. Beat 'em Up Co-op picks two, and each controller drives its own player.
- [ ] Up/Down walks in depth. Attacks only connect with enemies in roughly the same lane.
- [ ] Throw jumps in open space and grabs an enemy when one is adjacent. Light + Heavy fires the super at 3 bars.
- [ ] Enemies take turns: no more than two close in on one player at a time, the rest circle or hang back.
- [ ] Gunners, H.I.V.E. agents and Earth-X soldiers shoot. Punks and convicts lunge with forward specials.
- [ ] The GO arrow appears when an area is clear and walking right moves on. The camera never scrolls past live enemies.
- [ ] Pickups: burgers heal 250, medkits 500, Speed Force cells give 1 bar. They blink before vanishing.
- [ ] Each level ends with the boss intro line and a boss health bar. Level 5 has a Deathstroke mini-boss.
- [ ] Losing all lives shows GAME OVER with Continue (restarts the level) or Main Menu.
- [ ] Clearing level 5 shows the ending card, then the credits. The best score is saved.

## Visual / audio
- [ ] Pixel art stays crisp at 1280×720 and in fullscreen with Pixel Scaling set to CRISP.
- [ ] Fighters are roughly half the screen height and easy to read on every stage.
- [ ] The HUD stays legible on bright stages (D.E.O., National City).
- [ ] Each fighter's special has its own effect and sound.
- [ ] Reduce Flashing removes the full-screen white flashes. Screen Shake OFF stops the camera shake.

## Gamepad
- [ ] Gamepad 1 controls P1 and gamepad 2 controls P2. Swap Gamepads reverses them.
- [ ] D-pad and left stick both move. LT/LB block. RT/RB/A do specials. Start pauses.
