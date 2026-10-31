import Foundation

/// 分学段的英语单词库。
///
/// 每个学段的词量级：
/// - `daily`         生活场景高频
/// - `primarySchool` 小学基础词
/// - `middleSchool`  初中核心词
/// - `highSchool`    高中核心词
/// - `cet4`          大学四级高频词
/// - `cet6`          大学六级高频词
/// - `ielts`         雅思核心词
/// - `toefl`         托福核心词
///
/// 后续扩词：只在下方对应数组末尾追加 `Self.word(...)` 一行即可，无需改动其它文件。
enum EnglishVocabulary {

    static func words(for stage: EnglishStage) -> [EnglishLearningItem] {
        bundledWords(for: stage) + supplementalWords(for: stage)
    }

    private static func bundledWords(for stage: EnglishStage) -> [EnglishLearningItem] {
        switch stage {
        case .daily:        return daily
        case .primarySchool: return primarySchool
        case .middleSchool: return middleSchool
        case .highSchool:   return highSchool
        case .cet4:         return cet4
        case .cet6:         return cet6
        case .ielts:        return ielts
        case .toefl:        return toefl
        }
    }

    /// 所有学段词汇的并集，用于统计等场景。
    static var all: [EnglishLearningItem] {
        EnglishStage.allCases.flatMap { words(for: $0) }
    }

    static func supplementalWords(for stage: EnglishStage) -> [EnglishLearningItem] {
        supplementalWordsByStage[stage] ?? []
    }

    // MARK: - 构造辅助

    private static func word(
        _ stage: EnglishStage,
        _ slug: String,
        _ title: String,
        _ pronunciation: String,
        _ part: String,
        _ translation: String,
        _ example: String,
        _ exampleTranslation: String
    ) -> EnglishLearningItem {
        // .daily 保留旧 id 格式（word.hello），需免老用户升级后历史进度丢失。
        let id = stage == .daily
            ? "word.\(slug)"
            : "word.\(stage.rawValue).\(slug)"
        return EnglishLearningItem(
            id: id,
            category: .words,
            stage: stage,
            title: title,
            pronunciation: pronunciation,
            partOfSpeech: part,
            translation: translation,
            example: example,
            exampleTranslation: exampleTranslation
        )
    }

    private static func supplementalWord(
        _ stage: EnglishStage,
        _ slug: String,
        _ title: String,
        _ pronunciation: String?,
        _ part: String?,
        _ translation: String,
        _ example: String?,
        _ exampleTranslation: String?
    ) -> EnglishLearningItem {
        EnglishLearningItem(
            id: "word.supplement.\(stage.rawValue).\(slug)",
            category: .words,
            stage: stage,
            title: title,
            pronunciation: pronunciation,
            partOfSpeech: part,
            translation: translation,
            example: example,
            exampleTranslation: exampleTranslation,
            source: "EnglishVocabularySupplement"
        )
    }

    // MARK: - 日常英语（生活场景）

