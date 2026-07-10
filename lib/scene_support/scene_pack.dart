import 'package:flutter/material.dart';

enum ScenePackKind { hospitalVisit, quickExpressions }

class ScenePack {
  const ScenePack({
    required this.id,
    required this.title,
    required this.promptTitle,
    required this.description,
    required this.placeTypes,
    required this.icon,
    required this.color,
    required this.kind,
    required this.quickActions,
    this.partnerTips = const [],
  });

  final String id;
  final String title;
  final String promptTitle;
  final String description;
  final List<String> placeTypes;
  final IconData icon;
  final Color color;
  final ScenePackKind kind;
  final List<SceneQuickAction> quickActions;
  final List<String> partnerTips;
}

class SceneQuickAction {
  const SceneQuickAction({
    required this.text,
    required this.icon,
    this.helper,
  });

  final String text;
  final IconData icon;
  final String? helper;
}
