import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../common.dart';
import 'home_page.dart';

class AdbPage extends StatelessWidget implements PageShape {
  @override
  final title = "ADB";

  @override
  final icon = const Icon(Icons.adb);

  @override
  final appBarActions = const <Widget>[];

  const AdbPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return SizedBox.expand(
      child: ColoredBox(
        color: Theme.of(context).scaffoldBackgroundColor,
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              _AdbCard(
                title: "ADB",
                titleIcon: const Icon(Icons.adb, color: MyTheme.accent),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "\u540e\u7eed\u65e0\u7ebf\u8c03\u8bd5\u3001\u914d\u5bf9\u72b6\u6001\u548c\u8fdc\u7a0b\u547d\u4ee4\u7ec4\u4ef6\u90fd\u4f1a\u653e\u5728\u8fd9\u91cc\u3002",
                      style: TextStyle(color: MyTheme.darkGray),
                    ).marginOnly(bottom: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.play_arrow),
                        onPressed: () {},
                        label: const Text("\u542f\u52a8\u670d\u52a1"),
                      ),
                    ),
                  ],
                ),
              ),
              _AdbCard(
                title: "\u81ea\u52a8\u5316\u65e0\u7ebf\u8c03\u8bd5",
                titleIcon:
                    const Icon(Icons.settings_remote, color: MyTheme.accent),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "\u540e\u7eed\u7528\u4e8e\u57fa\u4e8e\u65e0\u969c\u788d\u534a\u81ea\u52a8\u6253\u5f00 Android \u65e0\u7ebf\u8c03\u8bd5\u5f00\u5173\u3002",
                      style: TextStyle(color: MyTheme.darkGray),
                    ).marginOnly(bottom: 8),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.settings_remote),
                        onPressed: () {},
                        label: const Text("\u6253\u5f00\u8c03\u8bd5"),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdbCard extends StatelessWidget {
  const _AdbCard({
    Key? key,
    required this.title,
    required this.child,
    this.titleIcon,
  }) : super(key: key);

  final String title;
  final Widget child;
  final Widget? titleIcon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.maxFinite,
      child: Card(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(13),
        ),
        margin: const EdgeInsets.fromLTRB(12.0, 10.0, 12.0, 0),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 15.0, horizontal: 20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 5, 0, 8),
                child: Row(
                  children: [
                    if (titleIcon != null) titleIcon!.marginOnly(right: 10),
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleLarge?.merge(
                              const TextStyle(fontWeight: FontWeight.bold),
                            ),
                      ),
                    ),
                  ],
                ),
              ),
              child,
            ],
          ),
        ),
      ),
    );
  }
}