    static let daily: [EnglishLearningItem] = [
        word(.daily, "hello", "hello", "/həˈloʊ/", "interj.", "你好", "Hello, nice to meet you.", "你好，很高兴认识你。"),
        word(.daily, "goodbye", "goodbye", "/ˌɡʊdˈbaɪ/", "interj.", "再见", "Goodbye. See you tomorrow.", "再见，明天见。"),
        word(.daily, "please", "please", "/pliːz/", "adv.", "请", "Please open the door.", "请把门打开。"),
        word(.daily, "thanks", "thanks", "/θæŋks/", "interj.", "谢谢", "Thanks for your help.", "谢谢你的帮助。"),
        word(.daily, "sorry", "sorry", "/ˈsɑːri/", "adj.", "抱歉的", "I am sorry I am late.", "很抱歉我迟到了。"),
        word(.daily, "yes", "yes", "/jes/", "adv.", "是；好的", "Yes, I understand.", "好的，我明白。"),
        word(.daily, "no", "no", "/noʊ/", "adv.", "不；没有", "No, thank you.", "不用了，谢谢。"),
        word(.daily, "name", "name", "/neɪm/", "n.", "名字", "My name is Lily.", "我的名字是莉莉。"),
        word(.daily, "friend", "friend", "/frend/", "n.", "朋友", "She is my good friend.", "她是我的好朋友。"),
        word(.daily, "family", "family", "/ˈfæməli/", "n.", "家庭；家人", "I love my family.", "我爱我的家人。"),
        word(.daily, "home", "home", "/hoʊm/", "n.", "家", "I am going home.", "我要回家。"),
        word(.daily, "school", "school", "/skuːl/", "n.", "学校", "The school is near my home.", "学校在我家附近。"),
        word(.daily, "work", "work", "/wɜːrk/", "n./v.", "工作", "I work from Monday to Friday.", "我从周一工作到周五。"),
        word(.daily, "book", "book", "/bʊk/", "n.", "书", "This is an English book.", "这是一本英语书。"),
        word(.daily, "water", "water", "/ˈwɔːtər/", "n.", "水", "May I have some water?", "我可以喝点水吗？"),
        word(.daily, "food", "food", "/fuːd/", "n.", "食物", "The food is delicious.", "食物很好吃。"),
        word(.daily, "apple", "apple", "/ˈæpəl/", "n.", "苹果", "I eat an apple every day.", "我每天吃一个苹果。"),
        word(.daily, "coffee", "coffee", "/ˈkɔːfi/", "n.", "咖啡", "I would like a cup of coffee.", "我想要一杯咖啡。"),
        word(.daily, "morning", "morning", "/ˈmɔːrnɪŋ/", "n.", "早晨", "I study English every morning.", "我每天早晨学习英语。"),
        word(.daily, "today", "today", "/təˈdeɪ/", "n./adv.", "今天", "Today is a beautiful day.", "今天是美好的一天。"),
        word(.daily, "tomorrow", "tomorrow", "/təˈmɑːroʊ/", "n./adv.", "明天", "I will call you tomorrow.", "我明天会给你打电话。"),
        word(.daily, "time", "time", "/taɪm/", "n.", "时间", "What time is it?", "现在几点？"),
        word(.daily, "happy", "happy", "/ˈhæpi/", "adj.", "高兴的", "I am happy to see you.", "见到你我很高兴。"),
        word(.daily, "good", "good", "/ɡʊd/", "adj.", "好的", "You did a good job.", "你做得很好。"),
        word(.daily, "small", "small", "/smɔːl/", "adj.", "小的", "I live in a small town.", "我住在一个小镇。"),
        word(.daily, "beautiful", "beautiful", "/ˈbjuːtɪfəl/", "adj.", "美丽的", "The flowers are beautiful.", "这些花很美。"),
        word(.daily, "learn", "learn", "/lɜːrn/", "v.", "学习", "I want to learn English.", "我想学习英语。"),
        word(.daily, "listen", "listen", "/ˈlɪsən/", "v.", "听", "Listen to the sentence again.", "再听一遍这个句子。"),
        word(.daily, "speak", "speak", "/spiːk/", "v.", "说；讲", "Please speak slowly.", "请说慢一点。"),
        word(.daily, "read", "read", "/riːd/", "v.", "阅读", "I read a short story.", "我读了一篇短故事。"),
        word(.daily, "help", "help", "/help/", "v./n.", "帮助", "Can you help me?", "你能帮助我吗？"),
        word(.daily, "start", "start", "/stɑːrt/", "v.", "开始", "Let us start now.", "让我们现在开始。"),
        word(.daily, "again", "again", "/əˈɡen/", "adv.", "再次", "Please say it again.", "请再说一遍。"),
        word(.daily, "slowly", "slowly", "/ˈsloʊli/", "adv.", "慢慢地", "He speaks slowly and clearly.", "他说得又慢又清楚。"),
        word(.daily, "understand", "understand", "/ˌʌndərˈstænd/", "v.", "理解", "I understand this word.", "我理解这个单词。"),
        word(.daily, "practice", "practice", "/ˈpræktɪs/", "n./v.", "练习", "Practice a little every day.", "每天练习一点。"),
        word(.daily, "money", "money", "/ˈmʌni/", "n.", "钱；货币", "I need some money to buy lunch.", "我需要一些钱买午饭。"),
        word(.daily, "phone", "phone", "/foʊn/", "n.", "电话；手机", "Please call me on my phone.", "请用手机给我打电话。"),
        word(.daily, "weather", "weather", "/ˈweðər/", "n.", "天气", "The weather is nice today.", "今天天气很好。"),
        word(.daily, "shop", "shop", "/ʃɑːp/", "n./v.", "商店；购物", "The shop opens at nine.", "这家商店九点开门。"),
        word(.daily, "street", "street", "/striːt/", "n.", "街道", "The store is on this street.", "那家店在这条街上。"),
        word(.daily, "bus", "bus", "/bʌs/", "n.", "公交车", "I take the bus to work.", "我乘公交车上班。"),
        word(.daily, "ticket", "ticket", "/ˈtɪkɪt/", "n.", "票", "I bought two movie tickets.", "我买了两张电影票。"),
        word(.daily, "restaurant", "restaurant", "/ˈrestrɑːnt/", "n.", "餐厅", "Let us meet at the restaurant.", "我们在餐厅见面吧。"),
        word(.daily, "hospital", "hospital", "/ˈhɑːspɪtl/", "n.", "医院", "The hospital is not far away.", "医院不远。"),
        word(.daily, "buy", "buy", "/baɪ/", "v.", "买", "I want to buy a new bag.", "我想买一个新包。"),
        word(.daily, "open", "open", "/ˈoʊpən/", "v./adj.", "打开；开的", "Please open the window.", "请打开窗户。"),
        word(.daily, "close", "close", "/kloʊz/", "v.", "关闭", "Please close the door.", "请关门。"),
        word(.daily, "wait", "wait", "/weɪt/", "v.", "等待", "Please wait a moment.", "请稍等片刻。"),
        word(.daily, "night", "night", "/naɪt/", "n.", "夜晚", "I sleep early at night.", "我晚上睡得早。"),
        word(.daily, "week", "week", "/wiːk/", "n.", "星期；周", "I will see you next week.", "我下周见你。"),
        word(.daily, "year", "year", "/jɪr/", "n.", "年", "Happy New Year!", "新年快乐！"),
        word(.daily, "love", "love", "/lʌv/", "v./n.", "爱；喜爱", "I love my hometown.", "我爱我的家乡。"),
        word(.daily, "tired", "tired", "/ˈtaɪərd/", "adj.", "疲倦的", "I feel tired after work.", "下班后我感到累。"),
        word(.daily, "hungry", "hungry", "/ˈhʌŋɡri/", "adj.", "饥饿的", "I am hungry. Let us eat.", "我饿了，我们吃饭吧。")
    ]

    // MARK: - 小学英语（基础词）

    static let primarySchool: [EnglishLearningItem] = [
        word(.primarySchool, "cat", "cat", "/kæt/", "n.", "猫", "The cat is under the chair.", "猫在椅子下面。"),
        word(.primarySchool, "dog", "dog", "/dɔːɡ/", "n.", "狗", "My dog likes to run.", "我的狗喜欢跑步。"),
        word(.primarySchool, "bird", "bird", "/bɜːrd/", "n.", "鸟", "A bird is singing in the tree.", "一只鸟在树上唱歌。"),
        word(.primarySchool, "fish", "fish", "/fɪʃ/", "n.", "鱼", "There is a fish in the bowl.", "碗里有一条鱼。"),
        word(.primarySchool, "mother", "mother", "/ˈmʌðər/", "n.", "妈妈", "My mother makes breakfast.", "我妈妈做早餐。"),
        word(.primarySchool, "father", "father", "/ˈfɑːðər/", "n.", "爸爸", "My father reads a book.", "我爸爸在读书。"),
        word(.primarySchool, "sister", "sister", "/ˈsɪstər/", "n.", "姐妹", "My sister is ten years old.", "我妹妹十岁。"),
        word(.primarySchool, "brother", "brother", "/ˈbrʌðər/", "n.", "兄弟", "My brother plays football.", "我哥哥踢足球。"),
        word(.primarySchool, "desk", "desk", "/desk/", "n.", "书桌", "The book is on the desk.", "书在桌子上。"),
        word(.primarySchool, "chair", "chair", "/tʃer/", "n.", "椅子", "Please sit on the chair.", "请坐在椅子上。"),
        word(.primarySchool, "pencil", "pencil", "/ˈpensəl/", "n.", "铅笔", "I write with a pencil.", "我用铅笔写字。"),
        word(.primarySchool, "bag", "bag", "/bæɡ/", "n.", "书包；包", "My bag is blue.", "我的书包是蓝色的。"),
        word(.primarySchool, "red", "red", "/red/", "adj.", "红色的", "This apple is red.", "这个苹果是红色的。"),
        word(.primarySchool, "blue", "blue", "/bluː/", "adj.", "蓝色的", "The sky is blue.", "天空是蓝色的。"),
        word(.primarySchool, "green", "green", "/ɡriːn/", "adj.", "绿色的", "The grass is green.", "草是绿色的。"),
        word(.primarySchool, "yellow", "yellow", "/ˈjeloʊ/", "adj.", "黄色的", "I have a yellow pencil.", "我有一支黄色铅笔。"),
        word(.primarySchool, "one", "one", "/wʌn/", "num.", "一", "I have one book.", "我有一本书。"),
        word(.primarySchool, "two", "two", "/tuː/", "num.", "二", "Two birds are in the tree.", "树上有两只鸟。"),
        word(.primarySchool, "three", "three", "/θriː/", "num.", "三", "There are three apples.", "这里有三个苹果。"),
        word(.primarySchool, "four", "four", "/fɔːr/", "num.", "四", "I see four chairs.", "我看见四把椅子。"),
        word(.primarySchool, "run", "run", "/rʌn/", "v.", "跑", "We run in the playground.", "我们在操场上跑步。"),
        word(.primarySchool, "jump", "jump", "/dʒʌmp/", "v.", "跳", "The boy can jump high.", "这个男孩能跳得很高。"),
        word(.primarySchool, "sing", "sing", "/sɪŋ/", "v.", "唱歌", "We sing an English song.", "我们唱一首英文歌。"),
        word(.primarySchool, "draw", "draw", "/drɔː/", "v.", "画", "I draw a small house.", "我画了一座小房子。"),
        word(.primarySchool, "eat", "eat", "/iːt/", "v.", "吃", "I eat rice for lunch.", "我午饭吃米饭。"),
        word(.primarySchool, "drink", "drink", "/drɪŋk/", "v.", "喝", "Please drink some water.", "请喝点水。"),
        word(.primarySchool, "big", "big", "/bɪɡ/", "adj.", "大的", "The elephant is big.", "大象很大。"),
        word(.primarySchool, "long", "long", "/lɔːŋ/", "adj.", "长的", "This ruler is long.", "这把尺子很长。"),
        word(.primarySchool, "short", "short", "/ʃɔːrt/", "adj.", "短的；矮的", "My pencil is short.", "我的铅笔很短。"),
        word(.primarySchool, "new", "new", "/nuː/", "adj.", "新的", "This is my new schoolbag.", "这是我的新书包。")
    ]

