import 'dart:io';
import 'dart:ui';

import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/native/platform_check.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

const double localSendAppBarHeight = 35;
const double _macTrafficLightPadding = 72;

ButtonStyle compactAppBarButtonStyle() {
  return TextButton.styleFrom(
    minimumSize: const Size(48, localSendAppBarHeight),
    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
    visualDensity: VisualDensity.compact,
    padding: const EdgeInsets.symmetric(horizontal: 10),
  );
}

class CustomBackButton extends StatelessWidget {
  final Color? color;

  const CustomBackButton({super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    return IconButton(
      constraints: const BoxConstraints.tightFor(
        width: localSendAppBarHeight,
        height: localSendAppBarHeight,
      ),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
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

class CustomBackTextButton extends StatelessWidget {
  const CustomBackTextButton({super.key});

  @override
  Widget build(BuildContext context) {
    return TextButton(
      style: compactAppBarButtonStyle(),
      onPressed: () async {
        await Navigator.maybePop(context);
      },
      child: const Text('返回'),
    );
  }
}

PreferredSizeWidget basicLocalSendAppbar(
  String title, {
  List<Widget> actions = const [],
}) {
  final isWindows = checkPlatform([TargetPlatform.windows]);
  final windowsLeftActionBar = isWindows ? Routerino.context.ref.read(settingsProvider).windowsLeftActionBar : false;
  // Keeps the native draggable macOS header while moving navigation to the trailing edge.
  if (checkPlatform([TargetPlatform.macOS])) {
    return PreferredSize(
      preferredSize: const Size.fromHeight(localSendAppBarHeight),
      child: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20.0, sigmaY: 20.0),
          child: MoveWindow(
            child: Container(
              color: Colors.transparent,
              height: localSendAppBarHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (!kIsWeb && Platform.isMacOS) const SizedBox(width: _macTrafficLightPadding),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Center(
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [...actions, const CustomBackTextButton()],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  return AppBar(
    toolbarHeight: localSendAppBarHeight,
    automaticallyImplyLeading: false,
    leadingWidth: isWindows && windowsLeftActionBar ? null : 0,
    leading: isWindows && windowsLeftActionBar
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: const [CustomBackTextButton()],
          )
        : null,
    title: isWindows && windowsLeftActionBar
        ? Align(
            alignment: Alignment.centerRight,
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 15),
            ),
          )
        : Text(
            title,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15),
          ),
    actions: isWindows && windowsLeftActionBar ? [...actions] : [...actions, const CustomBackTextButton()],
  );
}
