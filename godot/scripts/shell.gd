class_name Shell
## The interface language. The WeChat build carries the "zh_shell" feature tag
## (set on the MiniGame export preset) and shows its interface chrome in
## Simplified Chinese; the Web build keeps English.
##
## Only chrome goes through here: buttons, prompts, labels, toasts, the notebook
## and the report. Teaching content (dialogue, statements, documents, listening
## scripts and audio, answers and grading) never does, and stays English.
## Lookups are exact: a string without an entry is shown as it is.

const TITLE := "词探事务所"

static var active := false


static func init() -> void:
	active = OS.has_feature("zh_shell")


## The interface text for an English chrome string.
static func t(s: String) -> String:
	if active and ZH.has(s):
		return ZH[s]
	return s


## A clock time for the interface: "5:40 pm" in English, "下午 5:40" in Chinese.
static func clock(hr: int, m: int) -> String:
	if active:
		return "%s %d:%02d" % ["下午" if hr >= 12 else "上午", (hr + 11) % 12 + 1, m]
	return "%d:%02d %s" % [(hr + 11) % 12 + 1, m, "pm" if hr >= 12 else "am"]


const ZH := {
	# notebook: word bank groups
	"Paraphrases": "同义改写",
	"What was said, and what the document says": "说法与文件原文的对应",
	"Not Given traps": "Not Given 陷阱",
	"Mentioned nearby, but never actually stated": "附近提到过，但从未真正说明",
	"Chart language": "图表用语",
	"For describing data": "用于描述数据",
	"Grammar traps": "语法陷阱",
	"Wrong, then right": "先错误写法，再正确写法",
	"Linking words": "连接词",
	"The word and the job it does": "连接词及其作用",
	# HUD, hints and toasts
	"Leads and mistakes both cost time. Curtain is at %s.": "跟进线索和犯错都会耗费时间。开幕时间：%s。",
	"Ask Sam": "问 Sam",
	"Ask Sam (%d)": "问 Sam（%d）",
	"Notes": "笔记",
	"Continue": "继续",
	"tap": "点击",
	"curtain": "开幕",
	"%d minutes spent": "用时 %d 分钟",
	"Past %s time!": "已过%s时间！",
	"+%d min on the case clock": "案件时钟 +%d 分钟",
	"Saved to notebook: ": "已存入笔记本：",
	"New evidence card: ": "新证据卡：",
	"Nothing to ask Sam about right now.": "现在没有可以问 Sam 的事。",
	"Ask Sam?": "要问 Sam 吗？",
	"Sam will show you where to look, not what the answer is. It costs %d minutes on the case clock. %d of %d hints left.":
		"Sam 会告诉你该看哪里，但不会告诉你答案。每次提示会让案件时钟增加 %d 分钟。剩余提示：%d / %d。",
	"Not yet": "先不用",
	"Put the cards away": "收起证据卡",
	# notebook
	"Board": "证据板",
	"Words": "词汇",
	"Close": "关闭",
	"Notebook": "笔记本",
	"Nothing here yet. Every paraphrase, linking word and grammar trap you meet in a case is saved here automatically.":
		"这里还是空的。你在案件中遇到的每个同义改写、连接词和语法陷阱都会自动保存在这里。",
	"The board is empty. Evidence is pinned here as you find it.": "证据板还是空的。找到的证据会钉在这里。",
	"No notes yet. Facts appear here as you find them.": "还没有笔记。发现的事实会记录在这里。",
	"Leave case (progress is saved)": "离开案件（进度已保存）",
	# home
	"Detective work where the evidence is English. Every answer you give does a job in the case.":
		"以英语为证据的侦探游戏。你的每一个答案都会推动案情。",
	"Continue the case": "继续办案",
	"Open the case": "开始办案",
	"Case ": "案件 ",
	"About %d minutes. %s.": "约 %d 分钟。%s。",
	"Start again from the beginning": "从头开始",
	"Sound check": "声音测试",
	"My word bank": "我的词汇本",
	"Sound effects: ": "音效：",
	"Screen shake: ": "屏幕震动：",
	"on": "开",
	"off": "关",
	"Calls and radio messages are spoken aloud. Turn your sound on, or use headphones.":
		"电话和无线电内容会播放语音。请打开声音，或戴上耳机。",
	"Playing a test message…": "正在播放测试语音…",
	"If you heard a voice, you’re ready.": "听到声音了，就可以开始了。",
	"No voice found on this device. Calls will be shown as text instead.": "此设备没有可用的语音，通话内容将以文字显示。",
	"Listening": "听力",
	"Reading": "阅读",
	"Writing": "写作",
	# skill tags on leads and scene covers
	"Unit 9, Language Crimes": "第九组 · 语言罪案",
	"Choose what to follow": "选择要跟进的线索",
	"Listening · Part 1": "听力 · 第一部分",
	"Listening · Part 2": "听力 · 第二部分",
	"Reading · True / False / Not Given": "阅读 · 判断题（正确 / 错误 / 未提及）",
	"Writing · Task 1 skills": "写作 · 小作文技巧",
	"Writing · Grammar": "写作 · 语法",
	"Writing · Linking words": "写作 · 连接词",
	"Reading · Finding information": "阅读 · 信息定位",
	"Two cards, one conclusion": "两张卡片，一个结论",
	"One name. Three proofs.": "一个名字，三项证据。",
	# scene title cards
	"Briefing": "案情简报",
	"The Leads": "线索",
	"The Evidence Board": "证据板",
	"The Accusation": "指控",
	# the lead board: lead titles and their one-line descriptions
	"The Wiretap": "窃听",
	"The Tail": "跟踪",
	"The Interrogation": "审讯",
	"The Sales Report": "销售报告",
	"The Forgery Lab": "伪造鉴定室",
	"The Torn Note": "撕碎的纸条",
	"The Front Desk": "前台",
	"The Green Room": "演员休息室",
	"A new voicemail on Victor Hale’s office phone.": "Victor Hale 的办公室电话里有一条新的语音留言。",
	"Victor has left the hall. Follow him.": "Victor 离开了音乐厅。跟上他。",
	"Sit Victor down with the hall’s schedule.": "拿着音乐厅的日程表，让 Victor 坐下来谈谈。",
	"A report Victor wrote for the hall this afternoon.": "Victor 今天下午为音乐厅写的一份报告。",
	"The letter from her dressing table is back from the lab.": "她化妆台上的那封信，鉴定结果出来了。",
	"A cleaner found torn paper by the stage door.": "清洁工在后台门边发现了撕碎的纸条。",
	"Beatrice Lang keeps a log of everyone who comes and goes.": "Beatrice Lang 记录着每一个进出的人。",
	"Dominic Pryce is waiting to be asked.": "Dominic Pryce 在等你问话。",
	"%d min": "%d 分钟",
	"Locked": "未解锁",
	"Optional": "可选",
	"Done": "已完成",
	"Opens after the voicemail.": "听完语音留言后解锁。",
	"Opens after the interview.": "审讯结束后解锁。",
	"%s left before the curtain. The leads still open would take %d minutes.": "距开幕还有 %s。剩下的线索共需 %d 分钟。",
	"%d minutes": "%d 分钟",
	"No time left before the curtain. The leads still open would take %d minutes.": "已经到开幕时间。剩下的线索共需 %d 分钟。",
	"Take what we have to the evidence board": "带着现有线索去证据板",
	"Build the case?": "开始整理案情？",
	"Stop following leads and build the case? You can’t come back for the ones you skipped.":
		"停止跟进线索，开始整理案情？跳过的线索之后无法再回来。",
	"Build the case": "整理案情",
	"Keep investigating": "继续调查",
	# tape recorder and radio
	"Deduction": "推论",
	"Leave this sentence": "放过这一句",
	"Plays once only": "只播放一次",
	"Play": "播放",
	"Playing…": "播放中…",
	"Played": "已播放",
	"Tape finished": "录音已播完",
	"No voice on this device": "此设备没有语音",
	"This device has no speech voice, so here is the transcript instead. Read it once, then put it away.":
		"此设备没有语音，以下是录音原文。读一遍，然后收起。",
	"I’ve read it. Put it away": "读完了，收起",
	"Voicemail": "语音留言",
	"Phone call": "电话",
	"Police radio": "警用无线电",
	"Hand notes to Sam": "把笔记交给 Sam",
	"Play the tape first. Sam can’t wind back what you haven’t heard.": "请先播放录音。还没听过的内容，Sam 没法倒回去。",
	"Tap a building on the map": "在地图上点选一栋建筑",
	"Send the team to building %s": "派小队去 %s 号建筑",
	"Play the radio first. Then Sam can help.": "请先播放无线电，Sam 才能帮忙。",
	"Back to the hall": "回到音乐厅",
	"Tap the corners to walk the marker along his route.": "点按路口，让标记沿他的路线移动。",
	# interrogation
	"His composure": "他的镇定",
	"Your credibility": "你的可信度",
	"His composure: ": "他的镇定：",
	"steady": "稳定",
	"shaken": "动摇",
	"sweating": "冒汗",
	"cracking": "濒临崩溃",
	"gone": "崩溃",
	"First decide: True, Lie or Not Given.": "先选择：属实、说谎或未提及。",
	"TRUE": "属实",
	"LIE": "说谎",
	"NOT GIVEN": "未提及",
	"Credibility lost": "可信度下降",
	"Present an evidence card": "出示证据卡",
	"Let it pass": "先放过",
	"Tap the line that proves he’s lying.": "点按能证明他在说谎的那一行。",
	"Tap the line that proves it’s true.": "点按能证明属实的那一行。",
	"Back": "返回",
	"Which card do you put on the table?": "你要出示哪张证据卡？",
	"statement %d of %d%s": "第 %d / %d 条陈述%s",
	", again": "（再说一遍）",
	"and another thing": "还有一件事",
	# chart, forgery, torn note, logs
	"Tap the sentence that gets the chart wrong.": "点按与图表不符的那一句。",
	"Choose the sentence that matches the chart": "选出与图表相符的句子",
	"Tap a sentence Mira would never write.\nMistakes found: %d of %d": "点按 Mira 绝不会写出的句子。\n已发现错误：%d / %d",
	"What would Mira have written?": "Mira 会怎么写？",
	"Which word mends this piece?": "哪个词能补全这一片？",
	"Tap the line that answers Sam’s question.": "点按能回答 Sam 问题的那一行。",
	"Sam asks   %d of %d": "Sam 的问题   %d / %d",
	# evidence board
	"Tap two cards to connect them": "点选两张卡片，把它们连起来",
	"DEDUCTIONS MADE: %d": "已得出推论：%d",
	"Connect these two cards": "连接这两张卡片",
	"Two cards at a time. Tap one to put it back.": "一次只能选两张。点一张放回去。",
	"Make the accusation": "提出指控",
	"Make the accusation?": "要提出指控吗？",
	"You have made %d deductions. You can’t come back to the board.": "你已得出 %d 条推论。之后无法再回到证据板。",
	"Accuse": "指控",
	"Keep working": "继续推理",
	# accusation
	"Choose a suspect": "选择嫌疑人",
	"Choose %d more": "还需选择 %d 项",
	"Arrest %s": "逮捕 %s",
	"Three proofs only. Tap one to put it back.": "只能选三项证据。点一项放回去。",
	"Who did it?": "谁是凶手？",
	"Which three prove it?": "哪三项能证明？",
	"Choose three. Deductions from the board are the strong ones.": "选择三项。证据板上得出的推论最有力。",
	"Put the paper down": "放下报纸",
	"See the case report": "查看结案报告",
	# case report
	"Unit 9, Case ": "第九组 · 案件 ",
	"Case Report": "结案报告",
	"Case closed at": "结案时间",
	"Leads followed": "已跟进线索",
	"%d of %d": "%d / %d",
	"Deductions": "推论",
	"Hints used": "使用提示",
	"Estimated band": "预估分数",
	"%d of %d right first time, from %s": "首次答对 %d / %d，来自%s",
	"the wiretap and the tail": "窃听与跟踪",
	"the interview and the logs": "审讯与记录",
	"the chart report, the forged letter and the torn note": "图表报告、伪造信件与撕碎的纸条",
	"Not tested: you skipped these leads": "未测试：你跳过了这些线索",
	"A rough guide from one short case, not an official score. To work on next: %s.": "仅根据一个短案件粗略估算，并非官方分数。下一步重点练习：%s。",
	"Result code": "结果代码",
	"Copy": "复制",
	"Copied": "已复制",
	"Send it to someone who played this case. Type theirs here to compare.": "把它发给玩过这个案件的朋友，在这里输入对方的代码来比较。",
	"Friend’s result code": "朋友的结果代码",
	"Compare": "比较",
	"Closed at ": "结案 ",
	"%d hints": "提示 %d 次",
	"L %s  R %s  W %s": "听力 %s  阅读 %s  写作 %s",
	"That doesn’t look like a result code. Check for a missing letter.": "这不像有效的结果代码，请检查是否漏了字母。",
	"That code is from a different case.": "这个代码来自另一个案件。",
	"You": "你",
	"Them": "对方",
	"Play the case again": "重玩本案",
	"Conviction": "定罪",
	"Walked free": "无罪释放",
	"Case reopened": "案件重开",
}
