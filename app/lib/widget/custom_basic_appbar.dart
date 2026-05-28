import 'dart:io';
import 'dart:ui';

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/util/native/platform_check.dart';

class CustomBackButton extends StatelessWidget {
  final Color? color;

  const CustomBackButton({super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    return IconButton(
      icon: Icon(
        isRtl ? Icons.arrow_forward_ios_rounded : Icons.arrow_back_ios_new_rounded,
        color: color ?? IconTheme.of(context).color,
      ),
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      onPressed: () async {
        await Navigator.maybePop(context);
      },
    );
  }
}

PreferredSizeWidget basicLocalSendAppbar(
  String title, {
  List<Widget> actions = const [],
}) {
  // Keeps the native draggable macOS header while moving navigation to the trailing edge.
  if (checkPlatform([TargetPlatform.macOS])) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(kToolbarHeight),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: 20.0,
            sigmaY: 20.0,
          ),
          child: MoveWindow(
            child: Container(
              color: Colors.transparent,
              height: kToolbarHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (!kIsWeb && Platform.isMacOS) const SizedBox(width: 60),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 100,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ...actions,
                      const CustomBackButton(),
                    ],
                  ),
                  const SizedBox(width: 60),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  return AppBar(
    title: Text(title),
    actions: [
      ...actions,
      const CustomBackButton(),
    ],
  );
}
