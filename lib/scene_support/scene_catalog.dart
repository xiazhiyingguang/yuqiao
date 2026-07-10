import 'package:flutter/material.dart';

import '../location_recommendation.dart';
import 'scene_pack.dart';

abstract final class SceneCatalog {
  static const ScenePack hospital = ScenePack(
    id: 'hospital_visit',
    title: '问诊辅助',
    promptTitle: '你可能在医院，要打开问诊辅助吗？',
    description: '把症状、听不懂、下一步确认放在一个低负担流程里。',
    placeTypes: [PlaceTypeCatalog.hospital],
    icon: Icons.local_hospital_rounded,
    color: Color(0xFF4E8FD8),
    kind: ScenePackKind.hospitalVisit,
    quickActions: [
      SceneQuickAction(
        text: '请医生慢一点说',
        icon: Icons.speed_rounded,
        helper: '听不清或反应慢时用',
      ),
      SceneQuickAction(
        text: '请写下来',
        icon: Icons.edit_note_rounded,
        helper: '把医嘱留成文字',
      ),
      SceneQuickAction(
        text: '我没听懂，请再说一次',
        icon: Icons.hearing_disabled_rounded,
        helper: '需要重复说明',
      ),
      SceneQuickAction(
        text: '请告诉我下一步要做什么',
        icon: Icons.route_rounded,
        helper: '确认检查、取药或复诊',
      ),
      SceneQuickAction(
        text: '我需要联系家人',
        icon: Icons.contact_phone_rounded,
        helper: '需要陪同或确认决定',
      ),
      SceneQuickAction(
        text: '请问这个药怎么吃',
        icon: Icons.medical_services_rounded,
        helper: '确认用药方法',
      ),
    ],
    partnerTips: [
      '请一次只说一件事',
      '请给我时间回答',
      '可以写下来或让我指给你看',
    ],
  );

  static const ScenePack pharmacy = ScenePack(
    id: 'pharmacy_buy_medicine',
    title: '买药辅助',
    promptTitle: '你可能在药店，要打开买药辅助吗？',
    description: '围绕买药、用法、过敏和付款，快速把需求说清楚。',
    placeTypes: [PlaceTypeCatalog.pharmacy],
    icon: Icons.medication_rounded,
    color: Color(0xFF6EA8A1),
    kind: ScenePackKind.quickExpressions,
    quickActions: [
      SceneQuickAction(
        text: '我要买这个药',
        icon: Icons.medication_rounded,
        helper: '给店员看药名或包装',
      ),
      SceneQuickAction(
        text: '这个药怎么吃',
        icon: Icons.help_rounded,
        helper: '询问剂量和次数',
      ),
      SceneQuickAction(
        text: '请把用法写下来',
        icon: Icons.edit_note_rounded,
        helper: '方便回家查看',
      ),
      SceneQuickAction(
        text: '我对这个药过敏',
        icon: Icons.warning_rounded,
        helper: '避免拿错药',
      ),
      SceneQuickAction(
        text: '这个多少钱',
        icon: Icons.payments_rounded,
        helper: '确认价格',
      ),
      SceneQuickAction(
        text: '请帮我联系家人确认一下',
        icon: Icons.contact_phone_rounded,
        helper: '需要家属判断',
      ),
    ],
  );

  static const ScenePack supermarket = ScenePack(
    id: 'shopping_help',
    title: '购物辅助',
    promptTitle: '你可能在购物场所，要打开购物辅助吗？',
    description: '把找东西、询价、结账、求助这些高频购物表达放在一起。',
    placeTypes: [
      PlaceTypeCatalog.supermarket,
      PlaceTypeCatalog.convenienceStore,
      PlaceTypeCatalog.shoppingMall,
    ],
    icon: Icons.shopping_cart_rounded,
    color: Color(0xFFD7A86E),
    kind: ScenePackKind.quickExpressions,
    quickActions: [
      SceneQuickAction(
        text: '我要这个',
        icon: Icons.touch_app_rounded,
        helper: '指着商品时用',
      ),
      SceneQuickAction(
        text: '我找不到这个东西',
        icon: Icons.search_rounded,
        helper: '给店员看图片或文字',
      ),
      SceneQuickAction(
        text: '这个多少钱',
        icon: Icons.payments_rounded,
        helper: '询问价格',
      ),
      SceneQuickAction(
        text: '我要结账',
        icon: Icons.shopping_bag_rounded,
        helper: '到收银台时用',
      ),
      SceneQuickAction(
        text: '请帮我拿一下',
        icon: Icons.volunteer_activism_rounded,
        helper: '货架太高或不方便拿',
      ),
      SceneQuickAction(
        text: '请给我一个袋子',
        icon: Icons.shopping_bag_outlined,
        helper: '结账后需要袋子',
      ),
    ],
  );