    // MARK: - 初中英语（中考核心词）

    static let middleSchool: [EnglishLearningItem] = [
        word(.middleSchool, "teacher", "teacher", "/ˈtiːtʃər/", "n.", "老师", "Our English teacher is very kind.", "我们的英语老师非常和蔼。"),
        word(.middleSchool, "student", "student", "/ˈstuːdənt/", "n.", "学生", "He is a hardworking student.", "他是一个勤奋的学生。"),
        word(.middleSchool, "classroom", "classroom", "/ˈklæsruːm/", "n.", "教室", "The classroom is on the second floor.", "教室在二楼。"),
        word(.middleSchool, "homework", "homework", "/ˈhoʊmwɜːrk/", "n.", "家庭作业", "I do my homework after dinner.", "我晚饭后做作业。"),
        word(.middleSchool, "subject", "subject", "/ˈsʌbdʒɪkt/", "n.", "科目", "Math is my favorite subject.", "数学是我最喜欢的科目。"),
        word(.middleSchool, "history", "history", "/ˈhɪstəri/", "n.", "历史", "We learn history every Tuesday.", "我们每周二学历史。"),
        word(.middleSchool, "science", "science", "/ˈsaɪəns/", "n.", "科学", "Science helps us understand the world.", "科学帮助我们认识世界。"),
        word(.middleSchool, "exam", "exam", "/ɪɡˈzæm/", "n.", "考试", "The final exam is next week.", "期末考试在下周。"),
        word(.middleSchool, "answer", "answer", "/ˈænsər/", "n./v.", "回答；答案", "Please answer my question.", "请回答我的问题。"),
        word(.middleSchool, "question", "question", "/ˈkwestʃən/", "n.", "问题", "May I ask you a question?", "我可以问你一个问题吗？"),
        word(.middleSchool, "different", "different", "/ˈdɪfərənt/", "adj.", "不同的", "We come from different countries.", "我们来自不同的国家。"),
        word(.middleSchool, "same", "same", "/seɪm/", "adj.", "相同的", "We are in the same class.", "我们在同一个班。"),
        word(.middleSchool, "important", "important", "/ɪmˈpɔːrtənt/", "adj.", "重要的", "It is important to keep trying.", "坚持尝试很重要。"),
        word(.middleSchool, "interesting", "interesting", "/ˈɪntrəstɪŋ/", "adj.", "有趣的", "The story is really interesting.", "这个故事真的很有趣。"),
        word(.middleSchool, "difficult", "difficult", "/ˈdɪfɪkəlt/", "adj.", "困难的", "This question is a little difficult.", "这个问题有点难。"),
        word(.middleSchool, "easy", "easy", "/ˈiːzi/", "adj.", "容易的", "The English test was easy for me.", "对我来说英语考试很简单。"),
        word(.middleSchool, "future", "future", "/ˈfjuːtʃər/", "n.", "未来", "I dream about my future.", "我梦想着我的未来。"),
        word(.middleSchool, "dream", "dream", "/driːm/", "n./v.", "梦想；做梦", "Never give up on your dream.", "永远不要放弃你的梦想。"),
        word(.middleSchool, "hope", "hope", "/hoʊp/", "n./v.", "希望", "I hope to see you soon.", "我希望很快能见到你。"),
        word(.middleSchool, "brave", "brave", "/breɪv/", "adj.", "勇敢的", "Be brave when facing problems.", "面对问题时要勇敢。"),
        word(.middleSchool, "healthy", "healthy", "/ˈhelθi/", "adj.", "健康的", "Fresh vegetables keep us healthy.", "新鲜的蔬菜让我们保持健康。"),
        word(.middleSchool, "exercise", "exercise", "/ˈeksərsaɪz/", "n./v.", "运动；练习", "I exercise for thirty minutes a day.", "我每天运动三十分钟。"),
        word(.middleSchool, "invite", "invite", "/ɪnˈvaɪt/", "v.", "邀请", "She invited me to her birthday party.", "她邀请我参加她的生日聚会。"),
        word(.middleSchool, "decide", "decide", "/dɪˈsaɪd/", "v.", "决定", "I decided to study harder.", "我决定更加努力学习。"),
        word(.middleSchool, "believe", "believe", "/bɪˈliːv/", "v.", "相信", "I believe in myself.", "我相信自己。"),
        word(.middleSchool, "remember", "remember", "/rɪˈmembər/", "v.", "记得", "Remember to bring your notebook.", "记得带上你的笔记本。"),
        word(.middleSchool, "forget", "forget", "/fərˈɡet/", "v.", "忘记", "Do not forget to say thank you.", "别忘了说谢谢。"),
        word(.middleSchool, "worry", "worry", "/ˈwɜːri/", "v.", "担心", "Do not worry, I will help you.", "别担心，我会帮你。"),
        word(.middleSchool, "surprise", "surprise", "/sərˈpraɪz/", "n./v.", "惊讶；使惊讶", "The gift was a big surprise.", "那份礼物是一个巨大的惊喜。"),
        word(.middleSchool, "notice", "notice", "/ˈnoʊtɪs/", "n./v.", "注意；通知", "I did not notice the mistake.", "我没有注意到那个错误。"),
        word(.middleSchool, "improve", "improve", "/ɪmˈpruːv/", "v.", "改进；提高", "Reading helps improve your English.", "阅读有助于提高你的英语。"),
        word(.middleSchool, "share", "share", "/ʃer/", "v.", "分享", "I share my snacks with friends.", "我和朋友们分享零食。"),
        word(.middleSchool, "protect", "protect", "/prəˈtekt/", "v.", "保护", "We should protect the environment.", "我们应该保护环境。"),
        word(.middleSchool, "environment", "environment", "/ɪnˈvaɪrənmənt/", "n.", "环境", "A clean environment matters.", "干净的环境很重要。"),
        word(.middleSchool, "problem", "problem", "/ˈprɑːbləm/", "n.", "问题；难题", "Let us solve this problem together.", "我们一起解决这个问题吧。")
    ]

