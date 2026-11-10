# Task Tracker — Changelog

## 12.1.5.5

### New features

**Empty groups**
You can show a group you made when it has nothing in it. That includes one whose only contents are other empty groups. Empty groups sits under Options, General, List. It defaults to off, so that group stays off the list. Completed shows it when Show completed is on. Always shows it either way. Edit mode still shows it, so you can add a task or another group.

## 12.1.5.4

### New features

**Sync**
- Added Sync. You can send a saved task to a character on another account. They get the task on their list and can move it. The count, and whether the task is done, stay matched to yours.
- Sync defaults to off. Turn it on under Options, Advanced. The Sync button then sits with Edit data, Notes, and Popout. Type their character name and server.
- On a task that belongs to one character, each character on your account can send their own copy. Logging an alt does not change a copy that was already sent. A module row someone sent you stays on your list even if you have that row turned off.
- They can't check the task off. Turn on They can add to the count if you want them to raise the count. That increase syncs back to you. They still can't lower it. If you both add to the count at the same time, both adds count. Edit on a task they sent you opens a small window that shows who sent it and when. Delete removes it. The full task editor stays closed. Stop sharing removes the task from their list too. They need to be online for that.
- An update goes out when you log in, and again when the count changes. A weekly task someone sent you keeps this week's count. Logging in on another day this week does not open it again. It clears on the following week. A per-character task only updates while the character who shared it is logged in, and both of you need to be online for that send to land. While Sync is off, a new task is not sent or received. A task that was already shared still follows the owner.
- You can show the task owner's name on the task or in the tooltip. It defaults to on, with the name on the task in gray after the title. It works the other way too. When you share a task, that same spot says who you sent it to. Tooltip moves the name onto the row hover. None hides it.
- Sync all is there for a share that has fallen behind. It defaults to off. Turn it on under Sync and the button sits on the tracker title bar. One click sends every shared task again. Tasks you sent go out with your current count. Tasks someone sent you ask them for a fresh copy. You both still need to be online.

**Boss kills**
- In Boss mode, you can type part of an instance or boss name. Suggestions come from the dungeon journal, and a shorter name still matches the full boss.
- The check button names that boss before you kill it. The kill still has to finish successfully.

**Shortcuts**
- Added Manual / automatic under Task management in Shortcuts. On a task that tracks itself, that click switches between keeping the number you set and following the game. The count stays where it is until the game updates the task.
- Delete task, under Task management, asks before it removes the task.

### Adjusted features

- Added an Advanced page in Options, under Generative tasks. It holds settings that can need extra setup, and a note on that page says so. Hide collected in the picker is no longer an Options setting. It stays on the Collectable task, when you pick the item.
- Profession rows can now be edited like a task you made. That includes Abundance, the weeklies under each profession, and Catch-up Knowledge. Turn one off in Modules, then on again, and it goes back to the built-in task.

### Bug fixes

- A weekly task someone sent you stays done for the rest of the week, even if you have not logged that character again. It still clears on the weekly reset.
- Checking a quest task off yourself stays until that task resets. Reloading was clearing it.
- Weekly profession tasks you already finished stay finished until the weekly reset. A row with several quests, such as Weekly Treasures, was treating this week's finish as an older one and opening the task again.
- A group you made with nothing in it hides. That includes one whose only contents are other empty groups. Turn on edit mode and it comes back, so you can add a task or another group. Leave edit mode and it hides again.
- A daily or weekly task that lists several quests counts a quest you finish during that day or week. A quest you finished earlier stays checked off in the game, and that does not complete the task.
- A custom Prey hunt counts each time you finish it. Whichever difficulty you picked can already show that hunt in your log. Turning it in adds one on that row, including when you finish the same hunt again this week, up to 4.
- A daily or weekly task resets for each character. Only the character you were logged in on was starting over, so your other characters stayed done for the rest of that day or week. The next time you log in on one of them, that task starts over. A profession quest that character already finished this week still shows finished.
- Weekly Treasures counts a treasure you pick up this week. The first one was saved as an older finish, so the row stayed at 0. A treasure you already picked up this week counts, and the next one does too.
- A second group named Professions, or a profession name under that group, stays on the group window and asks you to pick another name.

## 12.1.5.3

### New features

**World Quests**
- Gold world quests start at 500 gold. Min gold sits next to Currency. Lower it to include smaller payouts. Clear the box to show every gold quest.

**Shortcuts**
- A Shortcuts page sits between Modules and Generative tasks. It sets clicks on the task name, the count, and Notes. Those sections start folded. Open one, then open Left, Right, or Middle. Each of those holds Normal, Ctrl, Alt, and Shift. Normal is a click with no extra key. A plain left click counts up. A plain right click counts down. Shift does not, until you set it.
- Ctrl-left starts as Task special. Achievement opens the achievement window. The other task types start blank. Custom runs a command you type.
- Notes keeps Shift-left for the popout and Alt-left to open Notes.
- The custom command box is the same width as the dropdown. The rows and the section titles use one text size.
- Commands are grouped. Task management holds Edit task, Count up, and Count down. Task special holds Open achievement. On the task name and the count it also holds Task special, which still opens the task types. Notes holds Edit notes and Open popout.
- A switch sits to the right of each command. On shows that click in the task tooltip. On the task name, a plain left click (count up) and a plain right click (count down) start on. Those lines show the click icon only. Alt-left on the task name and the count starts on. A task special that is not Nothing starts on. The rest start off.

### Adjusted features

