import Foundation

struct EnglishContentRepository {
    static let shared = EnglishContentRepository()

    let words: [EnglishLearningItem]
    let sentences: [EnglishLearningItem]
    let passages: [EnglishLearningItem]
    let quotes: [EnglishLearningItem]

    init(
        words: [EnglishLearningItem] = EnglishVocabulary.daily,
        sentences: [EnglishLearningItem] = Self.bundledSentences,
        passages: [EnglishLearningItem] = Self.bundledPassages,
        quotes: [EnglishLearningItem] = Self.bundledQuotes
    ) {
        self.words = words
        self.sentences = sentences
        self.passages = passages
        self.quotes = quotes
    }

    /// 全部内容的并集（含所有学段的单词）。
    var allItems: [EnglishLearningItem] { EnglishVocabulary.all + sentences + passages + quotes }

    func items(for category: EnglishLearningCategory) -> [EnglishLearningItem] {
        items(for: category, difficulty: nil)
    }

    /// 旧 API：单词类别默认使用初始化时的 words 集合（.daily 学段）。
    func items(
        for category: EnglishLearningCategory,
        difficulty: EnglishDifficulty?
    ) -> [EnglishLearningItem] {
        let source: [EnglishLearningItem]
        switch category {
        case .words: source = words
        case .sentences: source = sentences
        case .passages: source = passages
        case .daily: source = quotes
        }
        guard let difficulty else { return source }
        return source.filter { $0.difficulty == difficulty }
    }

    /// 新 API：按学段返回单词；非单词类别不受 stage 影响。
    func items(for category: EnglishLearningCategory, stage: EnglishStage) -> [EnglishLearningItem] {
        switch category {
        case .words: return EnglishVocabulary.words(for: stage)
        case .sentences: return sentences
        case .passages: return passages
        case .daily: return quotes
        }
    }

    func dailyQuote(on date: Date = Date(), calendar: Calendar = .current) -> EnglishLearningItem {
        stableItem(from: quotes, on: date, calendar: calendar)
    }

    /// 旧签名：使用默认 words 集合。
    func dailyWord(on date: Date = Date(), calendar: Calendar = .current) -> EnglishLearningItem {
        stableItem(from: words, on: date, calendar: calendar)
    }

    /// 新 API：指定学段的当日单词。
    func dailyWord(stage: EnglishStage, on date: Date = Date(), calendar: Calendar = .current) -> EnglishLearningItem {
        stableItem(from: EnglishVocabulary.words(for: stage), on: date, calendar: calendar)
    }

    func stableIndex(count: Int, on date: Date = Date(), calendar: Calendar = .current) -> Int {
        guard count > 0 else { return 0 }
        let day = calendar.ordinality(of: .day, in: .era, for: date) ?? 0
        return abs(day) % count
    }

    /// 旧 API：单词类别默认使用初始化时的 words 集合。
    func orderedItems(
        for category: EnglishLearningCategory,
        progress: [String: EnglishItemProgress],
        on date: Date = Date(),
        calendar: Calendar = .current
    ) -> [EnglishLearningItem] {
        buildOrderedItems(source: items(for: category), progress: progress, on: date, calendar: calendar)
    }

    /// 新 API：按指定学段构建每日队列。
    func orderedItems(
        for category: EnglishLearningCategory,
        stage: EnglishStage,
        progress: [String: EnglishItemProgress],
        on date: Date = Date(),
        calendar: Calendar = .current
    ) -> [EnglishLearningItem] {
        buildOrderedItems(source: items(for: category, stage: stage), progress: progress, on: date, calendar: calendar)
    }