    // MARK: - 高中英语（高考核心词）

    static let highSchool: [EnglishLearningItem] = [
        word(.highSchool, "achieve", "achieve", "/əˈtʃiːv/", "v.", "实现；取得", "She achieved her goal at last.", "她终于实现了目标。"),
        word(.highSchool, "opportunity", "opportunity", "/ˌɑːpərˈtuːnəti/", "n.", "机会", "This is a great opportunity to learn.", "这是一个学习的好机会。"),
        word(.highSchool, "challenge", "challenge", "/ˈtʃælɪndʒ/", "n./v.", "挑战", "Facing challenges makes us stronger.", "面对挑战让我们更强大。"),
        word(.highSchool, "society", "society", "/səˈsaɪəti/", "n.", "社会", "Technology changes our society fast.", "科技让社会飞速改变。"),
        word(.highSchool, "culture", "culture", "/ˈkʌltʃər/", "n.", "文化", "Language is a part of culture.", "语言是文化的一部分。"),
        word(.highSchool, "tradition", "tradition", "/trəˈdɪʃən/", "n.", "传统", "Family dinner is our tradition.", "家庭聚餐是我们的传统。"),
        word(.highSchool, "generation", "generation", "/ˌdʒenəˈreɪʃən/", "n.", "一代人", "Every generation has its own dream.", "每一代人都有自己的梦想。"),
        word(.highSchool, "communicate", "communicate", "/kəˈmjuːnɪkeɪt/", "v.", "沟通；交流", "We communicate through emails.", "我们通过邮件交流。"),
        word(.highSchool, "attitude", "attitude", "/ˈætɪtuːd/", "n.", "态度", "A positive attitude changes everything.", "积极的态度改变一切。"),
        word(.highSchool, "confident", "confident", "/ˈkɑːnfɪdənt/", "adj.", "自信的", "Be confident when you speak English.", "说英语时要自信。"),
        word(.highSchool, "responsible", "responsible", "/rɪˈspɑːnsəbəl/", "adj.", "有责任心的", "He is responsible for the team.", "他对团队负责。"),
        word(.highSchool, "encourage", "encourage", "/ɪnˈkɜːrɪdʒ/", "v.", "鼓励", "My parents encourage me to try.", "父母鼓励我去尝试。"),
        word(.highSchool, "environmentally", "environmental", "/ɪnˌvaɪrənˈmentəl/", "adj.", "环境的", "We should reduce environmental pollution.", "我们应该减少环境污染。"),
        word(.highSchool, "government", "government", "/ˈɡʌvərnmənt/", "n.", "政府", "The government plans a new policy.", "政府计划推出新政策。"),
        word(.highSchool, "economy", "economy", "/ɪˈkɑːnəmi/", "n.", "经济", "The economy is growing this year.", "今年经济在增长。"),
        word(.highSchool, "development", "development", "/dɪˈveləpmənt/", "n.", "发展", "Sustainable development matters to all.", "可持续发展对所有人都重要。"),
        word(.highSchool, "technology", "technology", "/tekˈnɑːlədʒi/", "n.", "科技", "Technology makes life easier.", "科技让生活变得更方便。"),
        word(.highSchool, "research", "research", "/rɪˈsɜːrtʃ/", "n./v.", "研究", "The team is doing important research.", "这个团队在做重要的研究。"),
        word(.highSchool, "analyze", "analyze", "/ˈænəlaɪz/", "v.", "分析", "She analyzed the data carefully.", "她仔细分析了这些数据。"),
        word(.highSchool, "conclusion", "conclusion", "/kənˈkluːʒən/", "n.", "结论", "We came to the same conclusion.", "我们得出了相同的结论。"),
        word(.highSchool, "argument", "argument", "/ˈɑːrɡjumənt/", "n.", "论点；争论", "His argument sounds reasonable.", "他的论点听起来很有道理。"),
        word(.highSchool, "propose", "propose", "/prəˈpoʊz/", "v.", "提议；建议", "I propose a new plan for the trip.", "我为这次旅行提议一个新方案。"),
        word(.highSchool, "obvious", "obvious", "/ˈɑːbviəs/", "adj.", "明显的", "The answer is obvious.", "答案很明显。"),
        word(.highSchool, "particular", "particular", "/pərˈtɪkjələr/", "adj.", "特别的", "Is there any particular topic you like?", "你有特别喜欢的话题吗？"),
        word(.highSchool, "efficient", "efficient", "/ɪˈfɪʃənt/", "adj.", "高效的", "This is an efficient way to study.", "这是一种高效的学习方式。"),
        word(.highSchool, "flexible", "flexible", "/ˈfleksəbəl/", "adj.", "灵活的", "The schedule is quite flexible.", "这个时间表相当灵活。"),
        word(.highSchool, "curious", "curious", "/ˈkjʊriəs/", "adj.", "好奇的", "Children are naturally curious.", "孩子天生就充满好奇。"),
        word(.highSchool, "impressive", "impressive", "/ɪmˈpresɪv/", "adj.", "令人印象深刻的", "Her English is really impressive.", "她的英语真的很惊艳。"),
        word(.highSchool, "concentrate", "concentrate", "/ˈkɑːnsəntreɪt/", "v.", "专注", "I need to concentrate on my work.", "我需要专注于工作。"),
        word(.highSchool, "distribute", "distribute", "/dɪˈstrɪbjuːt/", "v.", "分发；分配", "The teacher distributed the papers.", "老师分发了试卷。"),
        word(.highSchool, "sufficient", "sufficient", "/səˈfɪʃənt/", "adj.", "充足的", "We have sufficient time to prepare.", "我们有充足的时间准备。"),
        word(.highSchool, "eventually", "eventually", "/ɪˈventʃuəli/", "adv.", "最终", "He eventually finished the marathon.", "他最终跑完了马拉松。"),
        word(.highSchool, "meanwhile", "meanwhile", "/ˈmiːnwaɪl/", "adv.", "与此同时", "Meanwhile, I was writing an email.", "与此同时，我在写邮件。"),
        word(.highSchool, "regardless", "regardless", "/rɪˈɡɑːrdləs/", "adv.", "不管，不论", "He kept going regardless of the rain.", "不管下雨他还是继续前进。"),
        word(.highSchool, "achievement", "achievement", "/əˈtʃiːvmənt/", "n.", "成就", "Passing the exam was a big achievement.", "通过考试是一项大成就。")
    ]