- Dropdowns in Options use the same gray as the list on the left, so they show up on the page. The choice under your cursor lights up. Opening one closes the dropdown that was already open.
- Module headers use the same text size as the rest of Options.
- Choose icon has Use command at the top. It uses the same #showtooltip check as a macro, so a /cast or /use line can supply the picture.
- The command box has a larger editor. Lines runs each line on its own, so a waypoint list fits. Full still runs the whole command as one macro.
- On a note popout, close, edit, and the command icons sit inside the note. Close and edit are on the title line. Commands sit along the bottom.

### Bug fixes

- The Abundance Toy button shows on the row with your other command buttons.
- A note popout left open comes back after a reload or when you log in again, in the same place.
- Style size sliders keep your place in Options. The list no longer jumps back to the top.

## 12.1.5.2

### New features

**Currencies**
- Remnant of Anguish is with Voidlight Marl under Collections, then Currency, on Patch 12.0.0. It shows in Expansion Activities. The weekly goal starts at 1000.

**Tasks**
- In the task window, When completed tasks are hidden starts on Hide. Choose Keep to leave that task on the list anyway.

**List**
- The group menu lists Hide Modules, Hide Collections, and Hide Custom. Everything starts on the list. Click a row to hide that set, and the label switches to Show. Collections is the Collections headers. Custom is groups and tasks you added. Modules is the rest, such as Power, Seasonal, Professions, and patch activities.

**Professions**
- Abundance has a Toy button for Dundun's Abundant Travel Method. You need the toy. It only works in Midnight zones, and it has a 30 minute cooldown.

**Style**
- Popout sliders follow Compact, Comfy, and Spacious. Change them on Custom. Normal and Mouse Over are separate groups. Sliders adjust opacity. Close stays at least 10% so you can still find it.

**List**
- Holding Ctrl on a row no longer shows extra IDs in the tooltip.

**Settings**
- The first section in General is labeled General.
- New modules starts off. A module added in a later update stays off until you turn it on under Modules. Turn it on if you want those added to the list. Modules you already have stay as they are.
- Hover a row in General for what that setting does. Help tooltips starts on. Turn it off to hide those hover notes. Task tooltips on the list stay.

### Adjusted features

**Notes**
- The notes section was redesigned. Notes and Popout sit at the bottom of the task settings. Commands are in the grey column on the left, with the name and slash command under the icon. An empty note shows "Write a note here." That line, and a blank command, aren't saved until you change them. On a new task, the note is saved when you add the task.
- Popout is a movable copy of the note. You can keep more than one open, and each one comes back after a reload where you left it. Close, edit, and commands sit on the right. Edit opens Notes. On the list, the note icon stays on a task that has a note. Click opens Notes. Shift-click opens the popout.
- On an existing task, Edit data is on the left of that row, under Hide and Keep. Notes is in the middle. Click Edit data to set progress.
- The progress editor has Locked and Automatic on a task that tracks itself. Locked keeps the number you set. Automatic follows the game. Ctrl-left on a task no longer clears that.
- Ctrl-left on an achievement task opens it in the achievement window. The tooltip says that under the character list, with a left-click icon next to Ctrl. Other rows say Nothing. Alt-left on the count opens the task window. The shortcut line says Edit task. Shift-left on a task count no longer opens the progress editor.
- Shortcut, in General, starts on. Turn it off to hide those shortcut lines. The task tooltip stays.

### Bug fixes

**Reputations**
- Aqir Research Enclave was using the full reputation bar, so Exalted did not finish the row. It uses the friendship bar and finishes at 5000. The second line shows that rank.

**Prey**
- Prey: Nightmare counts Preferential Killing, the hunt where you pick the target, zone, and difficulty. The game uses that same quest on every difficulty, so it counts on this row. Each finish counts, up to 4.

**Edit mode**
- Shard of Dundun was showing under the first task as well as Abundance. It stays on Abundance.

## 12.1.5.1

### New features

**Tasks**
- A task can hold up to four goals. Once there is a second goal, Completes when sits above them. Click it to switch between all goals and any goal.
- Tips on the task window sit to the right of the window, level with the cursor.
- Settings sit on the left. The task itself is on the right, including its name. Add Additional Goal sits under the last goal. Add Secondary Data sits at the bottom. Secondary data stays hidden until you add it. The x beside it removes that section, and the button comes back.
- Second line fields share one width.
- A closed goal is one line, with the type and the count. The open goal uses that line for the task type, and the options sit under it.
- The row shows each count, joined with "and" or "or".

**Patch 12.1.5**
- Modules has Patch 12.1.5. Aqir Invasions has the satchel. Collections, then Reputations, has the two Renowns.

**Reputations**
- The Labyrinth of Kindo'jan tracks weekly Renown. The goal starts at 2100. The second line shows your Renown.
- Aqir Research Enclave tracks weekly reputation. The goal starts at 500. The second line shows your Renown.
- Delver's Journey, the one you check with Valeera, is under Midnight reputations. It tracks weekly Renown. The goal starts at 4200, one rank. The second line shows your Renown.

**Aqir Invasions**
- Aqir Research Satchel finishes when you loot it this week. Power treats it as Champion 2 gear, item level 295. After that, it keeps Champion Mistcrest until 309.

### Adjusted features

**Zones**
- Halduron's Weekly and the Labyrinth of Kindo'jan show under Expansion Activities.

### Bug fixes

**World Quests**
- Gold on a world quest shows the coin icons. On a narrow list, that line was cut off and the gold amount was followed by leftover text.

**Reputations**
- The Labyrinth of Kindo'jan row stayed at 0 and had no second line. It now follows your Renown bar, including progress you already earned. The second line shows your rank.
- Finishing a Renown rank was adding about a million to the weekly count. It now adds the size of that rank.

