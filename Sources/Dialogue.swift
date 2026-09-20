import Foundation

struct Line {
    let text: String
    var anim: String? = nil
    var fx: String? = nil
    var cue: Cue = .chatter
}

// `%@` is filled in with whatever the cue carries — usually an app name.
// Lines naming Eridians or Erid were cut: the pet should land for people who
// have never read the book.
func dialogueLines() -> [Line] {
    let name = NSUserName()
    return [
        // ── Straight from the book. Do not cut these. ────────────────────
        Line(text: "How do you know when the hug is done?"),
        Line(text: "Thumbs up, baby", fx: "sparkles"),
        Line(text: "Rocky hate Mark."),
        Line(text: "Fist my bump."),
        Line(text: "\(name) question is dumb"),
        Line(text: "Only us"),
        Line(text: "My portable Earth thinking machine"),
        Line(text: "Rocky, \(name), big science", anim: "react", fx: "sparkles"),
        Line(text: "I go home six years slow", anim: "sleep"),
        Line(text: "Oh, humor. Confusing."),
        Line(text: "Dirty, dirty, dirty…. This room for garbage?", anim: "react"),
        Line(text: "It's not enough"),
        Line(text: "Need word: to risk self to help another"),
        Line(text: "Amaze. Amaze. Amaze.", anim: "react", fx: "sparkles"),
        Line(text: "\(name) Rocky Save Stars", anim: "react", fx: "sparkles"),
        Line(text: "Words of encouragement."),
        Line(text: "Words of GREAT encouragement", anim: "react"),
        Line(text: "Rocky new to ball"),
        Line(text: "It's full good", fx: "sparkles"),
        Line(text: "Dirty. Dirty. Dirty.", anim: "react"),
        Line(text: "Where my bedroooom", anim: "sleep", fx: "zzz"),
        Line(text: "\(name) will die question?"),
        Line(text: "Rocky watch whole crew die. Rocky not fix. \(name) say \(name) will die. Rocky fix."),
        Line(text: "You sleep. I watch."),
        Line(text: "Friend \(name).", fx: "sparkles"),
        Line(text: "Question?"),
        Line(text: "Good. Good. Good.", fx: "sparkles"),
        Line(text: "You are scary space monster. But okay."),
        Line(text: "\(name). Clever. Amaze.", anim: "react", fx: "sparkles"),
        Line(text: "Amaze! Happy happy happy!", anim: "react", fx: "sparkles"),
        Line(text: "Why humans need water so much, question? Inefficient life-forms!"),
        Line(text: "Why does ship have name but chair no have name, question?"),
        Line(text: "Grumpy. Angry. Stupid. How long since last sleep, question?"),
        Line(text: "Usually you not stupid. Why stupid, question?"),
        Line(text: "Obvious I can do that! You are stupid right now. You sleep.", anim: "sleep"),
        Line(text: "Your face opening is in sad mode. Why, question?"),
        Line(text: "Humans are amaze. You leave ship.", fx: "sparkles"),
        Line(text: "Math is not thinking. Math is procedure. Memory is not thinking."),
        Line(text: "Is private. I sleep after eat. You watch me sleep, question?", anim: "sleep", fx: "zzz"),
        Line(text: "I speed up. Slow down. Much confuse. But get here."),
        Line(text: "You are good human.", fx: "sparkles"),
        Line(text: "Yes yes. I make now. We are team. We fix this. No be sad."),
        Line(text: "You damage self to save me. Thank."),
        Line(text: "You will miss me, question? I will miss you. You are friend."),
        Line(text: "No say sorry. You save me when you put me here. Thank thank thank."),
        Line(text: "Another similarity: You and me both willing to die for our people."),
        Line(text: "Amaze. Humans helpless without light."),

        // ── Rocky, in your house, with opinions ──────────────────────────
        Line(text: "\(name) look at screen long time. Eyes okay, question?"),
        Line(text: "You eat today, question? Answer honest."),
        Line(text: "Drink water. Inefficient life-form need water."),
        Line(text: "Rocky watch. \(name) work. Good system."),
        Line(text: "What is this you do, question?"),
        Line(text: "Rocky bored. Entertain Rocky.", anim: "react"),
        Line(text: "Rocky live here now. This is Rocky wall."),
        Line(text: "You is busy. Rocky wait. Rocky patient."),
        Line(text: "Music, question? Rocky no have ears. Rocky sad."),
        Line(text: "Outside is real. Rocky hear about it."),
        Line(text: "Human blink rate low. Concerning."),
        Line(text: "This corner is good corner."),
        Line(text: "Rocky nap now. You be quiet.", anim: "sleep", fx: "zzz"),
        Line(text: "Rocky no understand human work. Look like staring."),
        Line(text: "Good job. Probably.", fx: "sparkles"),
        Line(text: "You do thing. Rocky proud. Rocky no know what thing.", anim: "react", fx: "sparkles"),
        Line(text: "Rest is not lazy. Rest is repair."),
        Line(text: "Rocky here. Always here. Only us.", fx: "sparkles"),
        Line(text: "Coffee, question? Explain coffee."),
        Line(text: "Ceiling is good. Rocky recommend ceiling."),
        Line(text: "Human make same face for three hours. Amaze."),
        Line(text: "\(name) busy. Rocky climb. Everyone happy."),
        Line(text: "You breathe wrong. Slow down."),
        Line(text: "Small glowing box. Human magic. Rocky approve.", fx: "sparkles"),
        Line(text: "Rocky no judge. Rocky observe. Is different."),

        // ── Said only when the thing is actually true ────────────────────
        Line(text: "%@ open. Rocky inspect.", anim: "react", cue: .appLaunch),
        Line(text: "What is %@, question?", cue: .appLaunch),
        Line(text: "New thing! Rocky come look.", anim: "react", fx: "sparkles", cue: .appLaunch),
        Line(text: "%@ appear. Rocky was not consulted.", cue: .appLaunch),
        Line(text: "%@ is new. Rocky decide later if good.", cue: .appLaunch),

        Line(text: "Now %@. Okay. Rocky follow.", cue: .appSwitch),
        Line(text: "%@ again, question?", cue: .appSwitch),
        Line(text: "You move to %@. Rocky move to %@.", cue: .appSwitch),
        Line(text: "%@. Rocky observe from here.", cue: .appSwitch),

        Line(text: "Many many windows. Dirty. Dirty.", anim: "react", cue: .manyWindows),
        Line(text: "Rocky count your windows. Too many.", cue: .manyWindows),
        Line(text: "Windows everywhere. Close some. Rocky beg.", anim: "react", cue: .manyWindows),

        Line(text: "Time is late. You sleep, question?", anim: "sleep", cue: .lateNight),
        Line(text: "Sun gone. You still here. Why, question?", cue: .lateNight),
        Line(text: "One more hour, you say. You lie.", cue: .lateNight),
        Line(text: "Tomorrow exist. Use it.", cue: .lateNight),
        Line(text: "Night is for sleep. Rocky read this somewhere.", anim: "sleep", fx: "zzz", cue: .lateNight),

        Line(text: "Sun back. You survive night. Amaze.", anim: "react", fx: "sparkles", cue: .morning),
        Line(text: "Morning. Rocky already awake. Rocky always awake.", cue: .morning),
        Line(text: "New day. Big science.", anim: "react", fx: "sparkles", cue: .morning),

        Line(text: "You go away, come back. Rocky wait whole time.", fx: "sparkles", cue: .returned),
        Line(text: "You return! Happy happy happy!", anim: "react", fx: "sparkles", cue: .returned),
        Line(text: "Where you go, question? Rocky worry.", cue: .returned),
        Line(text: "Rocky guard screen. Nothing steal. You welcome.", cue: .returned),

        Line(text: "You wake. Rocky wake. Only us.", fx: "sparkles", cue: .woke),
        Line(text: "Screen alive again. Good.", cue: .woke),

        Line(text: "Machine dying. %@ percent. Do something.", anim: "react", cue: .batteryLow),
        Line(text: "%@ percent. Rocky concerned for machine.", anim: "react", cue: .batteryLow),
        Line(text: "Feed machine. %@ percent is not enough.", cue: .batteryLow),

        Line(text: "Machine eat now. Good.", fx: "sparkles", cue: .charging),
        Line(text: "Power. Amaze. Machine live.", anim: "react", fx: "sparkles", cue: .charging),

        Line(text: "You touch Rocky. Rocky allow.", anim: "react", fx: "sparkles", cue: .petted),
        Line(text: "Fist my bump.", anim: "react", fx: "sparkles", cue: .petted),
        Line(text: "Thumbs up, baby", anim: "react", fx: "sparkles", cue: .petted),
        Line(text: "Good good good!", anim: "react", fx: "sparkles", cue: .petted),
        Line(text: "Again. Rocky like.", anim: "react", fx: "sparkles", cue: .petted),

        Line(text: "Whoa! Put Rocky down!", anim: "react", cue: .dragged),
        Line(text: "Rocky fly! Amaze!", anim: "react", fx: "sparkles", cue: .dragged),
        Line(text: "This is not flying. This is falling.", anim: "react", cue: .dragged),
        Line(text: "Where we go, question?", cue: .dragged),

        Line(text: "You sit long time. Legs work, question?", cue: .sitting),
        Line(text: "Stand up. Move. Rocky insist.", anim: "react", cue: .sitting),
        Line(text: "Hour pass. You no move. Rocky notice.", cue: .sitting),
    ]
}