    // MARK: - 大学四级（CET-4 高频词）

    static let cet4: [EnglishLearningItem] = [
        word(.cet4, "abandon", "abandon", "/əˈbændən/", "v.", "放弃；抛弃", "He refused to abandon his dream.", "他拒绝放弃他的梦想。"),
        word(.cet4, "abundant", "abundant", "/əˈbʌndənt/", "adj.", "丰富的", "The region has abundant resources.", "这个地区资源丰富。"),
        word(.cet4, "acquire", "acquire", "/əˈkwaɪər/", "v.", "获得；习得", "You can acquire new skills online.", "你可以在网上获得新技能。"),
        word(.cet4, "adequate", "adequate", "/ˈædɪkwət/", "adj.", "足够的", "The salary is adequate for now.", "这份薪水目前来说是够的。"),
        word(.cet4, "adjust", "adjust", "/əˈdʒʌst/", "v.", "调整", "It takes time to adjust to a new city.", "适应一个新城市需要时间。"),
        word(.cet4, "advocate", "advocate", "/ˈædvəkeɪt/", "v./n.", "提倡；拥护者", "She advocates a healthy lifestyle.", "她提倡健康的生活方式。"),
        word(.cet4, "aggressive", "aggressive", "/əˈɡresɪv/", "adj.", "激进的；有进取心的", "He has an aggressive sales strategy.", "他有激进的销售策略。"),
        word(.cet4, "alternative", "alternative", "/ɔːlˈtɜːrnətɪv/", "n./adj.", "替代方案", "Is there any alternative to this plan?", "有替代这个计划的方案吗？"),
        word(.cet4, "ambiguous", "ambiguous", "/æmˈbɪɡjuəs/", "adj.", "模糊的", "The email is quite ambiguous.", "这封邮件相当含糊。"),
        word(.cet4, "anticipate", "anticipate", "/ænˈtɪsɪpeɪt/", "v.", "预期；期待", "We anticipate a strong demand.", "我们预计会有强劲的需求。"),
        word(.cet4, "apparent", "apparent", "/əˈpærənt/", "adj.", "明显的；显而易见的", "It became apparent that he was right.", "很明显他是对的。"),
        word(.cet4, "approach", "approach", "/əˈproʊtʃ/", "n./v.", "方法；接近", "We should try a different approach.", "我们应该试试不同的方法。"),
        word(.cet4, "appropriate", "appropriate", "/əˈproʊpriət/", "adj.", "合适的", "Choose an appropriate word here.", "在这里选一个合适的词。"),
        word(.cet4, "assumption", "assumption", "/əˈsʌmpʃən/", "n.", "假设", "Your assumption seems reasonable.", "你的假设听起来合理。"),
        word(.cet4, "benefit", "benefit", "/ˈbenɪfɪt/", "n./v.", "益处；使受益", "Reading benefits your mind.", "阅读对头脑有益。"),
        word(.cet4, "commercial", "commercial", "/kəˈmɜːrʃəl/", "adj./n.", "商业的；广告", "The film was a commercial success.", "这部电影在商业上取得成功。"),
        word(.cet4, "consequence", "consequence", "/ˈkɑːnsɪkwens/", "n.", "结果；后果", "Every choice has its consequences.", "每个选择都有它的后果。"),
        word(.cet4, "considerable", "considerable", "/kənˈsɪdərəbəl/", "adj.", "相当大的", "It requires considerable effort.", "这需要相当大的努力。"),
        word(.cet4, "conventional", "conventional", "/kənˈvenʃənəl/", "adj.", "传统的；常规的", "He prefers a conventional design.", "他更喜欢传统的设计。"),
        word(.cet4, "declare", "declare", "/dɪˈkler/", "v.", "宣布；声明", "The company declared record profits.", "公司宣布利润创下纪录。"),
        word(.cet4, "demonstrate", "demonstrate", "/ˈdemənstreɪt/", "v.", "证明；演示", "Let me demonstrate how it works.", "我来演示一下它的用法。"),
        word(.cet4, "distinct", "distinct", "/dɪˈstɪŋkt/", "adj.", "独特的；明显的", "There is a distinct smell in the air.", "空气中有一种独特的气味。"),
        word(.cet4, "efficient", "efficient", "/ɪˈfɪʃənt/", "adj.", "高效的", "The new system is more efficient.", "新系统更高效。"),
        word(.cet4, "eliminate", "eliminate", "/ɪˈlɪmɪneɪt/", "v.", "消除；排除", "We must eliminate the risk quickly.", "我们必须尽快消除风险。"),
        word(.cet4, "emphasize", "emphasize", "/ˈemfəsaɪz/", "v.", "强调", "The teacher emphasized honesty.", "老师强调了诚实的重要性。"),
        word(.cet4, "essential", "essential", "/ɪˈsenʃəl/", "adj.", "必不可少的", "Sleep is essential for health.", "睡眠对健康至关重要。"),
        word(.cet4, "evaluate", "evaluate", "/ɪˈvæljueɪt/", "v.", "评估", "Please evaluate the plan carefully.", "请仔细评估这个方案。"),
        word(.cet4, "indicate", "indicate", "/ˈɪndɪkeɪt/", "v.", "表明；指出", "The data indicates a clear trend.", "数据表明了一个明显的趋势。"),
        word(.cet4, "significant", "significant", "/sɪɡˈnɪfɪkənt/", "adj.", "重要的；显著的", "The change had a significant impact.", "这个变化产生了重要影响。"),
        word(.cet4, "sustainable", "sustainable", "/səˈsteɪnəbəl/", "adj.", "可持续的", "Sustainable growth is our goal.", "可持续增长是我们的目标。")
    ]

    // MARK: - 大学六级（CET-6 高频词）

