-- Last five changelog sections. Newest first.
-- Do not use a Unicode arrow in text this window draws. The game font has no glyph
-- for it, so it shows as an empty box. The window replaces → with the help arrow
-- (CovenantSanctum-Renown-DoubleArrow-Depressed, flipped right). Do not pick another arrow.

TaskTracker = TaskTracker or {}

TaskTracker.WHATS_NEW = {
    {
        version = "12.1.5.4",
        text = [[New features
Sync
• Added Sync. You can send a saved task to a character on another account. They get the task on their list and can move it. The count, and whether the task is done, stay matched to yours.
• Sync defaults to off. Turn it on under Options, Advanced. The Sync button then sits with Edit data, Notes, and Popout. Type their character name and server.
• On a task that belongs to one character, each character on your account can send their own copy. Logging an alt does not change a copy that was already sent. A module row someone sent you stays on your list even if you have that row turned off.
• They can't check the task off. Turn on They can add to the count if you want them to raise the count. That increase syncs back to you. They still can't lower it. If you both add to the count at the same time, both adds count. Edit on a task they sent you opens a small window that shows who sent it and when. Delete removes it. The full task editor stays closed. Stop sharing removes the task from their list too. They need to be online for that.
• An update goes out when you log in, and again when the count changes. A weekly task someone sent you keeps this week's count. Logging in on another day this week does not open it again. It clears on the following week. A per-character task only updates while the character who shared it is logged in, and both of you need to be online for that send to land. While Sync is off, a new task is not sent or received. A task that was already shared still follows the owner.
• You can show the task owner's name on the task or in the tooltip. It defaults to on, with the name on the task in gray after the title. It works the other way too. When you share a task, that same spot says who you sent it to. Tooltip moves the name onto the row hover. None hides it.
• Sync all is there for a share that has fallen behind. It defaults to off. Turn it on under Sync and the button sits on the tracker title bar. One click sends every shared task again. Tasks you sent go out with your current count. Tasks someone sent you ask them for a fresh copy. You both still need to be online.

Boss kills
• In Boss mode, you can type part of an instance or boss name. Suggestions come from the dungeon journal, and a shorter name still matches the full boss.
• The check button names that boss before you kill it. The kill still has to finish successfully.

Shortcuts
• Added Manual / automatic under Task management in Shortcuts. On a task that tracks itself, that click switches between keeping the number you set and following the game. The count stays where it is until the game updates the task.
• Delete task, under Task management, asks before it removes the task.

Adjusted features
• Added an Advanced page in Options, under Generative tasks. It holds settings that can need extra setup, and a note on that page says so. Hide collected in the picker is no longer an Options setting. It stays on the Collectable task, when you pick the item.
• Profession rows can now be edited like a task you made. That includes Abundance, the weeklies under each profession, and Catch-up Knowledge. Turn one off in Modules, then on again, and it goes back to the built-in task.

Bug fixes
• A weekly task someone sent you stays done for the rest of the week, even if you have not logged that character again. It still clears on the weekly reset.
• Checking a quest task off yourself stays until that task resets. Reloading was clearing it.
• Weekly profession tasks you already finished stay finished until the weekly reset. A row with several quests, such as Weekly Treasures, was treating this week's finish as an older one and opening the task again.
• A group you made with nothing in it hides. That includes one whose only contents are other empty groups. Turn on edit mode and it comes back, so you can add a task or another group. Leave edit mode and it hides again.
• A daily or weekly task that lists several quests counts a quest you finish during that day or week. A quest you finished earlier stays checked off in the game, and that does not complete the task.
• A custom Prey hunt counts each time you finish it. Whichever difficulty you picked can already show that hunt in your log. Turning it in adds one on that row, including when you finish the same hunt again this week, up to 4.
• A daily or weekly task resets for each character. Only the character you were logged in on was starting over, so your other characters stayed done for the rest of that day or week. The next time you log in on one of them, that task starts over. A profession quest that character already finished this week still shows finished.
• Weekly Treasures counts a treasure you pick up this week. The first one was saved as an older finish, so the row stayed at 0. A treasure you already picked up this week counts, and the next one does too.
• A second group named Professions, or a profession name under that group, stays on the group window and asks you to pick another name.
]],
    },
    {
        version = "12.1.5.3",
        text = [[New features
World Quests
• Gold world quests start at 500 gold. Min gold sits next to Currency. Lower it to include smaller payouts. Clear the box to show every gold quest.

Shortcuts
• A Shortcuts page sits between Modules and Generative tasks. It sets clicks on the task name, the count, and Notes. Those sections start folded. Open one, then open Left, Right, or Middle. Each of those holds Normal, Ctrl, Alt, and Shift. Normal is a click with no extra key. A plain left click counts up. A plain right click counts down. Shift does not, until you set it.
• Ctrl-left starts as Task special. Achievement opens the achievement window. The other task types start blank. Custom runs a command you type.
• Notes keeps Shift-left for the popout and Alt-left to open Notes.
• The custom command box is the same width as the dropdown. The rows and the section titles use one text size.
• Commands are grouped. Task management holds Edit task, Count up, and Count down. Task special holds Open achievement. On the task name and the count it also holds Task special, which still opens the task types. Notes holds Edit notes and Open popout.
• A switch sits to the right of each command. On shows that click in the task tooltip. On the task name, a plain left click (count up) and a plain right click (count down) start on. Those lines show the click icon only. Alt-left on the task name and the count starts on. A task special that is not Nothing starts on. The rest start off.

Adjusted features
• Dropdowns in Options use the same gray as the list on the left, so they show up on the page. The choice under your cursor lights up. Opening one closes the dropdown that was already open.
• Module headers use the same text size as the rest of Options.
• Choose icon has Use command at the top. It uses the same #showtooltip check as a macro, so a /cast or /use line can supply the picture.
• The command box has a larger editor. Lines runs each line on its own, so a waypoint list fits. Full still runs the whole command as one macro.
• On a note popout, close, edit, and the command icons sit inside the note. Close and edit are on the title line. Commands sit along the bottom.

Bug fixes
• The Abundance Toy button shows on the row with your other command buttons.
• A note popout left open comes back after a reload or when you log in again, in the same place.
• Style size sliders keep your place in Options. The list no longer jumps back to the top.
]],
    },
    {
        version = "12.1.5.2",
        text = [[New features
Currencies
• Remnant of Anguish is with Voidlight Marl under Collections, then Currency, on Patch 12.0.0. It shows in Expansion Activities. The weekly goal starts at 1000.

Tasks
• In the task window, When completed tasks are hidden starts on Hide. Choose Keep to leave that task on the list anyway.

List
• The group menu lists Hide Modules, Hide Collections, and Hide Custom. Everything starts on the list. Click a row to hide that set, and the label switches to Show. Collections is the Collections headers. Custom is groups and tasks you added. Modules is the rest, such as Power, Seasonal, Professions, and patch activities.

Professions
• Abundance has a Toy button for Dundun's Abundant Travel Method. You need the toy. It only works in Midnight zones, and it has a 30 minute cooldown.

Style
• Popout sliders follow Compact, Comfy, and Spacious. Change them on Custom. Normal and Mouse Over are separate groups. Sliders adjust opacity. Close stays at least 10% so you can still find it.

List
• Holding Ctrl on a row no longer shows extra IDs in the tooltip.

Settings
• The first section in General is labeled General.
• New modules starts off. A module added in a later update stays off until you turn it on under Modules. Turn it on if you want those added to the list. Modules you already have stay as they are.
• Hover a row in General for what that setting does. Help tooltips starts on. Turn it off to hide those hover notes. Task tooltips on the list stay.

Adjusted features
Notes
• The notes section was redesigned. Notes and Popout sit at the bottom of the task settings. Commands are in the grey column on the left, with the name and slash command under the icon. An empty note shows "Write a note here." That line, and a blank command, aren't saved until you change them. On a new task, the note is saved when you add the task.
• Popout is a movable copy of the note. You can keep more than one open, and each one comes back after a reload where you left it. Close, edit, and commands sit on the right. Edit opens Notes. On the list, the note icon stays on a task that has a note. Click opens Notes. Shift-click opens the popout.
• On an existing task, Edit data is on the left of that row, under Hide and Keep. Notes is in the middle. Click Edit data to set progress.
• The progress editor has Locked and Automatic on a task that tracks itself. Locked keeps the number you set. Automatic follows the game. Ctrl-left on a task no longer clears that.
• Ctrl-left on an achievement task opens it in the achievement window. The tooltip says that under the character list, with a left-click icon next to Ctrl. Other rows say Nothing. Alt-left on the count opens the task window. The shortcut line says Edit task. Shift-left on a task count no longer opens the progress editor.
• Shortcut, in General, starts on. Turn it off to hide those shortcut lines. The task tooltip stays.

Bug fixes
Reputations
• Aqir Research Enclave was using the full reputation bar, so Exalted did not finish the row. It uses the friendship bar and finishes at 5000. The second line shows that rank.

Prey
• Prey: Nightmare counts Preferential Killing, the hunt where you pick the target, zone, and difficulty. The game uses that same quest on every difficulty, so it counts on this row. Each finish counts, up to 4.

Edit mode
• Shard of Dundun was showing under the first task as well as Abundance. It stays on Abundance.
]],
    },
    {
        version = "12.1.5.1",
        text = [[New features
Tasks
• A task can hold up to four goals. Once there is a second goal, Completes when sits above them. Click it to switch between all goals and any goal.
• Tips on the task window sit to the right of the window, level with the cursor.
• Settings sit on the left. The task itself is on the right, including its name. Add Additional Goal sits under the last goal. Add Secondary Data sits at the bottom. Secondary data stays hidden until you add it. The x beside it removes that section, and the button comes back.
• Second line fields share one width.
• A closed goal is one line, with the type and the count. The open goal uses that line for the task type, and the options sit under it.
• The row shows each count, joined with "and" or "or".

Patch 12.1.5
• Modules has Patch 12.1.5. Aqir Invasions has the satchel. Collections, then Reputations, has the two Renowns.

Reputations
• The Labyrinth of Kindo'jan tracks weekly Renown. The goal starts at 2100. The second line shows your Renown.
• Aqir Research Enclave tracks weekly reputation. The goal starts at 500. The second line shows your Renown.
• Delver's Journey, the one you check with Valeera, is under Midnight reputations. It tracks weekly Renown. The goal starts at 4200, one rank. The second line shows your Renown.

Aqir Invasions
• Aqir Research Satchel finishes when you loot it this week. Power treats it as Champion 2 gear, item level 295. After that, it keeps Champion Mistcrest until 309.

Adjusted features
Zones
• Halduron's Weekly and the Labyrinth of Kindo'jan show under Expansion Activities.

Bug fixes
World Quests
• Gold on a world quest shows the coin icons. On a narrow list, that line was cut off and the gold amount was followed by leftover text.

Reputations
• The Labyrinth of Kindo'jan row stayed at 0 and had no second line. It now follows your Renown bar, including progress you already earned. The second line shows your rank.
• Finishing a Renown rank was adding about a million to the weekly count. It now adds the size of that rank.

Compatibility
• After the 12.1.5 update, the list was throwing an error every few seconds. GetItemCount was removed. Item counts now use C_Item.GetItemCount, so that spam stops.
]],
    },
    {
        version = "12.1.0.11",
        text = [[New features
Edit mode
• Options → General → List has List organization. Pick and place works as it does now. Drag and drop lets you drag = to a gap between rows. The row you are moving fades, and a copy of it follows the cursor.
• Official sections, such as Midnight, don't take new tasks. Add the task under a group you made.

Delves
• The Delves header has Delve-O-Bot 7001's icon. Click it to call a ride to a random Bountiful Delve. That needs the toy, and it only works out of combat.

Dungeons and raids
• Mythic+ in Seasonal Activities is now Dungeons. Normal and Heroic sit above the Mythic+ hints.
• Normal dungeons need level 80 and drop item level 253. Heroic needs level 90 and drops 276. After that gear is no longer an upgrade, Power keeps Adventurer Mistcrest until 282.
• Raids lists Normal, Heroic, and Mythic for the Venomous Abyss. Each row counts bosses killed this week on that difficulty, and finishes when the raid is clear. The rows show 292-302, 305-315, and 318-344. They need level 90. The 344 pieces are the last two Mythic bosses. After the gear, Normal keeps Champion Mistcrest until 309 and Heroic keeps Hero Mistcrest until 322. Myth Mistcrest stops at 334, and Mythic gear goes to 344.
• Each raid difficulty also has a Great Vault row. It counts vault slots for bosses killed on that difficulty, and finishes when the vault is full. That takes 6 bosses. Normal is 305, Heroic is 318, and Mythic is 334-344. The 344 choice is the last two Mythic bosses. Those rows use the same crests.
• Dungeon and raid rows show a Normal, Heroic, or Mythic icon.
• Vault Status sits above Delves.

Adjusted features
Tooltips
• Notes, commands, edit, Toggle off, Move row, Add task, Add group, and the title bar icons open beside the list, in the same spot as a task tooltip.
• Add task and Add group name the section. That header lights up while the line is under your cursor, and while you drag a row onto a gap.
• Toggle off, on an official section, turns off every row in that section.

World Quests
• Each hunt groups its quests by zone, so you can see where to go.

Power
• Power suggestions need level 90. Below 90 they drop off the Power list, and stay on in Midnight and the other sections.
• When no Power row applies, the Power section hides.
• Power details has a Level column for the level that reward needs.

Bug fixes
Power details
• The reward that applies is marked with a check. The old mark drew as a green box.

Power
• Enable all and Disable all under Power turn that section's switches on or off.

Weekly quests on alts
• Rows like Lost Legends track each character on their own. Finishing the quest on an alt marks that character Done.
• An alt who already finished this week before this update stays Incomplete until the next reset. After that, each character keeps their own starting list.
]],
    },
}