    private func buildOrderedItems(
        source: [EnglishLearningItem],
        progress: [String: EnglishItemProgress],
        on date: Date,
        calendar: Calendar
    ) -> [EnglishLearningItem] {
        guard !source.isEmpty else { return [] }
        let start = stableIndex(count: source.count, on: date, calendar: calendar)
        let rotated = Array(source[start...] + source[..<start])
        return rotated.sorted { lhs, rhs in
            let left = progress[lhs.id]
            let right = progress[rhs.id]
            let leftDue = left?.nextReviewAt.map { $0 <= date } ?? true
            let rightDue = right?.nextReviewAt.map { $0 <= date } ?? true
            if leftDue != rightDue { return leftDue && !rightDue }
            let leftMastery = left?.mastery ?? .new
            let rightMastery = right?.mastery ?? .new
            return leftMastery < rightMastery
        }
    }

    private func stableItem(
        from items: [EnglishLearningItem],
        on date: Date,
        calendar: Calendar
    ) -> EnglishLearningItem {
        precondition(!items.isEmpty, "Bundled English content must not be empty")
        return items[stableIndex(count: items.count, on: date, calendar: calendar)]
    }
}

private extension EnglishContentRepository {
    static func sentence(_ id: String, _ title: String, _ translation: String) -> EnglishLearningItem {
        EnglishLearningItem(id: "sentence.\(id)", category: .sentences, title: title, translation: translation)
    }

    static func passage(_ id: String, _ title: String, _ sentences: [String], _ translation: String) -> EnglishLearningItem {
        EnglishLearningItem(
            id: "passage.\(id)", category: .passages, title: title,
            translation: translation, passageSentences: sentences
        )
    }

    static func quote(_ id: String, _ title: String, _ translation: String, _ source: String) -> EnglishLearningItem {
        EnglishLearningItem(
            id: "quote.\(id)", category: .daily, title: title,
            translation: translation, source: source
        )
    }