    static let cet6: [EnglishLearningItem] = [
        word(.cet6, "abolish", "abolish", "/əˈbɑːlɪʃ/", "v.", "废除；取消", "The law was abolished last year.", "这条法律去年被废除了。"),
        word(.cet6, "accelerate", "accelerate", "/əkˈseləreɪt/", "v.", "加速；促进", "The plan will accelerate our progress.", "这个计划将加快我们的进度。"),
        word(.cet6, "accommodate", "accommodate", "/əˈkɑːmədeɪt/", "v.", "容纳；适应", "The hotel can accommodate 500 guests.", "这家酒店可容纳500名客人。"),
        word(.cet6, "accumulate", "accumulate", "/əˈkjuːmjəleɪt/", "v.", "积累", "He accumulated a lot of experience.", "他积累了很多经验。"),
        word(.cet6, "acknowledge", "acknowledge", "/əkˈnɑːlɪdʒ/", "v.", "承认；鸣谢", "She acknowledged her mistake.", "她承认了自己的错误。"),
        word(.cet6, "ambitious", "ambitious", "/æmˈbɪʃəs/", "adj.", "有雄心的", "She is an ambitious young leader.", "她是一位有雄心的年轻领导者。"),
        word(.cet6, "appreciate", "appreciate", "/əˈpriːʃieɪt/", "v.", "欣赏；感激", "I appreciate your kind help.", "我很感激你的热心帮助。"),
        word(.cet6, "comprehensive", "comprehensive", "/ˌkɑːmprɪˈhensɪv/", "adj.", "全面的；综合的", "We need a comprehensive plan.", "我们需要一个全面的计划。"),
        word(.cet6, "conform", "conform", "/kənˈfɔːrm/", "v.", "遵守；符合", "All products must conform to the rules.", "所有产品都必须符合规定。"),
        word(.cet6, "contemporary", "contemporary", "/kənˈtempəreri/", "adj.", "当代的；同时代的", "I enjoy contemporary art.", "我喜欢当代艺术。"),
        word(.cet6, "controversial", "controversial", "/ˌkɑːntrəˈvɜːrʃəl/", "adj.", "有争议的", "It is a controversial topic.", "这是一个有争议的话题。"),
        word(.cet6, "deliberate", "deliberate", "/dɪˈlɪbərət/", "adj.", "故意的；慎重的", "It was a deliberate decision.", "这是一个深思熟虑的决定。"),
        word(.cet6, "discipline", "discipline", "/ˈdɪsəplɪn/", "n.", "纪律；学科", "Good discipline helps you succeed.", "良好的自律帮你成功。"),
        word(.cet6, "distinguish", "distinguish", "/dɪˈstɪŋgwɪʃ/", "v.", "区分；辨别", "Can you distinguish the two words?", "你能区分这两个词吗？"),
        word(.cet6, "elaborate", "elaborate", "/ɪˈlæbərət/", "adj.", "精心制作的；详细的", "She gave an elaborate explanation.", "她给出了详细的解释。"),
        word(.cet6, "encounter", "encounter", "/ɪnˈkaʊntər/", "v./n.", "遇到；邂逅", "We encountered some problems.", "我们遇到了一些问题。"),
        word(.cet6, "enhance", "enhance", "/ɪnˈhæns/", "v.", "提高；增强", "Music can enhance your mood.", "音乐能提升你的心情。"),
        word(.cet6, "exaggerate", "exaggerate", "/ɪɡˈzædʒəreɪt/", "v.", "夸大", "Do not exaggerate the danger.", "不要夸大危险。"),
        word(.cet6, "fundamental", "fundamental", "/ˌfʌndəˈmentl/", "adj.", "基本的；基础的", "Trust is fundamental to teamwork.", "信任是团队合作的基础。"),
        word(.cet6, "inevitable", "inevitable", "/ɪnˈevɪtəbəl/", "adj.", "不可避免的", "Change is inevitable in life.", "变化在生活中是不可避免的。"),
        word(.cet6, "integrate", "integrate", "/ˈɪntɪɡreɪt/", "v.", "整合；使结合", "We integrate new tools into our work.", "我们将新工具整合到工作中。"),
        word(.cet6, "intense", "intense", "/ɪnˈtens/", "adj.", "强烈的；激烈的", "The competition is very intense.", "这场竞争非常激烈。"),
        word(.cet6, "manipulate", "manipulate", "/məˈnɪpjəleɪt/", "v.", "操纵；处理", "He knows how to manipulate the data.", "他知道如何处理这些数据。"),
        word(.cet6, "notion", "notion", "/ˈnoʊʃən/", "n.", "概念；想法", "I have no notion of what he means.", "我不明白他的意思。"),
        word(.cet6, "obstacle", "obstacle", "/ˈɑːbstəkəl/", "n.", "障碍", "We overcame every obstacle.", "我们克服了每一个障碍。"),
        word(.cet6, "perceive", "perceive", "/pərˈsiːv/", "v.", "感知；理解", "People perceive colors differently.", "人们对颜色的感知各不相同。"),
        word(.cet6, "prevail", "prevail", "/prɪˈveɪl/", "v.", "盛行；胜出", "Justice will prevail in the end.", "正义最终将战胜。"),
        word(.cet6, "prohibit", "prohibit", "/proʊˈhɪbɪt/", "v.", "禁止", "Smoking is prohibited here.", "这里禁止吸烟。"),
        word(.cet6, "reinforce", "reinforce", "/ˌriːɪnˈfɔːrs/", "v.", "加强；强化", "Practice reinforces what you learn.", "练习能巩固你所学的内容。"),
        word(.cet6, "reluctant", "reluctant", "/rɪˈlʌktənt/", "adj.", "不情愿的", "He was reluctant to leave.", "他不愿意离开。"),
        word(.cet6, "subsequent", "subsequent", "/ˈsʌbsɪkwənt/", "adj.", "随后的", "Subsequent events proved him right.", "后来发生的事证明他是对的。"),
        word(.cet6, "tremendous", "tremendous", "/trəˈmendəs/", "adj.", "巨大的；极好的", "She made tremendous progress.", "她取得了巨大的进步。"),
        word(.cet6, "versatile", "versatile", "/ˈvɜːrsətəl/", "adj.", "多才多艺的；多用途的", "He is a versatile musician.", "他是一位多才多艺的音乐家。")
    ]

    // MARK: - 雅思（IELTS 核心词）