**Compatibility**
- After the 12.1.5 update, the list was throwing an error every few seconds. GetItemCount was removed. Item counts now use C_Item.GetItemCount, so that spam stops.

## 12.1.0.11

### New features

**Edit mode**
- Options → General → List has List organization. Pick and place works as it does now. Drag and drop lets you drag = to a gap between rows. The row you are moving fades, and a copy of it follows the cursor.
- Official sections, such as Midnight, don't take new tasks. Add the task under a group you made.

**Delves**
- The Delves header has Delve-O-Bot 7001's icon. Click it to call a ride to a random Bountiful Delve. That needs the toy, and it only works out of combat.

**Dungeons and raids**
- Mythic+ in Seasonal Activities is now Dungeons. Normal and Heroic sit above the Mythic+ hints.
- Normal dungeons need level 80 and drop item level 253. Heroic needs level 90 and drops 276. After that gear is no longer an upgrade, Power keeps Adventurer Mistcrest until 282.
- Raids lists Normal, Heroic, and Mythic for the Venomous Abyss. Each row counts bosses killed this week on that difficulty, and finishes when the raid is clear. The rows show 292-302, 305-315, and 318-344. They need level 90. The 344 pieces are the last two Mythic bosses. After the gear, Normal keeps Champion Mistcrest until 309 and Heroic keeps Hero Mistcrest until 322. Myth Mistcrest stops at 334, and Mythic gear goes to 344.
- Each raid difficulty also has a Great Vault row. It counts vault slots for bosses killed on that difficulty, and finishes when the vault is full. That takes 6 bosses. Normal is 305, Heroic is 318, and Mythic is 334-344. The 344 choice is the last two Mythic bosses. Those rows use the same crests.
- Dungeon and raid rows show a Normal, Heroic, or Mythic icon.
- Vault Status sits above Delves.

### Adjusted features

**Tooltips**
- Notes, commands, edit, Toggle off, Move row, Add task, Add group, and the title bar icons open beside the list, in the same spot as a task tooltip.
- Add task and Add group name the section. That header lights up while the line is under your cursor, and while you drag a row onto a gap.
- Toggle off, on an official section, turns off every row in that section.

**World Quests**
- Each hunt groups its quests by zone, so you can see where to go.

**Power**
- Power suggestions need level 90. Below 90 they drop off the Power list, and stay on in Midnight and the other sections.
- When no Power row applies, the Power section hides.
- Power details has a Level column for the level that reward needs.

### Bug fixes

**Power details**
- The reward that applies is marked with a check. The old mark drew as a green box.

**Power**
- Enable all and Disable all under Power turn that section's switches on or off.

**Weekly quests on alts**
- Rows like Lost Legends track each character on their own. Finishing the quest on an alt marks that character Done.
- An alt who already finished this week before this update stays Incomplete until the next reset. After that, each character keeps their own starting list.

## 12.1.0.10

### New features

**Options panel**
- Options → Style has an Options Panel section, above Title bar.
- Font, rows, border, and the title bar there change this window only. Section titles sit 2px above Font. Rows is the height of those rows, and of the list on the left. The module grid and the character cards keep their own height.
- Compact, Comfy, and Spacious do not change this section.
- Border and Buttons for the task list sit under List.

### Adjusted features

**Ki'clak, Zul'jarra's Forces, and Lil' Mon**
- These are grindable tasks now. They count what you gain, instead of a fixed total.

**Second line**
- An achievement line starts with the achievement name. Ki'clak shows A Stack of Snacks - 4/5.
- Lifetime kills and Rarity Drop Rate can both be on. If Rarity has data for that drop, the line uses Rarity and does not count lifetime kills. If Rarity has no data, it counts kills.

### Bug fixes

**Profiles**
- Logging in loads that character's profile. The list was still using the last character's profile until you picked it again.

**Window**
- Dragging the list lands where you let go, including at the top of the screen. A UI scale other than 100% was dropping it lower than your cursor. The higher you placed it, the further it jumped.

**Ready to Buy**
- An ensemble you already know stays off the list. Depthdiver Vestments was still there after the tooltip said Already known.

## 12.1.0.9

### New features

**Profiles**
- Options → Profiles. Characters on the same profile share the layout and the design. Tasks stay with each character, unless the task is account wide.

**Spacing**
- Themes set the colors. Spacing is Compact, Comfy, or Spacious, under Options → Style.
- Compact is the tight list. Comfy is 20% larger. Spacious is 20% larger than Comfy. Spacious title text and title icons stay at 18 so they fit the bar.
- Those three dim the sliders. Custom is your own spacing. Its copy button can start from Compact, Comfy, or Spacious.
- Style no longer has a Defaults button. Compact, Comfy, Spacious, and Custom are the spacing choices.
- Color bar is the width of the strip on a header and on a task row.
- Bar to checkbox is the gap between that strip and the checkbox.
- Title bar and header buttons have no box. Plus, minus, and close use the same icons as the other buttons. Classic uses the game's icons. Tintable uses white marks that take the theme color.
- Font, title bar height, and border width each have their own slider.
- The font menu is Friz, Arial, Morpheus, and Skurri. Each one is a different font included with WoW.
- Drop shadow sits next to the font. It draws a dark edge around the letters. It starts off.

**Second line**
- An item or currency line can show how many you are holding, and how many AllTheThings still needs for collectables you do not have. That needs AllTheThings. Corrosive Coins and Voidlight Marl use this line.
- An achievement line can show Weekly target or In-game bar. Weekly target is what you gain this week, toward a number you type. In-game bar is the achievement's own total.

### Adjusted features

**Goals**
- Emerald Skyfang and Corrosive Coins are goal tasks now. They track what you gain toward a number you set, instead of a fixed total.