    static let bundledSentences: [EnglishLearningItem] = [
        sentence("nice-to-meet-you", "Nice to meet you.", "很高兴认识你。"),
        sentence("how-are-you", "How are you today?", "你今天好吗？"),
        sentence("im-fine", "I am fine, thank you.", "我很好，谢谢你。"),
        sentence("whats-your-name", "What is your name?", "你叫什么名字？"),
        sentence("where-are-you-from", "Where are you from?", "你来自哪里？"),
        sentence("dont-understand", "I do not understand.", "我不明白。"),
        sentence("say-again", "Could you say that again?", "你可以再说一遍吗？"),
        sentence("speak-slowly", "Please speak a little more slowly.", "请说得再慢一点。"),
        sentence("how-much", "How much is this?", "这个多少钱？"),
        sentence("where-station", "Where is the train station?", "火车站在哪里？"),
        sentence("like-coffee", "I would like a cup of coffee.", "我想要一杯咖啡。"),
        sentence("need-help", "Excuse me, I need some help.", "打扰一下，我需要一些帮助。"),
        sentence("good-day", "Have a nice day!", "祝你今天愉快！"),
        sentence("see-tomorrow", "See you tomorrow.", "明天见。"),
        sentence("learning-english", "I am learning English every day.", "我每天都在学习英语。"),
        sentence("take-your-time", "Take your time. There is no hurry.", "慢慢来，不着急。"),
        sentence("good-morning", "Good morning.", "早上好。"),
        sentence("good-afternoon", "Good afternoon.", "下午好。"),
        sentence("good-evening", "Good evening.", "晚上好。"),
        sentence("good-night", "Good night.", "晚安。"),
        sentence("my-name-is", "My name is Tom.", "我的名字叫汤姆。"),
        sentence("i-am-seven", "I am seven years old.", "我七岁了。"),
        sentence("i-am-from-china", "I am from China.", "我来自中国。"),
        sentence("this-is-my-mother", "This is my mother.", "这是我的妈妈。"),
        sentence("he-is-my-father", "He is my father.", "他是我的爸爸。"),
        sentence("she-is-my-sister", "She is my sister.", "她是我的姐姐。"),
        sentence("we-are-friends", "We are good friends.", "我们是好朋友。"),
        sentence("it-is-a-book", "It is a book.", "它是一本书。"),
        sentence("this-is-my-pencil", "This is my pencil.", "这是我的铅笔。"),
        sentence("that-is-your-bag", "That is your bag.", "那是你的书包。"),
        sentence("these-are-apples", "These are apples.", "这些是苹果。"),
        sentence("those-are-books", "Those are books.", "那些是书。"),
        sentence("what-is-this", "What is this?", "这是什么？"),
        sentence("it-is-an-egg", "It is an egg.", "它是一个鸡蛋。"),
        sentence("what-color", "What color is it?", "它是什么颜色？"),
        sentence("it-is-red", "It is red.", "它是红色的。"),
        sentence("how-many-books", "How many books do you have?", "你有多少本书？"),
        sentence("i-have-three-books", "I have three books.", "我有三本书。"),
        sentence("how-old-are-you", "How old are you?", "你几岁了？"),
        sentence("who-is-she", "Who is she?", "她是谁？"),
        sentence("where-is-my-pen", "Where is my pen?", "我的钢笔在哪里？"),
        sentence("on-the-desk", "It is on the desk.", "它在书桌上。"),
        sentence("under-the-chair", "It is under the chair.", "它在椅子下面。"),
        sentence("in-my-bag", "It is in my bag.", "它在我的书包里。"),
        sentence("open-your-book", "Open your book, please.", "请打开你的书。"),
        sentence("close-the-door", "Close the door, please.", "请关门。"),
        sentence("look-at-me", "Look at me, please.", "请看着我。"),
        sentence("listen-and-repeat", "Listen and repeat.", "听并跟读。"),
        sentence("read-after-me", "Read after me.", "跟我读。"),
        sentence("write-your-name", "Write your name, please.", "请写下你的名字。"),
        sentence("spell-this-word", "Can you spell this word?", "你会拼这个单词吗？"),
        sentence("i-can-read", "I can read English.", "我会读英语。"),
        sentence("i-can-sing", "I can sing a song.", "我会唱一首歌。"),
        sentence("i-like-milk", "I like milk.", "我喜欢牛奶。"),
        sentence("i-like-bananas", "I like bananas.", "我喜欢香蕉。"),
        sentence("i-dont-like-coffee", "I do not like coffee.", "我不喜欢咖啡。"),
        sentence("may-i-have-water", "May I have some water?", "我可以喝点水吗？"),
        sentence("here-you-are", "Here you are.", "给你。"),
        sentence("you-are-welcome", "You are welcome.", "不客气。"),
        sentence("its-sunny", "It is sunny today.", "今天晴朗。"),
        sentence("its-raining", "It is raining now.", "现在正在下雨。"),
        sentence("i-feel-cold", "I feel cold.", "我觉得冷。"),
        sentence("put-on-coat", "Put on your coat.", "穿上你的外套。"),
        sentence("lets-play", "Let us play together.", "让我们一起玩吧。"),
        sentence("come-here", "Come here, please.", "请到这里来。"),
        sentence("go-to-school", "I go to school by bus.", "我坐公交车去学校。"),
        sentence("time-for-lunch", "It is time for lunch.", "到午饭时间了。"),
        sentence("see-you-soon", "See you soon.", "一会儿见。"),
        sentence("happy-birthday", "Happy birthday!", "生日快乐！"),
        sentence("dont-worry-starter", "Do not worry.", "不要担心。"),
        sentence("try-again", "Try again, please.", "请再试一次。"),
        sentence("can-you-help", "Could you help me, please?", "你能帮帮我吗？"),
        sentence("where-toilet", "Where is the restroom?", "洗手间在哪里？"),
        sentence("how-to-get", "How can I get to the airport?", "我怎么去机场？"),
        sentence("check-the-bill", "Could I have the bill, please?", "请给我账单，好吗？"),
        sentence("table-for-two", "A table for two, please.", "请给我们一张两人桌。"),
        sentence("just-looking", "I am just looking, thank you.", "我只是随便看看，谢谢。"),
        sentence("whats-the-time", "What time does it open?", "它几点开门？"),
        sentence("i-agree", "I agree with you.", "我同意你的看法。"),
        sentence("in-my-opinion", "In my opinion, it is a good idea.", "在我看来，这是个好主意。"),
        sentence("let-me-think", "Let me think about it.", "让我考虑一下。"),
        sentence("no-problem", "No problem at all.", "完全没问题。"),
        sentence("congratulations", "Congratulations on your success!", "恭喜你成功！"),
        sentence("take-care", "Take care of yourself.", "好好照顾自己。"),
        sentence("good-luck", "Good luck with your exam.", "祝你考试顺利。"),
        sentence("long-time-no-see", "Long time no see.", "好久不见。"),
        sentence("keep-in-touch", "Let us keep in touch.", "我们保持联系。"),
        sentence("im-not-sure", "I am not sure about that.", "我对那个不太确定。"),
        sentence("could-you-repeat", "Could you repeat that, please?", "你能重复一遍吗？")
    ]