    static let ielts: [EnglishLearningItem] = [
        word(.ielts, "academic", "academic", "/ˌækəˈdemɪk/", "adj.", "学术的；学院的", "She writes in an academic style.", "她以学术风格写作。"),
        word(.ielts, "adequate", "adequate", "/ˈædɪkwət/", "adj.", "足够的；适当的", "The training was adequate for the job.", "这些培训足以胜任这份工作。"),
        word(.ielts, "allocate", "allocate", "/ˈæləkeɪt/", "v.", "分配", "We allocate time for reading daily.", "我们每天分配时间阅读。"),
        word(.ielts, "aspect", "aspect", "/ˈæspekt/", "n.", "方面", "Let us consider every aspect.", "让我们考虑每一个方面。"),
        word(.ielts, "benefit", "benefit", "/ˈbenɪfɪt/", "n./v.", "好处；使受益", "Exercise has many benefits.", "锻炼有很多好处。"),
        word(.ielts, "consequence", "consequence", "/ˈkɑːnsɪkwəns/", "n.", "后果；结果", "Actions have consequences.", "行为都有后果。"),
        word(.ielts, "considerable", "considerable", "/kənˈsɪdərəbəl/", "adj.", "相当大的", "It saved a considerable amount of time.", "这节省了相当多的时间。"),
        word(.ielts, "constant", "constant", "/ˈkɑːnstənt/", "adj.", "持续的；不变的", "He made constant efforts to improve.", "他不断努力以求提高。"),
        word(.ielts, "contribute", "contribute", "/kənˈtrɪbjuːt/", "v.", "贡献；促成", "Everyone can contribute ideas.", "每个人都可以贡献想法。"),
        word(.ielts, "crucial", "crucial", "/ˈkruːʃəl/", "adj.", "关键的", "Timing is crucial for success.", "时机对成功至关重要。"),
        word(.ielts, "cultural", "cultural", "/ˈkʌltʃərəl/", "adj.", "文化的", "Travel broadens your cultural view.", "旅行拓宽你的文化视野。"),
        word(.ielts, "decline", "decline", "/dɪˈklaɪn/", "v./n.", "下降；拒绝", "Sales began to decline slowly.", "销售额开始缓慢下降。"),
        word(.ielts, "demonstrate", "demonstrate", "/ˈdemənstreɪt/", "v.", "证明；演示", "The study demonstrates a clear link.", "这项研究证明了一种明确的联系。"),
        word(.ielts, "efficient", "efficient", "/ɪˈfɪʃənt/", "adj.", "高效的", "Public transport is efficient here.", "这里的公共交通很高效。"),
        word(.ielts, "emerge", "emerge", "/ɪˈmɜːrdʒ/", "v.", "出现；浮现", "New trends emerge every year.", "每年都会出现新趋势。"),
        word(.ielts, "essential", "essential", "/ɪˈsenʃəl/", "adj.", "必不可少的", "Water is essential for life.", "水对生命至关重要。"),
        word(.ielts, "establish", "establish", "/ɪˈstæblɪʃ/", "v.", "建立；创立", "They established a new company.", "他们创立了一家新公司。"),
        word(.ielts, "evident", "evident", "/ˈevɪdənt/", "adj.", "明显的", "His talent is evident to all.", "他的才华有目共睹。"),
        word(.ielts, "factor", "factor", "/ˈfæktər/", "n.", "因素", "Cost is an important factor.", "成本是一个重要因素。"),
        word(.ielts, "generate", "generate", "/ˈdʒenəreɪt/", "v.", "产生；生成", "The event generated great interest.", "这个活动引发了浓厚兴趣。"),
        word(.ielts, "impact", "impact", "/ˈɪmpækt/", "n./v.", "影响；冲击", "Technology has a huge impact on us.", "科技对我们有巨大影响。"),
        word(.ielts, "implement", "implement", "/ˈɪmplɪment/", "v.", "实施；执行", "The city will implement a new policy.", "该市将实施一项新政策。"),
        word(.ielts, "individual", "individual", "/ˌɪndɪˈvɪdʒuəl/", "n./adj.", "个人；个别的", "Each individual has unique needs.", "每个人都有独特的需求。"),
        word(.ielts, "maintain", "maintain", "/meɪnˈteɪn/", "v.", "维持；保养", "It is hard to maintain a balance.", "保持平衡很难。"),
        word(.ielts, "obtain", "obtain", "/əbˈteɪn/", "v.", "获得", "You can obtain a visa online.", "你可以在网上获得签证。"),
        word(.ielts, "potential", "potential", "/pəˈtenʃəl/", "n./adj.", "潜力；潜在的", "She has great potential.", "她有很大的潜力。"),
        word(.ielts, "previous", "previous", "/ˈpriːviəs/", "adj.", "先前的", "See my previous email for details.", "详情请看我之前的邮件。"),
        word(.ielts, "reduce", "reduce", "/rɪˈduːs/", "v.", "减少", "We must reduce plastic waste.", "我们必须减少塑料垃圾。"),
        word(.ielts, "reliable", "reliable", "/rɪˈlaɪəbəl/", "adj.", "可靠的", "He is a reliable partner.", "他是一个可靠的伙伴。"),
        word(.ielts, "resource", "resource", "/ˈriːsɔːrs/", "n.", "资源", "Water is a precious resource.", "水是宝贵的资源。"),
        word(.ielts, "significant", "significant", "/sɪɡˈnɪfɪkənt/", "adj.", "重要的；显著的", "There is a significant difference.", "存在显著的差异。"),
        word(.ielts, "tendency", "tendency", "/ˈtendənsi/", "n.", "趋势；倾向", "There is a tendency to overwork.", "人们有过度工作的倾向。")
    ]

    // MARK: - 托福（TOEFL 核心词）