  static const ScenePack transport = ScenePack(
    id: 'transport_help',
    title: '出行辅助',
    promptTitle: '你可能在交通地点，要打开出行辅助吗？',
    description: '用于问路、下车、听不懂和联系家人，降低出行沟通压力。',
    placeTypes: [PlaceTypeCatalog.transport],
    icon: Icons.directions_bus_rounded,
    color: Color(0xFF8D9DC2),
    kind: ScenePackKind.quickExpressions,
    quickActions: [
      SceneQuickAction(
        text: '我要去这里',
        icon: Icons.place_rounded,
        helper: '展示目的地时用',
      ),
      SceneQuickAction(
        text: '请慢一点说',
        icon: Icons.speed_rounded,
        helper: '询问路线时用',
      ),
      SceneQuickAction(
        text: '我听不懂，请指给我看',
        icon: Icons.hearing_disabled_rounded,
        helper: '需要视觉提示',
      ),
      SceneQuickAction(
        text: '请写下来',
        icon: Icons.edit_note_rounded,
        helper: '记录站名或出口',
      ),
      SceneQuickAction(
        text: '请告诉我在哪里下车',
        icon: Icons.transfer_within_a_station_rounded,
        helper: '公交、地铁、打车都可用',
      ),
      SceneQuickAction(
        text: '请帮我联系家人',
        icon: Icons.contact_phone_rounded,
        helper: '迷路或不确定时用',
      ),
    ],
  );

  static const ScenePack home = ScenePack(
    id: 'home_expression',
    title: '居家表达',
    promptTitle: '你可能在家附近，要打开居家表达吗？',
    description: '把喝水、休息、不舒服、解释意图这些日常高频表达放在最前面。',
    placeTypes: [PlaceTypeCatalog.home, PlaceTypeCatalog.residential],
    icon: Icons.home_rounded,
    color: Color(0xFFD08C60),
    kind: ScenePackKind.quickExpressions,
    quickActions: [
      SceneQuickAction(
        text: '我想休息一下',
        icon: Icons.hotel_rounded,
        helper: '需要安静或暂停',
      ),
      SceneQuickAction(
        text: '我想喝水',
        icon: Icons.local_drink_rounded,
        helper: '日常高频需求',
      ),
      SceneQuickAction(
        text: '我不舒服',
        icon: Icons.favorite_rounded,
        helper: '身体不适时用',
      ),
      SceneQuickAction(
        text: '请等我一下',
        icon: Icons.hourglass_bottom_rounded,
        helper: '需要更多反应时间',
      ),
      SceneQuickAction(
        text: '我不是这个意思',
        icon: Icons.cancel_rounded,
        helper: '纠正误解',
      ),
      SceneQuickAction(
        text: '请帮我联系家人',
        icon: Icons.contact_phone_rounded,
        helper: '需要协助时用',
      ),
    ],
  );

  static const ScenePack rehab = ScenePack(
    id: 'rehab_communication',
    title: '训练沟通',
    promptTitle: '你可能在康复中心，要打开训练沟通吗？',
    description: '帮助用户在训练中表达疼痛、疲劳、继续或需要示范。',
    placeTypes: [PlaceTypeCatalog.rehabilitationCenter],
    icon: Icons.fitness_center_rounded,
    color: Color(0xFF7A9E9F),
    kind: ScenePackKind.quickExpressions,
    quickActions: [
      SceneQuickAction(
        text: '我想休息一下',
        icon: Icons.hotel_rounded,
        helper: '训练中需要暂停',
      ),
      SceneQuickAction(
        text: '这个动作有点疼',
        icon: Icons.healing_rounded,
        helper: '提醒治疗师调整',
      ),
      SceneQuickAction(
        text: '请慢一点',
        icon: Icons.speed_rounded,
        helper: '节奏太快时用',
      ),
      SceneQuickAction(
        text: '我可以继续',
        icon: Icons.check_circle_rounded,
        helper: '确认继续训练',
      ),
      SceneQuickAction(
        text: '请再示范一次',
        icon: Icons.replay_rounded,
        helper: '看不懂动作时用',
      ),
      SceneQuickAction(
        text: '今天训练到这里',
        icon: Icons.done_all_rounded,
        helper: '疲劳或结束训练',
      ),
    ],
  );

  static const List<ScenePack> packs = [
    hospital,
    pharmacy,
    supermarket,
    transport,
    home,
    rehab,
  ];

  static ScenePack? forPlaceType(String? type) {
    final normalized = PlaceTypeCatalog.normalize(type);
    for (final pack in packs) {
      if (pack.placeTypes.contains(normalized)) return pack;
    }
    return null;
  }
}
