# Case Files

An IELTS practice game disguised as detective work, built in Godot 4. You are a trainee in Unit 9, a London police unit that solves cases where the evidence is language: forged letters, lying witnesses, torn notes. Your partner, Sam, briefs each case, reacts to what you do, and gives hints.

The IELTS task is the game action. Answers do jobs in the story, a wrong answer changes what happens next, and where the exam checks comprehension you prove your answer by tapping the line that shows it.

**Case 01: The Missing Violinist** (about 15 minutes, written for a band 6.5 target)

## Play

The repository root holds the Web export (`index.html`, `index.js`, `index.wasm`, `index.pck`), so GitHub Pages serves the game from the root of the site. The first load downloads about 35 MB; after that the browser keeps it.

To run it on your own computer, serve the folder (the game cannot start from a `file://` address):

```
python3 -m http.server 8000      # then open http://localhost:8000
```

Calls and radio messages are spoken with the browser's built-in speech in a British voice. If a device has no voice, the game shows the transcript to read once instead. Typed answers use real text boxes laid over the game, so the phone's own keyboard opens.

The earlier HTML version is kept in `legacy-html/`.

## How a case plays

1. **Briefing.** Sam sets up the case. It is 5:40 pm; the curtain goes up at 7:30.
2. **Leads.** You choose which leads to follow and in what order. Every lead costs time, mistakes and hints cost more, and the leads together cost more than the time you have. Two leads are optional and give extra evidence cards and word bank entries.

   | Lead | IELTS skill | Costs | Gives |
   | --- | --- | --- | --- |
   | The Wiretap | Listening Part 1: type what you hear | 15 min | the voicemail card |
   | The Tail (after the wiretap) | Listening Part 2: follow directions on a map | 15 min | the car hire receipt |
   | The Interrogation | Reading: True / False / Not Given | 20 min | the broken alibi, two cards about other suspects |
   | The Sales Report (after the interview) | Writing Task 1 skills: find and fix the sentence that misreads a chart | 10 min | the sales report card |
   | The Forgery Lab | Grammar: find three mistakes and choose the corrections | 15 min | the forgery card |
   | The Torn Note | Linking words: rebuild a note so its logic works | 15 min | the note card; Mira is found |
   | The Front Desk (optional) | Reading: find the line that answers the question | 15 min | the front desk log |
   | The Green Room (optional) | Reading: find the line that answers the question | 15 min | the rehearsal room sheet |

3. **Interrogation.** The suspect has a composure meter and you have credibility. You break his statements by tapping the proving line in the schedule, or by presenting an evidence card you collected earlier. The wrong card costs credibility; with none left he ends the interview and you get no alibi card.
4. **Evidence board.** Tap two cards that explain each other and connect them. A correct pair becomes a deduction. A wrong pair costs five minutes.
5. **Accusation.** Name a suspect and choose three proofs from the deductions you made and the cards you hold. Three strong deductions against the right person is a conviction; the right person with weaker proofs walks free; the wrong person reopens the case.
6. **Case report.** Estimated bands for Listening, Reading and Writing from answers that were right first time, plus a result code to compare with a friend.

Three hints per case: Sam points to the right part of the document or replays part of the tape, never the answer. Each costs ten minutes. The notebook keeps case notes, the evidence board, and a word bank of every paraphrase, linker, grammar trap and chart phrase you meet.

## Project layout

