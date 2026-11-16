# Case Files

An IELTS practice game disguised as detective work. You are a trainee in Unit 9, a London police unit that solves cases where the evidence is language: forged letters, lying witnesses, torn notes. Your partner, Sam, briefs each case, reacts to what you find, and gives hints.

The IELTS task is the game action. Answers do jobs in the story, a wrong answer changes what happens next, and where the exam checks comprehension you prove your answer by tapping the line that shows it.

**Case 01: The Missing Violinist** (about 12 minutes, written for a band 6.5 target)

| Scene | IELTS skill | What you do |
| --- | --- | --- |
| Briefing | | Sam sets up the case and the deadline |
| Wiretap | Listening Part 1 | Hear a voicemail once and type the time, address and names |
| Tail | Listening Part 2 | Follow spoken directions and tap the building on a map |
| Interrogation | Reading, True / False / Not Given | Check six statements against a schedule; tap the line that proves each one |
| Evidence board | Writing Task 1 skills | Find the sentence that misreads a chart, then choose the accurate rewrite |
| Forgery lab | Grammar | Find three mistakes in a letter and choose each correction |
| Torn note | Linking words | Rebuild a note by choosing the linkers that make its logic work |
| Accusation | | Name one suspect and the three cards that prove it (three endings) |
| Case report | | Estimated bands, plus a result code to compare with a friend |

## Play

It is a static site: no server, no build step.

- **On your computer:** open `index.html` in a browser.
- **On GitHub Pages:** in the repository go to Settings → Pages, choose "Deploy from a branch", pick the branch and the `/ (root)` folder, and save. The game is then at `https://<user>.github.io/<repo>/`.

Calls and radio messages use the browser's built-in text-to-speech with a British voice, so turn the sound on. If a device has no speech voice, the game shows the transcript to read once instead. Progress and the word bank are saved in the browser (`localStorage`).

## How it works

- **Case clock.** It shows when the case is on course to close (6:30 pm with no mistakes; curtain is 7:30 pm). It moves only when the player makes a mistake (5 minutes), loses a lead (10) or takes a hint (10). Reading slowly costs nothing.
- **Cold leads.** Wrong wiretap notes send a constable to the wrong place, and the facts must be won again from a faster phone call. A wrong building on the map means a second, differently worded radio message. A misjudged statement comes back as a harder paraphrase; if Sam has to settle a lie, the suspect does not crack and a warrant costs more time.
- **Hints.** Three per case. Sam points to the right paragraph (or replays the right part of the tape), never the answer.
- **Notebook.** Case notes and evidence cards, plus a word bank that saves every paraphrase, linker, grammar trap and chart phrase the player meets. The word bank persists across cases.
- **Bands.** Estimated from the share of answers that were right first time. It is a rough guide from one short case, not an official score.
- **Result code.** For example `MV01-BVJYAV`. It packs the ending, three bands, hints used and minutes lost; paste a friend's code into the report to compare.

## Project layout

```
index.html                  page shell; lists the case files to load
css/style.css               the desk, paper, ink and red
js/engine.js                clock, dialogue, hints, notebook, speech, saving, scoring, runner
js/scenes.js                scene types and document renderers
cases/missing-violinist.js  Case 01, as data
```

## Adding a case

A case is one data file. Copy `cases/missing-violinist.js`, change the content, and add a `<script>` tag for it in `index.html` after the existing case. No engine changes are needed while you use the existing scene types.

```js
CaseFiles.registerCase({
  id: 'my-case', code: 'XY', number: '02', title: '…', tagline: '…', minutes: 12,
  skills: ['Listening', 'Reading', 'Writing'],
  clock: { start: '18:30', deadline: '19:30', comfortable: '19:00', deadlineName: 'curtain' },
  hints: 3, hintCost: 10, mistakeCost: 5,
  cast: { sam: { name: 'Sam', role: '…', initials: 'S', tone: 'ink' }, /* … */ },
  scenes: [ /* in play order */ ],
  evidence: [ /* cards for the accusation; proves: true on the three that convict */ ]
});
```

Scene types (`type` on each scene):

| Type | Needs |
| --- | --- |
| `story` | `beats` |
| `wiretap` | `form.fields` (each with `accept` answers and the script `lines` a hint replays), `script`, `retry` (the harder call) |
| `tail` | `map` (roads, labels, blocks, marks), `script`, `answer`, `retry` |
| `interrogation` | `doc.sections[].lines`, `statements` (each with `verdict` T/F/NG, `proof` line ids, a `harder` paraphrase, `hint`, `word`), `need`, `crack`, `noCrack` |
| `chart` | `chart.bars`, `sentences` (one with `false: true`), `rewrite.options` |
| `forgery` | `letter.paragraphs` (sentences; the wrong ones carry `error` with `bad`, `good`, `options`, `word`) |
| `torn` | `pieces` (each with `before`, `after`, `options`, `answer`, `why`, `hint`, `word`) |
| `accusation` | `suspects`, `culprit`, `endings` |
| `report` | `skills`, `endingNames` |

Most scenes also take `intro` and `outro` beats. A beat is one of:

- a string: a line of dialogue. Plain strings are Sam; `"@victor …"` is spoken by cast member `victor`; `*stars*` mark emphasis.
- `{ doc: { kind: 'sheet' | 'receipt' | 'newspaper', … }, button: '…' }`: a document to read.
- `{ fact: { title, text } }`: a case note for the notebook.
- `{ evidence: 'card-id' }`: hands the player an evidence card.
- `{ word: { t, a, b, n } }`: a word bank entry (`t` is `paraphrase`, `trap`, `chart`, `grammar` or `linker`).
- `{ lose: 10 }`: minutes lost on the case clock.

To add a new kind of task, register it in `js/scenes.js` with `CaseFiles.registerScene('my-type', async (scene, ctx) => { … })`. The `ctx` object gives a scene the stage and tray, `say`, `play`, `lose`, `mark`, `word`, `fact`, `evidence`, `setHint`, `stamp` and `speech`.