**Vaults of Atal'Utek**
- Er'inye is one daily.
- Bounty of the Cursed, Essence of Malice, and From Whence it Came take turns. You can pick up only one of them.
- The row checks off when you turn that quest in.

**Special Assignment**
- Demand and Supply, Face the Swarm, and Wraith Wrath on the Coiled Isle count toward Special Assignment. The weekly goal is still two.

**Modules**
- Options → Modules lists Midnight before Professions.

**Power**
- After you open this week's two pinnacle caches, those weeklies show Veteran Mistcrest and its icon.

**Icons**
- Tintable icons use the accent text color. A custom theme can still set Icons on its own.

### Bug fixes

**Modules**
- Turning a task on in its own list leaves the Power list alone. Each list has its own switch.

## 12.1.0.8

### New features

**World Quests**
- World Quests sits under Generated Tasks, next to Ready to Buy. It lists world quests that are up right now.
- Gold is the ones that pay gold, highest first.
- Collectables are ones that reward an appearance, pet, toy, or mount you do not have yet.
- Currency and Reputation use the name you type. Only quests that pay that currency, or that reputation, show in those groups. Reputation includes renown. Type the faction name, such as Amani Tribe. On Midnight, a world quest that does not list an amount still counts as 75 with the faction that offers it. Those two search every expansion back to Legion. Gold and Collectables follow the expansions you turn on. Only Midnight is on until you turn others on.
- The Gold header is the total gold. Collectables shows how many you can still pick up. Currency and Reputation show how much of that reward is up.
- The same quest can show in more than one group.
- A hunt with nothing up is left off the list. World Quests hides when every hunt is empty. Turn that off under World Quests if you want the empty line.
- Show completed quests keeps a finished world quest on the list so you can check your other characters. Leave it off and a cleared board hides that group. Hover a quest to see who has finished it.
- Right-click a quest to hide it until you reload. The map pin sets a waypoint.

### Adjusted features

**Abundance**
- Abundance shows how many Shard of Dundun you are holding, as 4+2/8 Shard of Dundun. The quest adds 2, so the line turns green at 6.

**New installs**
- A new install starts with Professions, this patch's activities (The Coiled Isle and the Vaults), and Seasonal Activities.
- Older patches, Collections, Power, Ready to Buy, and World Quests stay off until you turn them on in Options.
- If you already use Task Tracker, your list stays as you left it.
- A new install uses the Compact theme and Classic icons. Change either under Options, on the Style page.
- Welcome Tasks sits at the top. Those tasks point at Edit mode, Options, and turning more modules on. Check one off and it deletes itself.

## 12.1.0.7

### Adjusted features

**List and options**
- Group arrows use the same chevron as the other icons. A closed group points right. An open group points down. Tintable and Classic both use it.
- A menu shows an arrow on the right. That includes task type, second line, collectable expansion and category, and the color theme.

### Bug fixes

**Currency tooltip**
- Can buy and Full list leave out mounts you already have. The prices are only for ones you still need.

**Overrides**
- A manual check stays on the character who set it. That includes character tasks and built-in weeklies. Checking one off on an alt no longer checks it off on your other characters.

**Characters on hover**
- Built-in weeklies use that character's progress. Yours matches the row. Other characters show what was saved the last time you played them this week. Log in on an alt once if their line is blank.

**Trovehunter's Bounty**
- Each character tracks their own map. Using it on one character no longer checks the weekly off on your other characters. If you already used this week's map, that character may need one click to check it off again.

## 12.1.0.6

### New features

**Changelog**
- The version number sits at the bottom left of Options. Click it to open the changelog.
- A red dot sits next to that number until you open the changelog. It comes back on the next version.

**Voidstorm collectables**
- **Duskbrute Harrower** and **Nova** are under Collections for Voidstorm. Both are a chance from a Slayer's Duellum Trove, the paragon chest after Exalted. Each row completes when you have it. The map pin points at Thraxadar.

**Task secondary data**
- A task can show a second line. You pick what it shows: reputation, kills, a collectable, items, a quest, an achievement, or gold. The line only shows information. It does not change when the task is done.
- A kill line can show your total kills, and the drop rate from Rarity when that addon is installed. Rarity Drop Rate uses that addon's attempts and its 1 in N odds.
- The ten rare-kill mounts start with that line on: the eight zone rares, plus Ruby Writhe and Topaz Skyfang. It shows Rarity's attempt count and the drop rate.
- Hexed Vilefeather Eagle's second line is Vile Essence, counted toward 1,000. An item line can have its own goal.
- Same mobs as this task copies the mobs already on the task. On a collectable it also fills the drop item, and the line uses that task's count.
- Some collectables, like Augmented Stormray, are not tracked by mob kills, so that mob list stays empty.
- Under Options, List, Second line in tooltip moves that line into the tooltip for every task.

**Built-in tasks**
- Collections, reputations, and farm tasks can be edited like a task you made. Turn one off in Modules, then on again, and it goes back to the built-in task.

### Adjusted features

**Full list**
- Hovering a currency, **Full list** is how much you still need for collectables you don't already have. The prices under it are the most expensive of what's left. It can still sit a bit apart from AllTheThings when they count a quest, or a cost that isn't a straight item price.

**Vaults of Atal'Utek**
- Hawkeye Soho is one daily. Patrolling the Temple, Relentless Strikes, and Decisive Incursions rotate, and you can only pick up one. The row checks off when you turn that one in.