    static let toefl: [EnglishLearningItem] = [
        word(.toefl, "abstract", "abstract", "/ˈæbstrækt/", "adj.", "抽象的", "Math can be quite abstract.", "数学可能相当抽象。"),
        word(.toefl, "adapt", "adapt", "/əˈdæpt/", "v.", "适应；改编", "Animals adapt to their environment.", "动物会适应它们的环境。"),
        word(.toefl, "analyze", "analyze", "/ˈænəlaɪz/", "v.", "分析", "Scientists analyze the samples.", "科学家分析这些样本。"),
        word(.toefl, "approximate", "approximate", "/əˈprɑːksɪmət/", "adj.", "大约的；近似的", "Give me an approximate figure.", "给我一个大致的数字。"),
        word(.toefl, "assess", "assess", "/əˈses/", "v.", "评估", "Teachers assess student progress.", "老师评估学生的进步。"),
        word(.toefl, "complex", "complex", "/ˈkɑːmpleks/", "adj.", "复杂的", "The human brain is very complex.", "人脑非常复杂。"),
        word(.toefl, "component", "component", "/kəmˈpoʊnənt/", "n.", "组成部分", "Water has two components.", "水由两种成分组成。"),
        word(.toefl, "conduct", "conduct", "/kənˈdʌkt/", "v.", "进行；实施", "They conduct research on climate.", "他们进行气候研究。"),
        word(.toefl, "consist", "consist", "/kənˈsɪst/", "v.", "组成；在于", "The team consists of five people.", "这个团队由五个人组成。"),
        word(.toefl, "constitute", "constitute", "/ˈkɑːnstətuːt/", "v.", "构成", "These parts constitute the whole.", "这些部分构成了整体。"),
        word(.toefl, "derive", "derive", "/dɪˈraɪv/", "v.", "源于；获得", "The word derives from Latin.", "这个词源自拉丁语。"),
        word(.toefl, "distinct", "distinct", "/dɪˈstɪŋkt/", "adj.", "明显的；截然不同的", "They have distinct styles.", "他们有截然不同的风格。"),
        word(.toefl, "dominant", "dominant", "/ˈdɑːmɪnənt/", "adj.", "占主导地位的", "English is the dominant language here.", "英语是这里的主导语言。"),
        word(.toefl, "emphasis", "emphasis", "/ˈemfəsɪs/", "n.", "强调；重点", "The course puts emphasis on writing.", "这门课注重写作。"),
        word(.toefl, "evolve", "evolve", "/ɪˈvɑːlv/", "v.", "进化；发展", "Species evolve over time.", "物种随时间进化。"),
        word(.toefl, "expand", "expand", "/ɪkˈspænd/", "v.", "扩展；膨胀", "Metal expands when heated.", "金属受热时会膨胀。"),
        word(.toefl, "hypothesis", "hypothesis", "/haɪˈpɑːθəsɪs/", "n.", "假设", "The experiment tests a hypothesis.", "这个实验检验一个假设。"),
        word(.toefl, "illustrate", "illustrate", "/ˈɪləstreɪt/", "v.", "说明；举例", "Let me illustrate with an example.", "让我举个例子说明。"),
        word(.toefl, "initial", "initial", "/ɪˈnɪʃəl/", "adj.", "最初的", "The initial results look good.", "初步结果看起来不错。"),
        word(.toefl, "innovation", "innovation", "/ˌɪnəˈveɪʃən/", "n.", "创新", "Innovation drives the economy.", "创新推动经济发展。"),
        word(.toefl, "interpret", "interpret", "/ɪnˈtɜːrprɪt/", "v.", "解释；口译", "How do you interpret this result?", "你如何解读这个结果？"),
        word(.toefl, "mechanism", "mechanism", "/ˈmekənɪzəm/", "n.", "机制；机理", "We study the defense mechanism.", "我们研究防御机制。"),
        word(.toefl, "phenomenon", "phenomenon", "/fəˈnɑːmɪnɑːn/", "n.", "现象", "It is a natural phenomenon.", "这是一种自然现象。"),
        word(.toefl, "precise", "precise", "/prɪˈsaɪs/", "adj.", "精确的", "We need precise measurements.", "我们需要精确的测量。"),
        word(.toefl, "primary", "primary", "/ˈpraɪmeri/", "adj.", "主要的；初级的", "Our primary goal is safety.", "我们的首要目标是安全。"),
        word(.toefl, "proportion", "proportion", "/prəˈpɔːrʃən/", "n.", "比例；部分", "A large proportion agreed.", "很大一部分人表示同意。"),
        word(.toefl, "reveal", "reveal", "/rɪˈviːl/", "v.", "揭示；显示", "The data reveals a clear pattern.", "数据揭示了一个明显的规律。"),
        word(.toefl, "species", "species", "/ˈspiːʃiːz/", "n.", "物种", "This species is very rare.", "这个物种非常稀有。"),
        word(.toefl, "structure", "structure", "/ˈstrʌktʃər/", "n.", "结构", "The essay has a clear structure.", "这篇文章结构清晰。"),
        word(.toefl, "substance", "substance", "/ˈsʌbstəns/", "n.", "物质", "Water is a common substance.", "水是一种常见物质。"),
        word(.toefl, "theory", "theory", "/ˈθiːəri/", "n.", "理论", "The theory explains many facts.", "这个理论解释了很多事实。")
    ]
}

private extension EnglishVocabulary {
    struct SupplementalBook: Decodable {
        let stage: EnglishStage
        let items: [SupplementalEntry]
    }

    struct SupplementalEntry: Decodable {
        let word: String
        let translation: String
        let pronunciation: String?
        let part: String?
        let example: String?
        let exampleTranslation: String?
    }

    static let supplementalWordsByStage: [EnglishStage: [EnglishLearningItem]] = loadSupplementalWords()

    static func loadSupplementalWords() -> [EnglishStage: [EnglishLearningItem]] {
        var result: [EnglishStage: [EnglishLearningItem]] = [:]
        var knownWordsByStage = Dictionary(
            uniqueKeysWithValues: EnglishStage.allCases.map { stage in
                (stage, Set(bundledWords(for: stage).map { $0.title.lowercased() }))
            }
        )

        for book in supplementalBooks {
            var entries: [EnglishLearningItem] = []
            var knownWords = knownWordsByStage[book.stage] ?? []

            for entry in book.items {
                let title = entry.word.trimmingCharacters(in: .whitespacesAndNewlines)
                let translation = entry.translation.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !title.isEmpty, !translation.isEmpty else { continue }
                guard knownWords.insert(title.lowercased()).inserted else { continue }

                entries.append(supplementalWord(
                    book.stage,
                    slugify(title, fallback: "\(entries.count + 1)"),
                    title,
                    entry.pronunciation?.nilIfEmpty,
                    entry.part?.nilIfEmpty,
                    translation,
                    entry.example?.nilIfEmpty,
                    entry.exampleTranslation?.nilIfEmpty
                ))
            }

            result[book.stage, default: []].append(contentsOf: entries)
            knownWordsByStage[book.stage] = knownWords
        }

        return result
    }

    static var supplementalBooks: [SupplementalBook] {
        supplementalVocabularyURLs.flatMap { url -> [SupplementalBook] in
            guard let data = try? Data(contentsOf: url),
                  let books = try? JSONDecoder().decode([SupplementalBook].self, from: data) else {
                return []
            }
            return books
        }
    }

    static var supplementalVocabularyURLs: [URL] {
        let resourceNames = [
            "EnglishVocabularyStarterSupplement",
            "EnglishVocabularySupplement",
            "EnglishVocabularyBulkSupplement",
            "EnglishVocabularyLevelSupplement",
            "EnglishVocabularyDailyExpansion",
            "EnglishVocabularyCet6Expansion",
            "EnglishVocabularyIeltsExpansion",
            "EnglishVocabularyToeflExpansion",
            "EnglishVocabularyDailyMegaExpansion",
            "EnglishVocabularySchoolMegaExpansion",
            "EnglishVocabularyAdvancedMegaExpansion",
            "EnglishVocabularyExamMegaExpansion",
            "EnglishVocabularyThousandExpansion"
        ]
        for bundle in [Bundle.main, Bundle(for: EnglishVocabularyBundleToken.self)] {
            let urls = resourceNames.compactMap { bundle.url(forResource: $0, withExtension: "json") }
            if !urls.isEmpty { return urls }
        }
        return []
    }

    static func slugify(_ text: String, fallback: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let slug = text.lowercased().unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let compact = String(slug)
            .split(separator: "-")
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return compact.isEmpty ? fallback : compact
    }
}

private final class EnglishVocabularyBundleToken {}

private extension String {
    var nilIfEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
