// Mulberry Symbols mapping data for Yuqiao.
// Keep this file free of Flutter imports so validation tools can import it.

class MulberrySymbolResolver {
  const MulberrySymbolResolver._();

  static const String attribution =
      'Symbols from Mulberry Symbols, used under CC BY-SA.';

  static String normalize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[\s，。！？、,.!?：:；;“”（）()\[\]【】]'), '')
        .replaceAll('"', '')
        .replaceAll("'", '');
  }

  static String? assetForText(String text) {
    final normalized = normalize(text);
    if (normalized.isEmpty) return null;
    String? bestAsset;
    var bestKeywordLength = 0;
    var bestKeywordIndex = -1;
    for (final rule in entries) {
      if (rule.status == 'disabled') continue;
      for (final keyword in rule.keywords) {
        final normalizedKeyword = normalize(keyword);
        if (normalizedKeyword.isEmpty) continue;
        if (normalizedTextEquals(normalized, normalizedKeyword)) {
          return rule.asset;
        }
        final keywordIndex = normalized.indexOf(normalizedKeyword);
        if (keywordIndex >= 0 &&
            (normalizedKeyword.length > bestKeywordLength ||
                (normalizedKeyword.length == bestKeywordLength &&
                    keywordIndex > bestKeywordIndex))) {
          bestAsset = rule.asset;
          bestKeywordLength = normalizedKeyword.length;
          bestKeywordIndex = keywordIndex;
        }
      }
    }
    return bestAsset;
  }

  static bool hasSymbolFor(String text) => assetForText(text) != null;

  static bool normalizedTextEquals(String text, String keyword) =>
      text == keyword;

  static const List<MulberrySymbolEntry> entries = [
    MulberrySymbolEntry('EN-symbols/headache.svg', ['头疼', '头痛', 'headache']),
    MulberrySymbolEntry('EN-symbols/back_ache.svg', ['背疼', '背痛', '腰疼', '腰痛']),
    MulberrySymbolEntry(
        'EN-symbols/drink_,_to.svg', ['喝水', '想喝', '口渴', '喝一口', 'drink']),
    MulberrySymbolEntry('EN-symbols/water.svg', ['水', 'water']),
    MulberrySymbolEntry(
        'EN-symbols/eat_,_to.svg', ['吃饭', '吃东西', '想吃', '饿', 'eat'],
        status: 'disabled', note: '未找到合适的图片'),
    MulberrySymbolEntry('EN-symbols/bread.svg', ['面包', 'bread']),
    MulberrySymbolEntry('EN-symbols/coffee.svg', ['咖啡', 'coffee']),
    MulberrySymbolEntry('EN-symbols/tea.svg', ['茶', 'tea']),
    MulberrySymbolEntry('EN-symbols/doctor_1a.svg', ['医生', 'doctor']),
    MulberrySymbolEntry('EN-symbols/nurse_1a.svg', ['护士', 'nurse']),
    MulberrySymbolEntry(
        'EN-symbols/medicine.svg', ['药', '吃药', '买药', 'medicine']),
    MulberrySymbolEntry(
        'EN-symbols/toilet.svg', ['厕所', '卫生间', '上厕所', '洗手间', 'toilet']),
    MulberrySymbolEntry(
        'EN-symbols/house.svg', ['回家', '家里', '在家', '家', 'home', 'house']),
    MulberrySymbolEntry('EN-symbols/park_,_to.svg', ['公园', 'park'],
        status: 'disabled', note: '未找到合适的图片'),
    MulberrySymbolEntry('EN-symbols/school.svg', ['学校', '老师', '上课', 'school']),
    MulberrySymbolEntry('EN-symbols/key_1.svg', ['钥匙', 'key']),
    MulberrySymbolEntry('EN-symbols/glasses.svg', ['眼镜', 'glasses']),
    MulberrySymbolEntry('EN-symbols/phone_picture_video.svg',
        ['手机', '电话', '拍照', '照片', 'phone']),
    MulberrySymbolEntry(
        'EN-symbols/rest_,_to.svg', ['休息', '累了', '休息一下', 'rest'],
        status: 'disabled', note: '未找到合适的图片'),
    MulberrySymbolEntry('EN-symbols/sleep_male_,_to.svg', ['睡觉', '困', 'sleep'],
        status: 'disabled', note: '未找到合适的图片'),
    MulberrySymbolEntry(
        'EN-symbols/walk_,_to.svg', ['散步', '走路', '走一走', 'walk']),
    MulberrySymbolEntry('EN-symbols/help_,_to.svg', ['帮我', '帮助', '帮忙', 'help']),
    MulberrySymbolEntry(
        'EN-symbols/mum_parent.svg', ['妈妈', '母亲', 'mum', 'mother']),
    MulberrySymbolEntry(
        'EN-symbols/family.svg', ['家人', '朋友', '女儿', '儿子', 'family', 'friend']),
    MulberrySymbolEntry(
        'EN-symbols/happy_man.svg', ['开心', '高兴', '挺好的', '舒服', 'happy']),
    MulberrySymbolEntry('EN-symbols/sad_man.svg', ['难过', '伤心', '不舒服', 'sad']),

    // ===== 食物 =====
    MulberrySymbolEntry('EN-symbols/banana.svg', ['香蕉', 'banana']),
    MulberrySymbolEntry('EN-symbols/orange.svg', ['橙子', '橘子', 'orange']),
    MulberrySymbolEntry('EN-symbols/grapes.svg', ['葡萄', 'grapes']),
    MulberrySymbolEntry('EN-symbols/rice.svg', ['米饭', '饭', 'rice']),
    MulberrySymbolEntry('EN-symbols/noodles.svg', ['面条', 'noodles']),
    MulberrySymbolEntry('EN-symbols/soup.svg', ['汤', 'soup']),
    MulberrySymbolEntry('EN-symbols/egg.svg', ['鸡蛋', 'egg']),
    MulberrySymbolEntry('EN-symbols/milk.svg', ['牛奶', 'milk']),
    MulberrySymbolEntry('EN-symbols/orange_juice.svg', ['橙汁', '果汁', 'juice']),
    MulberrySymbolEntry('EN-symbols/beer.svg', ['啤酒', 'beer']),
    MulberrySymbolEntry('EN-symbols/wine.svg', ['红酒', '酒', 'wine']),
    MulberrySymbolEntry('EN-symbols/cake.svg', ['蛋糕', 'cake']),
    MulberrySymbolEntry('EN-symbols/chocolate.svg', ['巧克力', 'chocolate']),
    MulberrySymbolEntry('EN-symbols/ice_cream.svg', ['冰淇淋', 'ice cream']),
    MulberrySymbolEntry('EN-symbols/fruit.svg', ['水果', 'fruit']),
    MulberrySymbolEntry('EN-symbols/vegetables.svg', ['蔬菜', 'vegetables']),
    MulberrySymbolEntry('EN-symbols/meat.svg', ['肉', 'meat']),
    MulberrySymbolEntry('EN-symbols/fish.svg', ['鱼', 'fish']),
    MulberrySymbolEntry('EN-symbols/chicken.svg', ['鸡肉', '鸡', 'chicken']),
    MulberrySymbolEntry('EN-symbols/pizza.svg', ['披萨', 'pizza']),
    MulberrySymbolEntry('EN-symbols/hamburger.svg', ['汉堡', '汉堡包', 'hamburger']),
    MulberrySymbolEntry('EN-symbols/sandwich.svg', ['三明治', 'sandwich']),
    MulberrySymbolEntry('EN-symbols/salad.svg', ['沙拉', 'salad']),
    MulberrySymbolEntry('EN-symbols/cheese.svg', ['奶酪', '芝士', 'cheese']),
    MulberrySymbolEntry('EN-symbols/butter.svg', ['黄油', 'butter']),
    MulberrySymbolEntry('EN-symbols/castor_sugar.svg', ['糖', 'sugar']),
    MulberrySymbolEntry('EN-symbols/salt.svg', ['盐', 'salt']),
    MulberrySymbolEntry('EN-symbols/pepper.svg', ['胡椒', 'pepper']),
    MulberrySymbolEntry('EN-symbols/cooking_oil.svg', ['食用油', '油', 'oil']),
    MulberrySymbolEntry('EN-symbols/pineapple.svg', ['菠萝', 'pineapple']),
    MulberrySymbolEntry('EN-symbols/grapefruit.svg', ['柚子', 'grapefruit']),
    MulberrySymbolEntry('EN-symbols/avocado.svg', ['牛油果', 'avocado']),
    MulberrySymbolEntry('EN-symbols/lemon.svg', ['柠檬', 'lemon']),
    MulberrySymbolEntry('EN-symbols/strawberry.svg', ['草莓', 'strawberry']),
    MulberrySymbolEntry('EN-symbols/watermelon.svg', ['西瓜', 'watermelon']),
    MulberrySymbolEntry('EN-symbols/peach.svg', ['桃子', 'peach']),
    MulberrySymbolEntry('EN-symbols/cherry.svg', ['樱桃', 'cherry']),
    MulberrySymbolEntry('EN-symbols/pear.svg', ['梨', 'pear']),
    MulberrySymbolEntry('EN-symbols/mango.svg', ['芒果', 'mango']),
    MulberrySymbolEntry('EN-symbols/egg_fried.svg', ['煎蛋', 'fried egg']),
    MulberrySymbolEntry('EN-symbols/soup_tomato.svg', ['番茄汤', 'tomato soup']),
    MulberrySymbolEntry(
        'EN-symbols/hot_chocolate.svg', ['热巧克力', 'hot chocolate']),
    MulberrySymbolEntry('EN-symbols/milkshake.svg', ['奶昔', 'milkshake']),
    MulberrySymbolEntry(
        'EN-symbols/biscuit_chocolate_chip.svg', ['饼干', 'biscuit']),
    MulberrySymbolEntry('EN-symbols/pancakes.svg', ['煎饼', 'pancake']),
    MulberrySymbolEntry('EN-symbols/bacon.svg', ['培根', 'bacon']),
    MulberrySymbolEntry('EN-symbols/sausages.svg', ['香肠', 'sausage']),
    MulberrySymbolEntry('EN-symbols/crisps_cheese_puffs.svg', ['薯片', 'crisps']),

    // ===== 身体部位 =====
    MulberrySymbolEntry('EN-symbols/head.svg', ['头', 'head']),
    MulberrySymbolEntry('EN-symbols/eye.svg', ['眼睛', 'eye']),
    MulberrySymbolEntry('EN-symbols/ear.svg', ['耳朵', 'ear']),
    MulberrySymbolEntry('EN-symbols/mouth.svg', ['嘴巴', '嘴', 'mouth']),
    MulberrySymbolEntry('EN-symbols/foot.svg', ['脚', 'foot']),
    MulberrySymbolEntry('EN-symbols/leg.svg', ['腿', 'leg']),
    MulberrySymbolEntry('EN-symbols/arm.svg', ['胳膊', '手臂', 'arm']),
    MulberrySymbolEntry('EN-symbols/finger.svg', ['手指', 'finger']),
    MulberrySymbolEntry('EN-symbols/tooth.svg', ['牙齿', '牙', 'tooth']),
    MulberrySymbolEntry('EN-symbols/face_neutral_3.svg', ['脸', '面部', 'face'],
        status: 'disabled', note: '未找到合适的图片'),
    MulberrySymbolEntry('EN-symbols/long_hair.svg', ['头发', 'hair'],
        status: 'disabled', note: '未找到合适的图片'),
    MulberrySymbolEntry('EN-symbols/brush_hair_,_to.svg', ['梳头'],
        status: 'disabled', note: '未找到合适的图片'),
    MulberrySymbolEntry('EN-symbols/left_hand.svg', ['手', '手掌', 'hand'],
        status: 'disabled', note: '未找到合适的图片'),
    MulberrySymbolEntry('EN-symbols/nostril.svg', ['鼻子', 'nose']),
    MulberrySymbolEntry('EN-symbols/neck.svg', ['脖子', 'neck']),
    MulberrySymbolEntry('EN-symbols/shoulder.svg', ['肩膀', 'shoulder']),
    MulberrySymbolEntry('EN-symbols/knee.svg', ['膝盖', 'knee']),
    MulberrySymbolEntry('EN-symbols/stomach.svg', ['肚子', '胃', 'stomach']),
    MulberrySymbolEntry('EN-symbols/throat.svg', ['喉咙', '嗓子', 'throat']),
    MulberrySymbolEntry('EN-symbols/tongue.svg', ['舌头', 'tongue']),
    MulberrySymbolEntry('EN-symbols/back.svg', ['后背', '背', 'back']),
    MulberrySymbolEntry('EN-symbols/ankle.svg', ['脚踝', 'ankle']),
    MulberrySymbolEntry('EN-symbols/wrist.svg', ['手腕', 'wrist']),
    MulberrySymbolEntry('EN-symbols/elbow.svg', ['手肘', 'elbow']),

    // ===== 交通 =====
    MulberrySymbolEntry('EN-symbols/car.svg', ['车', '汽车', 'car']),
    MulberrySymbolEntry('EN-symbols/bus.svg', ['公交车', '巴士', 'bus']),
    MulberrySymbolEntry('EN-symbols/train.svg', ['火车', 'train']),
    MulberrySymbolEntry('EN-symbols/taxi.svg', ['出租车', '打车', 'taxi']),
    MulberrySymbolEntry(
        'EN-symbols/aeroplane.svg', ['飞机', 'plane', 'airplane']),
    MulberrySymbolEntry('EN-symbols/boat.svg', ['船', 'boat']),

    // ===== 地点 =====
    MulberrySymbolEntry(
        'EN-symbols/surgery_health_centre.svg', ['医院', 'hospital'],
        status: 'disabled', note: '未找到合适的图片'),
    MulberrySymbolEntry('EN-symbols/shop.svg', ['商店', '超市', 'shop', 'store']),
    MulberrySymbolEntry('EN-symbols/bank.svg', ['银行', 'bank']),
    MulberrySymbolEntry('EN-symbols/church.svg', ['教堂', 'church']),
    MulberrySymbolEntry(
        'EN-symbols/cafe.svg', ['餐厅', '饭店', 'restaurant', 'cafe']),
    MulberrySymbolEntry('EN-symbols/book_shelf.svg', ['图书馆', 'library']),
    MulberrySymbolEntry('EN-symbols/back_garden.svg', ['花园', '院子', 'garden']),
    MulberrySymbolEntry('EN-symbols/cooker.svg', ['厨房', 'kitchen'],
        status: 'disabled', note: '未找到合适的图片'),
    MulberrySymbolEntry(
        'EN-symbols/shower.svg', ['浴室', '洗澡', 'bathroom', 'shower']),
    MulberrySymbolEntry('EN-symbols/headboard.svg', ['卧室', 'bedroom'],
        status: 'disabled', note: '未找到合适的图片'),
    MulberrySymbolEntry('EN-symbols/desk.svg', ['办公室', 'office'],
        status: 'disabled', note: '未找到合适的图片'),
    MulberrySymbolEntry(
        'EN-symbols/travel.svg', ['机场', '旅行', 'airport', 'travel']),

    // ===== 家具/物品 =====
    MulberrySymbolEntry('EN-symbols/door.svg', ['门', 'door']),
    MulberrySymbolEntry('EN-symbols/window.svg', ['窗户', 'window']),
    MulberrySymbolEntry('EN-symbols/table.svg', ['桌子', 'table']),
    MulberrySymbolEntry('EN-symbols/chair.svg', ['椅子', 'chair']),
    MulberrySymbolEntry(
        'EN-symbols/arm_chair.svg', ['沙发', '扶手椅', 'sofa', 'armchair']),
    MulberrySymbolEntry('EN-symbols/mug_2.svg', ['杯子', '马克杯', 'cup', 'mug']),
    MulberrySymbolEntry('EN-symbols/plate.svg', ['盘子', 'plate']),
    MulberrySymbolEntry('EN-symbols/bowl.svg', ['碗', 'bowl']),
    MulberrySymbolEntry('EN-symbols/fork.svg', ['叉子', 'fork']),
    MulberrySymbolEntry('EN-symbols/knife.svg', ['刀', 'knife']),
    MulberrySymbolEntry('EN-symbols/spoon.svg', ['勺子', 'spoon']),
    MulberrySymbolEntry('EN-symbols/glass.svg', ['玻璃杯', 'glass']),
    MulberrySymbolEntry('EN-symbols/lamp.svg', ['灯', '台灯', 'lamp']),
    MulberrySymbolEntry('EN-symbols/clock.svg', ['钟', '时钟', 'clock']),
    MulberrySymbolEntry(
        'EN-symbols/read_book_,_to.svg', ['书', '读书', 'book', 'read'],
        status: 'disabled', note: '未找到合适的图片'),
    MulberrySymbolEntry('EN-symbols/pen.svg', ['笔', 'pen']),
    MulberrySymbolEntry('EN-symbols/paper.svg', ['纸', 'paper']),
    MulberrySymbolEntry('EN-symbols/plastic_bag.svg', ['包', '袋子', 'bag']),
    MulberrySymbolEntry('EN-symbols/cardboard.svg', ['盒子', '箱子', 'box']),
    MulberrySymbolEntry('EN-symbols/jar.svg', ['瓶子', '罐子', 'bottle', 'jar']),
    MulberrySymbolEntry('EN-symbols/mirror.svg', ['镜子', 'mirror']),
    MulberrySymbolEntry('EN-symbols/towel.svg', ['毛巾', 'towel']),
    MulberrySymbolEntry('EN-symbols/soap.svg', ['肥皂', 'soap']),
    MulberrySymbolEntry('EN-symbols/toothbrush.svg', ['牙刷', 'toothbrush']),
    MulberrySymbolEntry('EN-symbols/comb.svg', ['梳子', 'comb']),
    MulberrySymbolEntry('EN-symbols/scissors.svg', ['剪刀', 'scissors']),
    MulberrySymbolEntry('EN-symbols/fridge.svg', ['冰箱', 'fridge']),
    MulberrySymbolEntry('EN-symbols/microwave.svg', ['微波炉', 'microwave']),
    MulberrySymbolEntry('EN-symbols/broom.svg', ['扫帚', 'broom']),
    MulberrySymbolEntry('EN-symbols/newspaper.svg', ['报纸', 'newspaper']),
    MulberrySymbolEntry('EN-symbols/letter.svg', ['信', '信件', 'letter']),
    MulberrySymbolEntry('EN-symbols/card.svg', ['卡片', '卡', 'card']),
    MulberrySymbolEntry('EN-symbols/ring.svg', ['戒指', 'ring']),
    MulberrySymbolEntry('EN-symbols/picture.svg', ['画', '图画', 'picture']),
    MulberrySymbolEntry('EN-symbols/shampoo.svg', ['洗发水', 'shampoo']),
    MulberrySymbolEntry('EN-symbols/razor.svg', ['剃须刀', 'razor']),
    MulberrySymbolEntry('EN-symbols/glue.svg', ['胶水', 'glue']),
    MulberrySymbolEntry('EN-symbols/paint.svg', ['颜料', 'paint'],
        status: 'disabled', note: '未找到合适的图片'),
    MulberrySymbolEntry('EN-symbols/baby.svg', ['婴儿', '宝宝', 'baby']),
    MulberrySymbolEntry('EN-symbols/balloon.svg', ['气球', 'balloon']),
    MulberrySymbolEntry('EN-symbols/candle_2.svg', ['蜡烛', 'candle']),
    MulberrySymbolEntry('EN-symbols/umbrella.svg', ['雨伞', '伞', 'umbrella']),
    MulberrySymbolEntry('EN-symbols/torch.svg', ['手电筒', 'torch']),
    MulberrySymbolEntry('EN-symbols/blanket.svg', ['毯子', '被子', 'blanket']),
    MulberrySymbolEntry('EN-symbols/cupboard.svg', ['柜子', '橱柜', 'cupboard']),
    MulberrySymbolEntry('EN-symbols/bath.svg', ['泡澡', 'bath']),
    MulberrySymbolEntry('EN-symbols/sink.svg', ['水槽', '水池', 'sink']),
    MulberrySymbolEntry('EN-symbols/wardrobe.svg', ['衣柜', 'wardrobe']),
    MulberrySymbolEntry('EN-symbols/curtains.svg', ['窗帘', 'curtain']),
    MulberrySymbolEntry('EN-symbols/rug.svg', ['地毯', '地毯', 'carpet', 'rug']),
    MulberrySymbolEntry('EN-symbols/wallet.svg', ['钱包', 'wallet']),
    MulberrySymbolEntry('EN-symbols/basket.svg', ['篮子', 'basket']),
    MulberrySymbolEntry('EN-symbols/teapot.svg', ['茶壶', 'teapot']),
    MulberrySymbolEntry('EN-symbols/kettle.svg', ['水壶', 'kettle']),
    MulberrySymbolEntry('EN-symbols/toaster.svg', ['烤面包机', 'toaster']),
    MulberrySymbolEntry('EN-symbols/vacuum_cleaner_1.svg', ['吸尘器', 'vacuum']),
    MulberrySymbolEntry('EN-symbols/iron.svg', ['熨斗', 'iron']),
    MulberrySymbolEntry('EN-symbols/thermometer.svg', ['温度计', 'thermometer']),
    MulberrySymbolEntry('EN-symbols/stethoscope.svg', ['听诊器', 'stethoscope']),
    MulberrySymbolEntry('EN-symbols/syringe.svg', ['注射器', '打针', 'syringe']),
    MulberrySymbolEntry(
        'EN-symbols/plaster.svg', ['创可贴', '绷带', 'bandage', 'plaster']),
    MulberrySymbolEntry('EN-symbols/wheelchair.svg', ['轮椅', 'wheelchair']),
    MulberrySymbolEntry('EN-symbols/crutches.svg', ['拐杖', 'crutches']),
    MulberrySymbolEntry('EN-symbols/gloves.svg', ['手套', 'gloves']),
    MulberrySymbolEntry('EN-symbols/boots.svg', ['靴子', 'boots']),
    MulberrySymbolEntry('EN-symbols/slippers.svg', ['拖鞋', 'slippers']),
    MulberrySymbolEntry('EN-symbols/socks.svg', ['袜子', 'socks']),
    MulberrySymbolEntry('EN-symbols/cap.svg', ['帽子', '帽', 'hat', 'cap']),
    MulberrySymbolEntry('EN-symbols/sunglasses.svg', ['太阳镜', 'sunglasses']),
    MulberrySymbolEntry('EN-symbols/watch.svg', ['手表', 'watch']),
    MulberrySymbolEntry('EN-symbols/necklace.svg', ['项链', 'necklace']),
    MulberrySymbolEntry('EN-symbols/earrings.svg', ['耳环', 'earring']),
    MulberrySymbolEntry('EN-symbols/bracelet_1.svg', ['手镯', 'bracelet']),
    MulberrySymbolEntry('EN-symbols/hand_bag.svg', ['手提包', 'handbag']),
    MulberrySymbolEntry('EN-symbols/dinner.svg', ['餐盘', '晚餐', 'dinner']),
    MulberrySymbolEntry('EN-symbols/sandals.svg', ['凉鞋', 'sandals']),
    MulberrySymbolEntry(
        'EN-symbols/laptop.svg', ['电脑', '笔记本', 'computer', 'laptop']),
    MulberrySymbolEntry('EN-symbols/printer.svg', ['打印机', 'printer']),

    // ===== 词语花园扩展训练词 =====
    MulberrySymbolEntry('EN-symbols/apple.svg', ['苹果', 'apple']),
    MulberrySymbolEntry('EN-symbols/apple_juice.svg', ['苹果汁', 'apple juice']),
    MulberrySymbolEntry('EN-symbols/porridge.svg', ['粥', 'porridge']),
    MulberrySymbolEntry('EN-symbols/potato.svg', ['土豆', 'potato']),
    MulberrySymbolEntry('EN-symbols/sweet_potato.svg', ['红薯', 'sweet potato']),
    MulberrySymbolEntry('EN-symbols/carrot.svg', ['胡萝卜', 'carrot']),
    MulberrySymbolEntry('EN-symbols/sweetcorn.svg', ['玉米', 'corn']),
    MulberrySymbolEntry('EN-symbols/tomato.svg', ['西红柿', '番茄', 'tomato']),
    MulberrySymbolEntry('EN-symbols/cabbage.svg', ['白菜', '卷心菜', 'cabbage']),
    MulberrySymbolEntry('EN-symbols/green_beans.svg', ['豆角', 'green beans']),
    MulberrySymbolEntry('EN-symbols/baked_beans.svg', ['豆子', 'beans']),
    MulberrySymbolEntry('EN-symbols/breakfast_1.svg', ['早饭', 'breakfast']),
    MulberrySymbolEntry('EN-symbols/lunch_1.svg', ['午饭', 'lunch']),
    MulberrySymbolEntry('EN-symbols/dinner_hot.svg', ['热饭', 'hot dinner']),
    MulberrySymbolEntry('EN-symbols/drink_hot.svg', ['热饮', 'hot drink']),
    MulberrySymbolEntry('EN-symbols/drink_cold.svg', ['冷饮', 'cold drink']),
    MulberrySymbolEntry('EN-symbols/tea_bag.svg', ['茶包', 'tea bag']),
    MulberrySymbolEntry('EN-symbols/soup_carrot.svg', ['胡萝卜汤', 'carrot soup']),
    MulberrySymbolEntry('EN-symbols/steak.svg', ['牛排', 'steak']),
    MulberrySymbolEntry('EN-symbols/bread_roll.svg', ['面包卷', 'bread roll']),
    MulberrySymbolEntry('EN-symbols/hot_dog.svg', ['热狗', 'hot dog']),
    MulberrySymbolEntry('EN-symbols/ready_meal.svg', ['盒饭', 'ready meal']),
    MulberrySymbolEntry(
        'EN-symbols/takeaway_chinese.svg', ['中餐外卖', 'takeaway']),
    MulberrySymbolEntry('EN-symbols/salad_plate.svg', ['一盘沙拉', 'salad plate']),
    MulberrySymbolEntry('EN-symbols/sit_,_to.svg', ['坐下', 'sit']),
    MulberrySymbolEntry('EN-symbols/stand_,_to.svg', ['站起来', 'stand']),
    MulberrySymbolEntry('EN-symbols/wait_,_to.svg', ['等一下', 'wait']),
    MulberrySymbolEntry('EN-symbols/open_door_,_to.svg', ['开门', 'open door']),
    MulberrySymbolEntry('EN-symbols/close_door_,_to.svg', ['关门', 'close door']),
    MulberrySymbolEntry(
        'EN-symbols/turn_on_light_switch_,_to.svg', ['开灯', 'turn on light']),
    MulberrySymbolEntry(
        'EN-symbols/turn_off_light_switch_,_to.svg', ['关灯', 'turn off light']),
    MulberrySymbolEntry('EN-symbols/wash_hands_,_to.svg', ['洗手', 'wash hands']),
    MulberrySymbolEntry('EN-symbols/wash_face_,_to.svg', ['洗脸', 'wash face']),
    MulberrySymbolEntry(
        'EN-symbols/brush_teeth_,_to.svg', ['刷牙', 'brush teeth']),
    MulberrySymbolEntry(
        'EN-symbols/get_dressed_,_to.svg', ['穿衣服', 'get dressed']),
    MulberrySymbolEntry('EN-symbols/undress_,_to.svg', ['脱衣服', 'undress']),
    MulberrySymbolEntry(
        'EN-symbols/put_on_coat_,_to.svg', ['穿外套', 'put on coat']),
    MulberrySymbolEntry(
        'EN-symbols/take_off_cap_,_to.svg', ['摘帽子', 'take off cap']),
    MulberrySymbolEntry('EN-symbols/make_the_bed_,_to.svg', ['铺床', 'make bed']),
    MulberrySymbolEntry('EN-symbols/clean_room.svg', ['打扫房间', 'clean room']),
    MulberrySymbolEntry(
        'EN-symbols/wash_clothes_,_to.svg', ['洗衣服', 'wash clothes']),
    MulberrySymbolEntry(
        'EN-symbols/fold_clothes_,_to.svg', ['叠衣服', 'fold clothes']),
    MulberrySymbolEntry('EN-symbols/cook_,_to.svg', ['做饭', 'cook']),
    MulberrySymbolEntry('EN-symbols/call_out_,_to.svg', ['呼叫', 'call out']),
    MulberrySymbolEntry(
        'EN-symbols/telephone_mobile_,_to.svg', ['打手机', 'call mobile']),
    MulberrySymbolEntry(
        'EN-symbols/take_picture_,_to.svg', ['拍照片', 'take picture']),
    MulberrySymbolEntry('EN-symbols/write_,_to.svg', ['写字', 'write']),
    MulberrySymbolEntry('EN-symbols/read_,_to.svg', ['阅读', 'read']),
    MulberrySymbolEntry('EN-symbols/point_,_to.svg', ['指一指', 'point']),
    MulberrySymbolEntry('EN-symbols/give_,_to.svg', ['给我', 'give']),
    MulberrySymbolEntry('EN-symbols/bring_,_to.svg', ['拿过来', 'bring']),
    MulberrySymbolEntry('EN-symbols/take_,_to.svg', ['拿走', 'take']),
    MulberrySymbolEntry('EN-symbols/push_,_to.svg', ['推', 'push']),
    MulberrySymbolEntry('EN-symbols/pull_,_to.svg', ['拉', 'pull']),
    MulberrySymbolEntry(
        'EN-symbols/walk_upstairs_,_to.svg', ['上楼', 'upstairs']),
    MulberrySymbolEntry(
        'EN-symbols/walk_downstairs_,_to.svg', ['下楼', 'downstairs']),
    MulberrySymbolEntry('EN-symbols/queue_,_to.svg', ['排队', 'queue']),
    MulberrySymbolEntry('EN-symbols/open_shop.svg', ['开门营业', 'open shop']),
    MulberrySymbolEntry('EN-symbols/cash_point.svg', ['取钱', 'cash machine']),
    MulberrySymbolEntry(
        'EN-symbols/remote_control.svg', ['遥控器', 'remote control']),
    MulberrySymbolEntry('EN-symbols/charger_electric.svg', ['充电器', 'charger']),
    MulberrySymbolEntry(
        'EN-symbols/washing_machine.svg', ['洗衣机', 'washing machine']),
    MulberrySymbolEntry('EN-symbols/dishwasher.svg', ['洗碗机', 'dishwasher']),
    MulberrySymbolEntry(
        'EN-symbols/medicine_cabinet.svg', ['药箱', 'medicine cabinet']),
    MulberrySymbolEntry(
        'EN-symbols/first_aid_box.svg', ['急救箱', 'first aid box']),
    MulberrySymbolEntry('EN-symbols/hearing_aid_1.svg', ['助听器', 'hearing aid']),
    MulberrySymbolEntry(
        'EN-symbols/blood_pressure.svg', ['血压', 'blood pressure']),
    MulberrySymbolEntry('EN-symbols/ambulance.svg', ['救护车', 'ambulance']),
    MulberrySymbolEntry('EN-symbols/lightbulb.svg', ['灯泡', 'light bulb']),
    MulberrySymbolEntry(
        'EN-symbols/ceiling_light.svg', ['顶灯', 'ceiling light']),
    MulberrySymbolEntry('EN-symbols/single_bed.svg', ['床', 'bed']),
    MulberrySymbolEntry('EN-symbols/coffee_table.svg', ['茶几', 'coffee table']),
    MulberrySymbolEntry('EN-symbols/bookcase.svg', ['书柜', 'bookcase']),
    MulberrySymbolEntry('EN-symbols/clothes_hanger.svg', ['衣架', 'hanger']),
    MulberrySymbolEntry('EN-symbols/pencil.svg', ['铅笔', 'pencil']),
    MulberrySymbolEntry('EN-symbols/notebook.svg', ['笔记本', 'notebook']),
    MulberrySymbolEntry('EN-symbols/computer_keyboard.svg', ['键盘', 'keyboard']),
    MulberrySymbolEntry('EN-symbols/computer_mouse_1.svg', ['鼠标', 'mouse']),
    MulberrySymbolEntry('EN-symbols/headphones.svg', ['耳机', 'headphones']),
    MulberrySymbolEntry(
        'EN-symbols/mobile_phone_text_message.svg', ['短信', 'text message']),
    MulberrySymbolEntry('EN-symbols/bank_card.svg', ['银行卡', 'bank card']),
    MulberrySymbolEntry('EN-symbols/money.svg', ['现金', 'money']),
    MulberrySymbolEntry('EN-symbols/personal_passport.svg', ['护照', 'passport']),
    MulberrySymbolEntry('EN-symbols/calendar.svg', ['日历', 'calendar']),
    MulberrySymbolEntry('EN-symbols/morning.svg', ['早上', 'morning']),
    MulberrySymbolEntry('EN-symbols/night.svg', ['晚上', 'night']),
    MulberrySymbolEntry('EN-symbols/today.svg', ['今天', 'today']),
    MulberrySymbolEntry('EN-symbols/tomorrow.svg', ['明天', 'tomorrow']),
    MulberrySymbolEntry('EN-symbols/lift.svg', ['电梯', 'lift']),
    MulberrySymbolEntry('EN-symbols/stairs.svg', ['楼梯', 'stairs']),
    MulberrySymbolEntry(
        'EN-symbols/surgery_health_centre.svg', ['医院', 'hospital']),
    MulberrySymbolEntry('EN-symbols/class_room.svg', ['教室', 'classroom']),
    MulberrySymbolEntry('EN-symbols/office_block.svg', ['办公楼', 'office block']),
    MulberrySymbolEntry('EN-symbols/room.svg', ['房间', 'room']),
    MulberrySymbolEntry(
        'EN-symbols/disabled_toilet.svg', ['无障碍厕所', 'accessible toilet']),
    MulberrySymbolEntry('EN-symbols/dad_parent.svg', ['爸爸', 'dad']),
    MulberrySymbolEntry('EN-symbols/daughter.svg', ['女儿', 'daughter']),
    MulberrySymbolEntry('EN-symbols/son.svg', ['儿子', 'son']),
    MulberrySymbolEntry('EN-symbols/grandfather.svg', ['爷爷', 'grandfather']),
    MulberrySymbolEntry('EN-symbols/grandmother.svg', ['奶奶', 'grandmother']),

    // ===== 词语花园扩展训练词 2 =====
    MulberrySymbolEntry('EN-symbols/plum.svg', ['李子', 'plum']),
    MulberrySymbolEntry('EN-symbols/apricot.svg', ['杏', 'apricot']),
    MulberrySymbolEntry('EN-symbols/berry.svg', ['浆果', 'berry']),
    MulberrySymbolEntry('EN-symbols/blackberry.svg', ['黑莓', 'blackberry']),
    MulberrySymbolEntry('EN-symbols/cranberries.svg', ['蔓越莓', 'cranberries']),
    MulberrySymbolEntry('EN-symbols/kiwi.svg', ['猕猴桃', 'kiwi']),
    MulberrySymbolEntry('EN-symbols/melon.svg', ['甜瓜', 'melon']),
    MulberrySymbolEntry('EN-symbols/cucumber.svg', ['黄瓜', 'cucumber']),
    MulberrySymbolEntry('EN-symbols/onion.svg', ['洋葱', 'onion']),
    MulberrySymbolEntry('EN-symbols/garlic.svg', ['大蒜', 'garlic']),
    MulberrySymbolEntry('EN-symbols/peas.svg', ['豌豆', 'peas']),
    MulberrySymbolEntry('EN-symbols/mushroom.svg', ['蘑菇', 'mushroom']),
    MulberrySymbolEntry('EN-symbols/celery.svg', ['芹菜', 'celery']),
    MulberrySymbolEntry('EN-symbols/lettuce.svg', ['生菜', 'lettuce']),
    MulberrySymbolEntry('EN-symbols/broccoli.svg', ['西兰花', 'broccoli']),
    MulberrySymbolEntry('EN-symbols/cauliflower.svg', ['花菜', 'cauliflower']),
    MulberrySymbolEntry('EN-symbols/pumpkin.svg', ['南瓜', 'pumpkin']),
    MulberrySymbolEntry('EN-symbols/turnip.svg', ['白萝卜', 'turnip']),
    MulberrySymbolEntry('EN-symbols/yogurt.svg', ['酸奶', 'yogurt']),
    MulberrySymbolEntry('EN-symbols/cereal_bowl.svg', ['麦片', 'cereal']),
    MulberrySymbolEntry('EN-symbols/cornflakes.svg', ['玉米片', 'cornflakes']),
    MulberrySymbolEntry('EN-symbols/toast.svg', ['吐司', 'toast']),
    MulberrySymbolEntry('EN-symbols/jam.svg', ['果酱', 'jam']),
    MulberrySymbolEntry('EN-symbols/honey.svg', ['蜂蜜', 'honey']),
    MulberrySymbolEntry('EN-symbols/pasta.svg', ['意面', 'pasta']),
    MulberrySymbolEntry('EN-symbols/spaghetti.svg', ['意大利面', 'spaghetti']),
    MulberrySymbolEntry('EN-symbols/chips.svg', ['薯条', 'chips']),
    MulberrySymbolEntry(
        'EN-symbols/chocolate_bar.svg', ['巧克力棒', 'chocolate bar']),
    MulberrySymbolEntry('EN-symbols/milkshake_strawberry.svg',
        ['草莓奶昔', 'strawberry milkshake']),
    MulberrySymbolEntry(
        'EN-symbols/cranberry_juice.svg', ['蔓越莓汁', 'cranberry juice']),
    MulberrySymbolEntry('EN-symbols/stomach_ache.svg', ['肚子疼', 'stomach ache']),
    MulberrySymbolEntry('EN-symbols/toothache.svg', ['牙疼', 'toothache']),
    MulberrySymbolEntry('EN-symbols/vomit_,_to.svg', ['呕吐', 'vomit']),
    MulberrySymbolEntry('EN-symbols/tablets.svg', ['药片', 'tablets']),
    MulberrySymbolEntry(
        'EN-symbols/tablet_blister_pack.svg', ['药板', 'blister pack']),
    MulberrySymbolEntry('EN-symbols/oxygen_mask.svg', ['氧气面罩', 'oxygen mask']),
    MulberrySymbolEntry(
        'EN-symbols/physio_therapist_1a.svg', ['康复治疗师', 'physio therapist']),
    MulberrySymbolEntry('EN-symbols/speech_language_therapist_1a.svg',
        ['言语治疗师', 'speech therapist']),
    MulberrySymbolEntry('EN-symbols/occupational_therapist_1a.svg',
        ['作业治疗师', 'occupational therapist']),
    MulberrySymbolEntry('EN-symbols/healthy.svg', ['健康', 'healthy']),
    MulberrySymbolEntry('EN-symbols/liquid_soap.svg', ['洗手液', 'liquid soap']),
    MulberrySymbolEntry('EN-symbols/toothpaste.svg', ['牙膏', 'toothpaste']),
    MulberrySymbolEntry('EN-symbols/tissues.svg', ['纸巾', 'tissues']),
    MulberrySymbolEntry('EN-symbols/toilet_roll.svg', ['卫生纸', 'toilet roll']),
    MulberrySymbolEntry('EN-symbols/shower_gel.svg', ['沐浴露', 'shower gel']),
    MulberrySymbolEntry('EN-symbols/hairdryer.svg', ['吹风机', 'hairdryer']),
    MulberrySymbolEntry(
        'EN-symbols/nail_clippers.svg', ['指甲剪', 'nail clippers']),
    MulberrySymbolEntry('EN-symbols/nail_file.svg', ['指甲锉', 'nail file']),
    MulberrySymbolEntry(
        'EN-symbols/razor_electric.svg', ['电动剃须刀', 'electric razor']),
    MulberrySymbolEntry('EN-symbols/mouthwash.svg', ['漱口水', 'mouthwash']),
    MulberrySymbolEntry('EN-symbols/bath_mat.svg', ['浴室垫', 'bath mat']),
    MulberrySymbolEntry('EN-symbols/bathe_,_to.svg', ['洗澡', 'bathe']),
    MulberrySymbolEntry(
        'EN-symbols/flush_toilet_,_to.svg', ['冲厕所', 'flush toilet']),
    MulberrySymbolEntry(
        'EN-symbols/put_in_bin_,_to.svg', ['扔垃圾', 'put in bin']),
    MulberrySymbolEntry(
        'EN-symbols/clip_nails_,_to.svg', ['剪指甲', 'clip nails']),
    MulberrySymbolEntry(
        'EN-symbols/shave_with_razor_,_to.svg', ['刮胡子', 'shave']),
    MulberrySymbolEntry(
        'EN-symbols/look_in_mirror_,_to.svg', ['照镜子', 'look in mirror']),
    MulberrySymbolEntry('EN-symbols/clean_dishes.svg', ['洗碗', 'clean dishes']),
    MulberrySymbolEntry(
        'EN-symbols/clean_window_,_to.svg', ['擦窗户', 'clean window']),
    MulberrySymbolEntry(
        'EN-symbols/water_plants_,_to.svg', ['浇花', 'water plants']),
    MulberrySymbolEntry(
        'EN-symbols/return_book_,_to.svg', ['还书', 'return book']),
    MulberrySymbolEntry(
        'EN-symbols/use_computer_,_to.svg', ['用电脑', 'use computer']),
    MulberrySymbolEntry(
        'EN-symbols/sit_at_computer_,_to.svg', ['坐在电脑前', 'sit at computer']),
    MulberrySymbolEntry(
        'EN-symbols/carry_books_,_to.svg', ['拿书', 'carry books']),
    MulberrySymbolEntry('EN-symbols/hang_coat_,_to.svg', ['挂外套', 'hang coat']),
    MulberrySymbolEntry(
        'EN-symbols/change_clothes_,_to.svg', ['换衣服', 'change clothes']),
    MulberrySymbolEntry('EN-symbols/open_tin_,_to.svg', ['开罐头', 'open tin']),
    MulberrySymbolEntry(
        'EN-symbols/ring_doorbell_,_to.svg', ['按门铃', 'ring doorbell']),
    MulberrySymbolEntry('EN-symbols/visit_,_to.svg', ['拜访', 'visit']),
    MulberrySymbolEntry(
        'EN-symbols/take_care_of_,_to.svg', ['照顾', 'take care']),
    MulberrySymbolEntry('EN-symbols/spill_,_to.svg', ['洒了', 'spill']),
    MulberrySymbolEntry('EN-symbols/sneeze_cold.svg', ['打喷嚏', 'sneeze']),
    MulberrySymbolEntry('EN-symbols/chair_dining.svg', ['餐椅', 'dining chair']),
    MulberrySymbolEntry('EN-symbols/dining_table.svg', ['餐桌', 'dining table']),
    MulberrySymbolEntry('EN-symbols/chest_of_drawers.svg', ['抽屉柜', 'drawers']),
    MulberrySymbolEntry('EN-symbols/dresser.svg', ['梳妆台', 'dresser']),
    MulberrySymbolEntry('EN-symbols/double_bed.svg', ['双人床', 'double bed']),
    MulberrySymbolEntry('EN-symbols/bunk_beds.svg', ['上下床', 'bunk beds']),
    MulberrySymbolEntry('EN-symbols/recycle_bin.svg', ['回收桶', 'recycle bin']),
    MulberrySymbolEntry('EN-symbols/waste_paper_bin.svg', ['垃圾桶', 'waste bin']),
    MulberrySymbolEntry('EN-symbols/tea_towel.svg', ['擦碗布', 'tea towel']),
    MulberrySymbolEntry('EN-symbols/art_room.svg', ['美术室', 'art room']),
    MulberrySymbolEntry('EN-symbols/music_room.svg', ['音乐室', 'music room']),
    MulberrySymbolEntry(
        'EN-symbols/science_room.svg', ['科学教室', 'science room']),
    MulberrySymbolEntry('EN-symbols/sensory_room.svg', ['感统室', 'sensory room']),
    MulberrySymbolEntry('EN-symbols/inside_room.svg', ['室内', 'inside room']),
    MulberrySymbolEntry('EN-symbols/messy_room.svg', ['乱房间', 'messy room']),
    MulberrySymbolEntry('EN-symbols/closed_shop.svg', ['商店关门', 'closed shop']),
    MulberrySymbolEntry('EN-symbols/shop_2.svg', ['商场', 'shopping mall']),
    MulberrySymbolEntry(
        'EN-symbols/grandparents.svg', ['爷爷奶奶', 'grandparents']),
    MulberrySymbolEntry('EN-symbols/old_person_1.svg', ['老人', 'older person']),
    MulberrySymbolEntry('EN-symbols/visitor_1a.svg', ['访客', 'visitor']),
    MulberrySymbolEntry(
        'EN-symbols/care_assistant_1a.svg', ['护工', 'care assistant']),
    MulberrySymbolEntry('EN-symbols/police_1a.svg', ['警察', 'police']),
    MulberrySymbolEntry(
        'EN-symbols/taxi_driver_1a.svg', ['出租车司机', 'taxi driver']),
    MulberrySymbolEntry(
        'EN-symbols/post_person_1a.svg', ['邮递员', 'post person']),
    MulberrySymbolEntry('EN-symbols/confused_man.svg', ['困惑', 'confused']),
    MulberrySymbolEntry('EN-symbols/excited_man.svg', ['兴奋', 'excited']),
    MulberrySymbolEntry('EN-symbols/serene_man.svg', ['平静', 'calm']),
    MulberrySymbolEntry('EN-symbols/surprised_man.svg', ['惊讶', 'surprised']),
  ];
}

class MulberrySymbolEntry {
  const MulberrySymbolEntry(
    this.asset,
    this.keywords, {
    this.category = '未分类',
    this.status = 'review',
    this.confidence = 'medium',
    this.source = 'manual',
    this.alternatives = const [],
    this.note = '',
  });

  final String asset;
  final List<String> keywords;
  final String category;
  final String status;
  final String confidence;
  final String source;
  final List<String> alternatives;
  final String note;

  String get primaryText => keywords.isEmpty ? asset : keywords.first;

  bool matches(String normalizedText) {
    for (final keyword in keywords) {
      final normalizedKeyword = MulberrySymbolResolver.normalize(keyword);
      if (MulberrySymbolResolver.normalizedTextEquals(
        normalizedText,
        normalizedKeyword,
      )) {
        return true;
      }
    }
    return keywords.any((keyword) {
      final normalizedKeyword = MulberrySymbolResolver.normalize(keyword);
      return normalizedKeyword.isNotEmpty &&
          normalizedText.contains(normalizedKeyword);
    });
  }
}