**Ready to Buy**
- Vendors in the zone you are standing in use the Current zone color and sit at the top of that list. The rest stay in name order. Turn Color zone off and they still sit at the top, without the tint.
- The eye on Ready to Buy Tasks hides vendors outside the zone you are standing in. When the eye looks covered, only that zone stays. The Vaults and The Coiled Isle stay separate.

### Bug fixes

**Ready to Buy**
- Vendor collectables from the Coiled Isle and the Vaults show up. That includes housing from Jan'sari the Watchful and the Skull of Er'inye. Those zones were left out before.
- Ensembles you have already learned stay off the list. That includes a set whose tooltip says Already known.

**Azta'rec**
- Azta'rec (Delves) completes when you summon him with a Scalebound Herald's Flute in a delve and loot the cache he leaves. Once a week. His own delve, Venomfall Deeps, does not check this off.

## 12.1.0.5

### New features

- **Ready to Buy** lists collectables you can purchase from vendors right now, based on the currencies and gold you have. Each seller is one row under **Generated Tasks** at the bottom of the list. This needs AllTheThings.
  - The row shows how many items this spend can buy, the currencies that spend uses, and your standing with that reputation.
  - The same coins are not counted twice. Items you do not have the reputation for stay in the row and are not counted.
  - A price you can pay is green, and so is a reputation you already meet. A price you cannot pay, or a reputation that is still too low, is red.
  - Collectables that cost only gold are included. Companion pets count, not only battle pets.
  - You do not already own the items that are counted. That includes ensembles you have already learned, and decor you already have at least one of.
  - Consumables and other items that are not collectables are left out.
  - When nothing is ready, the list says so for the expansions you have turned on.
  - The map pin sits on the name when a row has a second line.
  - A map pin sets a TomTom waypoint when AllTheThings has one for that vendor.
  - Right-click a vendor to hide it until you reload. Refresh scans again.
- **Options → Generative tasks** has a **Ready to Buy** section, like the groups in Modules.
  - Spend can run high to low or low to high.
  - **Show** lists mounts, pets, toys, appearances, housing, recipes, and other in equal columns that wrap when the window is narrow.
  - **Show** and **Expansions** collapse under Ready to Buy.
  - **Expansions** has a switch for each expansion. Only Midnight is on until you turn others on.
  - The switch on the Ready to Buy row turns the list on or off.
  - You can list currencies you are not ready to spend. Add one by shift-clicking it or typing its name. Those purchases are left out.

### Adjusted features

### Bug fixes

## 12.1.0.4

### New features

- Title bar menu: **Current Zone Filter** sits above a colored bar, with Collapse all and Expand all below it. The label is the option you picked (**Focus**, **Zone Only**, or **Zone + Global**), not the zone name. Options → General chooses what that click does.
- **Focus** opens that zone and collapses the rest.
- **Zone Only** hides everything else.
- **Zone + Global** hides other zones and keeps Power, professions, and your own tasks.
- **Include parent** and **Include subzone** add the zone above or below you (the Vaults and The Coiled Isle). Both can be on.
- **Color zone** tints the zone you are standing in (on by default). That color is **Current zone** in Options → Style → Customize.
- **Fade** puts that color behind the right side of the row and lets it thin out about a third of the way toward the left, instead of filling the row.

### Adjusted features

- Custom themes have an **Icons** color. It starts as the same color as main text, and you can change it on its own. Built-in themes keep using the main text color for those icons.
- Options has a full redesign: a cleaner layout with a consistent setup across every page. The selected highlight is a soft tint instead of a bright fill. Style settings, including note peek, use sliders with even spacing. **Defaults** on that page restores the built-in sizes and spacing. Your color theme stays as you set it. Header and row height are the thickness in pixels, centered on the theme, and the other size sliders sit on the normal value with room either way.
- Addon text no longer draws a drop shadow, so labels stay sharp on dark panels.
- Style no longer has a single list font percent. **Headers** and **Tasks** each have a **Font** size in pixels. Each one starts at that theme's own size. Row height is separate from the font size.
- Style **Title bar** sits under Sizes. **Text** and **Icons** set the tracker title and the buttons on that bar. Text starts at the theme size. Icons start at the usual button size.
- **Three-Eyed Fish** explains the steps: Venom Trawler is rank 4 of 5 with Captain Tokka, then an Eerie Bauble for 250 Voidlight, used on a fishing pool, fishes up a Star Ooze. That starts a chain of 3 quests.

### Bug fixes

- **Whole UI** scale keeps the tracker’s top-left corner where it is. The window grows from that corner and stays on screen, instead of jumping to the top.
- **Wrap lines** breaks a long task name onto extra lines when the list is narrow, instead of leaving a gap under a single cut-off line.
- The Mythic+ **Great Vault** Power hint uses your lowest equipped piece (or the Details ilvl), like the end-of-dungeon hint. Empty vault slots no longer recommend **+0 for ilvl 302+** when your gear is already higher.

## 12.1.0.3

### New features

- Title bar **collapse/expand** button (left of minimize). Hover it for **Collapse all**, **Expand all**, **Collapse 1 level**, and **Expand 1 level**. One-level steps move the deepest open groups one nest up or down. The menu stays open so you can click more than once; move the mouse away when you are done.
- Custom tasks can use a **Temporary** reset. They show **[T]** on the list and remove themselves when they complete (toys, mounts, achievements, and other one-shot farms). Hover Temporary in the task window for a short explanation.

## 12.1.0.2

### New features