    static let bundledPassages: [EnglishLearningItem] = [
        passage("my-morning", "My Morning", [
            "I get up at seven in the morning.",
            "I drink a glass of water.",
            "Then I eat breakfast and read for ten minutes.",
            "A good morning helps me have a good day."
        ], "我早上七点起床。我喝一杯水，然后吃早餐并阅读十分钟。一个好的早晨帮助我度过美好的一天。"),
        passage("my-friend", "My Friend", [
            "My friend is called Anna.",
            "She is kind and always smiles.",
            "We study English together after work.",
            "Learning with a friend is fun."
        ], "我的朋友叫安娜。她很善良，总是微笑。我们下班后一起学习英语。和朋友一起学习很有趣。"),
        passage("small-steps", "Small Steps", [
            "Learning English takes time.",
            "I learn five new words every day.",
            "I listen to each word and say it aloud.",
            "Small steps can make a big difference."
        ], "学习英语需要时间。我每天学习五个新单词。我听每个单词并大声说出来。小小的进步也能带来很大的改变。"),
        passage("at-cafe", "At the Cafe", [
            "I walk into a small cafe.",
            "I say hello and ask for a cup of coffee.",
            "The server smiles and says, here you are.",
            "I say thank you and enjoy my coffee."
        ], "我走进一家小咖啡馆。我打招呼并要了一杯咖啡。服务员微笑着说，给你。我说谢谢，然后享用咖啡。"),
        passage("rainy-day", "A Rainy Day", [
            "It is raining today.",
            "I take my umbrella and walk to the bus stop.",
            "The air is cool and the street is quiet.",
            "I listen to English on the bus."
        ], "今天下雨了。我带上雨伞走到公交站。空气凉爽，街道安静。我在公交车上听英语。"),
        passage("weekend-plan", "My Weekend Plan", [
            "This weekend I will stay at home.",
            "I want to cook a simple meal and clean my room.",
            "In the afternoon, I will call my family.",
            "At night, I will read a good book."
        ], "这个周末我会待在家里。我想做一顿简单的饭并打扫房间。下午我会给家人打电话，晚上读一本好书。"),
        passage("hello-class", "Hello, Class", [
            "Hello, class.",
            "My name is Lily.",
            "I am eight years old.",
            "I like English."
        ], "同学们好。我的名字叫莉莉。我八岁了。我喜欢英语。"),
        passage("my-schoolbag", "My Schoolbag", [
            "This is my schoolbag.",
            "It is blue and white.",
            "I have a book, a pencil and an eraser.",
            "I put my schoolbag on the desk."
        ], "这是我的书包。它是蓝白色的。我有一本书、一支铅笔和一块橡皮。我把书包放在书桌上。"),
        passage("my-family-starter", "My Family", [
            "This is my family.",
            "My father is tall.",
            "My mother is kind.",
            "We eat dinner together."
        ], "这是我的家人。我的爸爸很高。我的妈妈很亲切。我们一起吃晚饭。"),
        passage("at-school", "At School", [
            "I go to school in the morning.",
            "I say hello to my teacher.",
            "We read, write and sing in class.",
            "School is fun."
        ], "我早上去上学。我向老师问好。我们在课堂上读、写和唱歌。学校很有趣。"),
        passage("lunch-time", "Lunch Time", [
            "It is time for lunch.",
            "I have rice, chicken and soup.",
            "I drink some water.",
            "The food is nice."
        ], "到午饭时间了。我吃米饭、鸡肉和汤。我喝一些水。食物很好。"),
        passage("a-sunny-day", "A Sunny Day", [
            "It is sunny today.",
            "The sky is blue.",
            "I go to the park with my friend.",
            "We play with a ball."
        ], "今天晴朗。天空是蓝色的。我和朋友去公园。我们玩球。"),
        passage("my-room-starter", "My Room", [
            "This is my room.",
            "My bed is near the window.",
            "My books are on the table.",
            "I clean my room every day."
        ], "这是我的房间。我的床在窗户附近。我的书在桌子上。我每天打扫房间。"),
        passage("the-little-cat", "The Little Cat", [
            "I have a little cat.",
            "It is black and white.",
            "It likes milk.",
            "It sleeps under my chair."
        ], "我有一只小猫。它是黑白色的。它喜欢牛奶。它睡在我的椅子下面。"),
        passage("birthday-party", "A Birthday Party", [
            "Today is my birthday.",
            "My friends come to my house.",
            "We eat cake and sing a song.",
            "I am very happy."
        ], "今天是我的生日。我的朋友们来到我家。我们吃蛋糕并唱歌。我非常开心。"),
        passage("go-by-bus", "Go by Bus", [
            "I go to school by bus.",
            "The bus is big.",
            "I sit near the window.",
            "I can see trees and shops."
        ], "我坐公交车去上学。公交车很大。我坐在窗户附近。我能看见树和商店。"),
        passage("four-seasons", "Four Seasons", [
            "Spring is warm.",
            "Summer is hot.",
            "Autumn is cool.",
            "Winter is cold."
        ], "春天温暖。夏天炎热。秋天凉爽。冬天寒冷。"),
        passage("lets-read", "Let Us Read", [
            "Open your book.",
            "Look at the words.",
            "Listen and read after me.",
            "Now you can try again."
        ], "打开你的书。看这些单词。听并跟我读。现在你可以再试一次。")
    ]