```
index.*                      the Web export that GitHub Pages serves
godot/                       the Godot 4.6.1 project
  project.godot, main.tscn
  export_presets.cfg         Web preset (thread support off, so no special server headers are needed)
  cases/missing_violinist.json   Case 01, as data
  scripts/main.gd            engine: screen, people, dialogue, clock, hints, notebook, sound, speech, saving, scoring
  scripts/scenes.gd          one function per scene type
  scripts/ui.gd              paper-and-ink interface builders
  scripts/clock_face.gd, pen_mark.gd, map_view.gd, chart_view.gd   custom-drawn pieces
  web/head_include.html      browser bridge: speech, typed-answer boxes, clipboard
  addons/godot_mini_game/    Godot Mini Game export plugin (v0.3.1), with its bundled 4.6.1 engine
  assets/
    places/        one image per location (unit9, street, office, lab, stagedoor, hall)
    characters/    one image per person and mood, named <person>_<mood>.png
    ui/            desk surfaces, folder, pin, tape, tape reel
    audio/         sound effects (.wav)
    fonts/         Crimson Text, Courier Prime, Kalam (SIL Open Font License)
tools/make_assets.js         regenerates the placeholder art and sounds
tools/export_wechat.gd       exports the WeChat Mini Game package without opening the editor
tools/playtest/baseline.js   fixed-answer playthrough of Case 01; prints the result code
minigame/wechat/             the WeChat Mini Game package (open this folder in WeChat DevTools)
legacy-html/                 the earlier HTML version
```

## Replacing the placeholder art

All artwork and sound is loaded by file name from `godot/assets`. To use finished art, save it over the placeholder with the same name and export again; no code changes.

- **Places:** `places/<id>.png`, landscape 4:3 (the placeholders are 960 x 720). The game crops to the middle band while a document is open, so keep the important things in the middle third.
- **Characters:** `characters/<person>_<mood>.png`, a bust on a transparent background (placeholders are 400 x 480), feet of the bust at the bottom edge. Moods in use: `neutral`, `pleased`, `annoyed` for Sam; `neutral`, `smug`, `nervous`, `sweating`, `cracked` for Victor. If a mood file is missing the game uses `<person>_neutral.png`.
- **Sounds:** `audio/<name>.wav`.

## Adding a case

A case is one JSON file in `godot/cases`. Copy `missing_violinist.json`, change the content, and add its path to `CASES` at the top of `scripts/main.gd`. No other code changes are needed while you use the existing scene types.

Top-level keys: `id`, `code`, `number`, `title`, `clock` (start, deadline), `hints`, `hintCost`, `mistakeCost`, `cast`, `briefing`, `hub`, `leads`, `board`, `accusation`, `report`, `evidence`.

- `leads[]`: `id`, `cost` in minutes, `teaser`, optional `requires` (lead ids) and `optional`, and a `scene`.
- `scene.type`: `wiretap`, `tail`, `interrogation`, `chart`, `forgery`, `torn` or `scan`. Each scene also names a `place` and a `surface` (`desk`, `cork`, `steel`, `stone`).
- `interrogation`: `statements` checked against `doc` (each with `verdict` T/F/NG, `proof` line ids and a `harder` paraphrase), and `cardStatements` that only an evidence card can break (`card` is the id of the right one).
- `board.deductions[]`: `cards` (two evidence ids), `title`, `text`, Sam's line, and `strong: true` if it counts toward a conviction.
- `evidence[]`: the cards, each with `id`, `title`, `text`.

Dialogue lines are strings. A plain string is Sam; `"@victor ..."` is spoken by the cast member `victor`; `*stars*` mark emphasis. Story beats can also be `{ "doc": ... }`, `{ "fact": ... }`, `{ "evidence": "id" }`, `{ "word": ... }` or `{ "lose": 10 }`.

## Building the Web export

With Godot 4.6.1 and its export templates installed:

```
cd godot
godot --headless --export-release Web ../index.html
```

The preset has thread support switched off, because GitHub Pages cannot send the headers a threaded build needs. If you edit `web/head_include.html`, paste its contents into the "Head Include" field of the Web preset (or into `html/head_include` in `export_presets.cfg`) before exporting.

## Building the WeChat Mini Game package

The Godot Mini Game export plugin is installed and enabled. Export from its **Mini Game Export** dock (platform WeChat, App ID `wxd74107578cbd5867`, portrait, preset `Web`, output `minigame/wechat`), or without the editor:

```
cd godot
godot --headless --path . --script ../tools/export_wechat.gd
```

The plugin's engine matches Godot 4.6.1 exactly; with any other editor version the export stops at its preflight check. Open `minigame/wechat` in WeChat DevTools.