- **Custom themes:** Options → Style → **Customize…** makes a copy of the current palette. Built-in themes are never overwritten. You can rename, recolor, or delete custom copies (up to 20). Colors apply when you Save. Fonts, spacing, and row stripes stay with the theme you copied from — pick Compact for a tight list, Tome or Paper for a roomier one.
- **More palettes:** **Compact**, **Void**, **Verdant**, **Tome**, and **Paper**, plus the existing Dark, Nord, Gilded, Parchment, and Ivory.
- **Patch 12.1.0 Collections:** Toys, Mounts, Pets, and Reputations (Zul’jarra’s Forces and Captain Tokka). In Modules, Collections sits inside Patch 12.1.0 (newest patch first). Collection headers use a distinct color. Rows complete when you own the collectable or hit max rank; some mounts and pets are weekly farms that still complete when you learn them. The same 12.1 items appear in Add Task → Collectable.
- Hovering a task shows a short tooltip **beside the list**, level with the mouse. Built-in tasks explain what they are and how to do them there, so **Notes** is yours. Item, currency, and achievement rows include the in-game tooltip text. Achievement rows use your live criteria progress. Hold **Ctrl** for debug IDs. **Options → Characters** lists every alt the addon has seen; turn on **Tooltip** to add that character (class-colored name and status) at the bottom of task hovers. **Currency total** and **Highest reputation** at the top of that page control the extra account-sum and top-standing lines (on by default). **Remove** drops an alt’s stored data from the list; log in on them again to add them back. Warband reputations such as Zul’jarra’s Forces and Captain Tokka show the same rank on every character.
- Quest rows that have been picked up show **Current Active Quest** with the quest name and ID in quest gold (handy when a weekly has several possible quests).
- Vendor collectables (NPC-sold toys, mounts, and pets) show **Requirements** on hover after the built-in note: renown, friendship, currency, gold, or items, with your current count. Green if you can afford it right now, red if you can’t. Hovering a currency like **Corrosive Coins** lists up to five vendor items it buys (**Can buy**), one line each: price, type, then name (long names cut off). A **Full list** line above that is your count vs the cost of everything it buys. Options → General → **Connected addons** has an **AllTheThings** toggle (with a ?) so you can hide that extra data, or see that installing AllTheThings unlocks more vendor costs.
- **Collections** now covers more Coiled Isle, Vaults, and Renown toys, mounts, and pets. Wild-caught critters are one **The Coiled Isle Safari** bar. Vendor and drop rows have Way pins for Jan'sari, Sluggs, Er'inye, Du'gal, Big Mon, Olawu, and the Image of Astalor. **Zan** and **Three-Eyed Fish** complete from the pet or their quests; **Ki'clak** still uses the snacks achievement bar and now completes when you have the pet too.
- **Ral’kala** farms under Collections: **Hexflame Reaver**, **Pale Hexscale**, and **Preyhunter’s Masquerade**. Summon at a Haunted Brazier with Ossified Relics (100 to spawn, at least 1 for loot). No weekly lockout — each qualifying kill +1 (goal 50). The row also completes when you learn that drop. Way pins the Image of Astalor to turn on Curse of the Isle.
- **Collections → Currency** (under Patch 12.1.0) tracks **Corrosive Coins** — how many you have right now. Completes at your goal (default 10000). The same currency is in Add Task → Collectable → Currency.
- **Patch list grouping:** Options → General and the top of Options → Modules. All three keep a **Midnight** expansion header. **Default** is Midnight > Patch > Zone, with Collections on the patch. **Patch > zone** is Midnight > Patch > Zone, with Collections under each zone. **Zones** is Midnight > Zone (no patch headers), Collections under each zone. **Expansion Activities** sits first (Prey, rotating weeklies). **Instanced Activities** is for dungeon, raid, and delve rows (Halduron’s Weekly now; instance collections later). **Lost Legends** is under **Harandar**. **Vaults of Atal’Utek** sits under **The Coiled Isle**, after that zone’s Collections. Hover each grouping button for a short description.
- Weekly farm rows for the **12.0.0** world-rare mounts, two per original Midnight zone: **Rootstalker Grimlynx** and **Vibrant Petalwing** (Harandar), **Cerulean Hawkstrider** and **Cobalt Dragonhawk** (Quel’Thalas), **Escaped Witherbark Pango** and **Amani Sharptalon** (**Zul’Aman**), **Sanguine Harrower** and **Augmented Stormray** (Voidstorm). Same style as the Coiled Isle rare farms — each rare’s daily bonus loot +1, completes when you learn the mount. In Default they sit under Patch 12.0.0 Collections; in the other grouping modes they sit under those zones.
- **Hexed Vilefeather Eagle** (Zul’Aman): farm **Vile Essence** in Maisara Deeps for the Abandoned Ritual Skull (1000 Essence). Weekly target 100 by default; the row also completes when you learn the mount. Way pins the skull.
- **Voidlight Marl** under Collections → Currency (Patch 12.0.0 / Expansion Activities). Weekly earned target 10000 by default. Hover still lists vendor items that currency buys.

### Adjusted features