    static let bundledQuotes: [EnglishLearningItem] = [
        quote("begin", "The secret of getting ahead is getting started.", "取得进步的秘诀就是开始行动。", "Mark Twain"),
        quote("possible", "It always seems impossible until it is done.", "在事情完成之前，它看起来总是不可能。", "Nelson Mandela"),
        quote("journey", "A journey of a thousand miles begins with a single step.", "千里之行，始于足下。", "Lao Tzu"),
        quote("courage", "Success is not final, failure is not fatal: it is the courage to continue that counts.", "成功不是终点，失败也并非致命，重要的是继续前进的勇气。", "Winston Churchill"),
        quote("sunshine", "Keep your face always toward the sunshine, and shadows will fall behind you.", "永远面向阳光，阴影就会落在你身后。", "Walt Whitman"),
        quote("learn", "Live as if you were to die tomorrow. Learn as if you were to live forever.", "像明天就会离开一样生活，像永远活着一样学习。", "Mahatma Gandhi"),
        quote("little", "Great things are done by a series of small things brought together.", "伟大的事情，是由许多小事汇聚而成的。", "Vincent van Gogh"),
        quote("believe", "Believe you can and you are halfway there.", "相信自己能做到，你就已经成功了一半。", "Theodore Roosevelt"),
        quote("today", "The future depends on what you do today.", "未来取决于你今天做什么。", "Mahatma Gandhi"),
        quote("mistakes", "A person who never made a mistake never tried anything new.", "从不犯错的人，从未尝试过新事物。", "Albert Einstein")
    ]
}