- Options → Style spacing is split into **List**, **Headers**, and **Tasks**. You can set list padding (including top/bottom), nest indent, header and task extra height, gaps, title inset, checkbox size, row and command icon size, and space between titles and icons. Narrow titles (truncate vs wrap) sit under Tasks. List rows and group headers follow the current theme’s size (Compact is tighter; Tome and Paper are roomier), then extra height.
- In Options → Modules → Collections, owned toys, mounts, and pets (and maxed reputations) show **Have** instead of On. That hides them from the list; click Have to show the row again. The On / Off / Have buttons are half as wide as before. Module rows use as many columns as fit the panel (names wrap to two lines); nested groups drop to fewer columns instead of clipping.
- **Venomous Coiler** under Collections → Mounts tracks **Assault the Vault** as an achievement bar (how many of the 10 criteria you have), like Emerald Skyfang. Account-wide; no weekly reset. It still completes when you learn the mount.
- **Lil' Mon** is a weekly account-wide **Big Mon** kill bar (5). Way still pins Big Mon. It no longer completes just from owning the pet.
- If a task has only one command, that icon sits on the row — click it to run (out of combat). Two or more still open the flyout. Command icons are a bit smaller than the row so they sit closer to the quest markers. Built-in **Way** commands use the taxi-node pin.
- Coiled Isle and Vaults of Atal’Utek weeklies/dailies have a **Way** command that pins Captain Tokka, Tokka’s Folly (Gills and Sluggs), Sanctum Attendant Ethrandil, Du’gal, or the Eastern Fang entrance from any zone (TomTom). Ancient Amani Mask pins the chest. Ral’kala farms pin the Image of Astalor.
- **Patch 12.1.0** dailies and weeklies are split into **The Coiled Isle** and **Vaults of Atal’Utek**. That group now tracks the Vaults weekly and dailies, Open Sea Fishing, Tokka’s Folly dailies from **Brinedrinker Gills** and **Second Mate Sluggs**, and the Prey daily from **Sanctum Attendant Ethrandil**. Gills and Sluggs complete when you turn in any of that NPC’s dailies. Ethrandil completes on Prey: Anguish from Beyond. Coiled Isle Nightmare hunts still count on Prey: Nightmare. Open Sea Fishing notes that it needs rank 4 (Venom Trawler) with Captain Tokka.
- **Du’gal** under Vaults of Atal’Utek stays off the list until you learn **Spirit of Tok’jara** (Collections → Mounts; Renown 10 with Zul’jarra’s Forces starts the six-day chain). After that, his rotating dailies show up. Completes when you turn in any of those dailies. Way pins Du’gal at the Amani Foothold.
- **Trovehunter’s Bounty** (Delves) tracks this season’s map item.
- Switching themes keeps Options on the section you were on (for example Style).
- New advanced tasks default to account-wide weekly (you can change either).
- **Power** compares rewards to your **weakest equipped piece**, not overall item level. The Details box shows that number; type a different one only if you want to override it. Hints use Season 2 pinnacle and Prey rewards (Mistcrests). Prey chests count for the first two hunts. Abundance and Special Assignment show this season’s caches. **Cursed Surges** shares this week’s two pinnacle caches. After you use that limit, weeklies that already won still show that reward. The Mythic+ **Great Vault** hint uses the same “Run +X for ilvl Y+” line as end-of-dungeon.
- The Power **Details** table has normal vertical and horizontal scrollbars. Compact columns (#, Power, Item, Curr, ilvl, Pin) are centered. Drag the L-shaped corner to resize; the size is remembered.
- **Prey: Nightmare** counts the Coiled Isle hunts.
- **Decor Duels** is removed; that activity is gone.

### Bug fixes

- The list scrollbar stays on the panel when you collapse or expand groups, turn Edit on or off, or show/hide completed. It no longer hangs off the bottom after the list gets shorter.
- The tracker stays where you put it on reload, theme change, minimize/expand, and login.
- **Nullaeus** (Delves) completes when you loot the bag he leaves behind. A kill still counts if the encounter actually ends. It does not complete from Delver’s Bounty map loot.
- Duplicate Collections groups from an earlier load are merged into one.
- Collection subsections with nothing left to show (for example **Toys** when you already have the Amani Mask) no longer sit on the list as empty 0/0 headers. Click **Collected** in Modules if you still want that row.
- Collection Way pins line up in one column. Ki'clak’s pin was sitting a few pixels off because achievement rows used a narrower progress slot than the other pet rows.
- Combat no longer throws a blocked-action error when combat-log kill tracking is off.
- Nameplates fading out no longer error on unit health (Midnight secret values).
- Targeting and nameplate kills no longer error when the game hides unit IDs in combat.

## 12.1.0.1

Versioning is **game patch + addon revision**: `12.1.0` is the WoW patch, `.1` is this addon release. Interface updated for patch **12.1.0**.

### New features

- **Color themes:** **Nord** (cool polar night), **Gilded** (gold on mahogany), and **Ivory** (cool light). Switch under Options → Style.

### Bug fixes

- Notes on Mythic+ hint rows are no longer wiped on login or reload.
- Loot-mode mob kills count again when you loot a matching NPC.
- Gold tasks keep small copper/silver gains instead of rounding them away.
- Switching Dark / Parchment no longer blanks the task list until `/reload`.
- Add Task no longer copies boss-instance fields from the last mob-kill task you edited.
- Collapse / expand no longer leaves empty space where the tasks should be.
- Renaming the Power or Midnight patch groups no longer creates a duplicate or treats a custom group with the same name as the module.
- Stormarion / Spark Quest: turning in the quest updates every row that tracks it.
- Character-task clicks only save that task, not every character’s progress. Deleted tasks are dropped from per-character storage.
- Note and command icons on a row open notes or the flyout instead of completing the task.

## 1.4.4

### Compatibility

- Interface updated for WoW patch **12.0.7** (no gameplay changes).

## 1.4.3

### Bug fixes

- **Professions on alts:** Profession subsections (Alchemy, Mining, etc.) only show for professions that character has learned. Empty **0/0** headers from other alts are gone.

## 1.4.2

### Professions module (Midnight)

- New **Professions** module under **Options → Modules**, with a **Professions** group in the task list (after Seasonal Activities).
- **Abundance** weekly moved from **Patch 12.0.0** to **Professions** (still appears in **Power** when reward tracking applies). Existing lists update on load.
- The **Professions** group shows **(Open a Profession to load)** until you open any profession window once on that character.
- Only **primary professions you have learned** get a subsection, with weekly rows for orders/gathering, treasures or samples, treatise, and catch-up knowledge.

### Account vs Character tasks

- User tasks can be **Character** (default) or **Account** under **Progress scope** in add/edit.
- **Character** tasks keep **separate progress on each alt**. **On other characters:** **Hidden** (only the creator sees it) or **Shown** (every character sees the row with their own progress). Default is **Hidden**.
- **Account** tasks share progress across the account. Daily/weekly account tasks show **[AD]** / **[AW]** instead of **[D]** / **[W]**.
- On first update after install, existing tasks default to **Character** scope. Built-in weeklies like **Great Vault** stay **Account** when they are once per account. Existing progress is moved automatically.
- Built-in module rows still track account-wide. **Options → Modules** (and the matching **Power** toggles) are **per character**. Turning off Delves on one alt no longer hides it on others.

### UI

- **Options** closes with **Escape**.
- **Add / Edit Task** is taller for **Progress scope** and **On other characters**, with action buttons in a footer so they do not overlap the form.

### Bug fixes

- You can create and delete custom groups named like **General**, **Delves**, or **Power** without them becoming undeletable.
- Shift-click progress editor: setting only the automated tally no longer forces a manual **0** lock.
- Switching a task from **Character** to **Account** keeps the active character’s progress.
- Character progress no longer resets on every instance change — only when you switch characters. Item/currency totals no longer flash **0** right after zoning.
- Collectable tasks (e.g. Escaped Witherbark Pango): first quest sync no longer forces **0** when you already set progress; shift-click updates the tally.
- Weekly quest tasks (e.g. Housing Weekly) no longer drop to **0/1** after the game’s daily reset when the task is set to **Weekly**.

## 1.4.1

### Bug fixes

- **Weekly multi-quest rows (e.g. Prey):** If a period baseline was missing but saved progress was still there, the bar could show **0/N** after an update. Progress no longer drops to zero in that case.

### Reputation tasks

- **Standing** goal: the list shows current reputation toward the target (for example `4520/9000` for Honored, or Renown current/target) instead of a `0/1` flag.

## 1.4

Smoother list painting when row content has not changed (less hitching while the list is open).

## 1.3.5

### Achievements

- For a **specific criterion**, **Progress mode** can follow WoW’s live **current / total** bar (**In-game bar**), or keep **Weekly target** (progress since reset vs your goal).

### Task list

- **Shift-click `x/x`:** two fields — **tracked** (what the list shows) and **automated** (game sync). **Set** applies automated first, then tracked.

## 1.3.4

### General

- **Daily / weekly reset schedule** under **Settings → General:** Auto (realm timers), US, EU, or Custom (hour, minute, weekday, and time zone). Resets also apply after entering the world and when weekly rewards update, without a full `/reload`.

### Edit mode

- **Hide completed** works in Edit mode the same as when edit is off.

### Modules

- **Decor Duels** (was Delve Duels). **Spark Quest** under **Seasonal Activities → General** (any one of the linked weeklies completes the row).

### Import / export

- Mail icon on Add/Edit task, group dialogs, and the edit-mode add strip to copy or paste a share string. Progress is not copied. Title-bar **×** closes these windows.

## 1.3.3

### Collectable tasks

- New **Collectable** type: expansion, category, catalog pick, goal, and reset. Includes Midnight / Eversong / Ghostlands / Stormray mounts tied to rare dailies. **Nether Swept Drake** can also progress from fishing in the supported areas.

### Task list

- Removed the per-row revert icon. **Ctrl+left-click** the row to clear a manual override.
- Registry rows: **Right-click** the row or **#/#** to lower progress by 1, even when Shift is required for left-click.
- Left-click at max (or at zero) no longer saves a manual state when nothing changed.

### Advanced tasks

- Item and currency tasks keep updating in the background while a manual lock is on. **Ctrl+left-click** clears the lock.

### Season 1 weeklies

- Shared quest pools (Lost Legends, Fortify, Halduron’s Weekly, etc.) only count **new** completions after weekly reset.
- Void Assaults: either assault quest can complete the row.
- Special Assignment: updated quest list, **2** per week; pinnacle hints and slot counting fixed. Removed Unity Against the Void and Saltheril's Soiree.

### Modules (Midnight)

- **Patch 12.0.0** / **Patch 12.0.5** groups. Prey under 12.0.0; Void Assaults under 12.0.5. Existing lists merge on first load.

### Mob kills

- Automatic world/loot counting is off in dungeons, raids, arenas, and battlegrounds. Boss tracking at encounter end still works.

## 1.3.2

- **Mob Kills** advanced task type (world, loot, or instance bosses).
- **Power** section for weekly rewards vs your item level, with an optional Details view and ilvl override.
- Mythic+ Great Vault hint no longer recommends low keys while vault data is loading; hint rows complete at the **+10** upgrade cap.
- **Alt-click** a row to open the task editor.

## 1.3.1

Smoother list updates during busy game events.

## 1.3

- Better **Paragon** reputation tracking.
- Group headers show clearer completion totals. **Hide completed** can collapse finished groups.
- Safer Edit mode; better narrow-window titles; set progress counts from the list.

## 1.2

- Reputation: Check button for faction ID/link/name; Renown vs classic standing; weekly gain still moves at max Renown (including Paragon).
- Great Vault: **Collect Vault** when a reward is ready.
- Quest state icons (available / trivial / turn-in) on quest tasks and quest registry rows.
- Achievements: validation, criterion picker, extra dialog height.
- Items vs Currency mode, with validation.
- **Prey: Nightmarish** weekly in the Prey group.
